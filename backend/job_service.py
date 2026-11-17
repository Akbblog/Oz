"""
Durable scraping-job primitives.

Everything here works on both SQLite and MySQL through ``database.get_db()``.

Design rules
------------
* Job creation is ONE transaction: lock the user row, check limits and balance,
  debit with a conditional UPDATE, insert the job, ledger row and first logs.
  A repeated request with the same ``Idempotency-Key`` returns the original job
  and never charges twice.
* Credit settlement (refund of undelivered work) happens exactly once per job,
  guarded by ``jobs.settled_at IS NULL``.
* A job is owned by one worker at a time (``jobs.worker_id``). Every worker
  write is conditional on that ownership, so a worker that lost its lease can
  never overwrite the state written by the worker that took over.
* Workers heartbeat. A ``running`` job whose heartbeat is stale is requeued and
  resumed from ``completed_cities`` instead of being marked failed.
* Timestamps are stored the way the rest of the app stores them (naive,
  server-local ``datetime.now().isoformat()``) and converted to explicit UTC
  (``...Z``) only at the API boundary, so browsers in any timezone compute
  correct durations.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import re
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Iterable, List, Optional, Tuple
from urllib.parse import unquote, urlparse

from database import _get_db_type, get_db, get_credit_config

logger = logging.getLogger(__name__)

TERMINAL_STATUSES = ("completed", "failed", "cancelled")
ACTIVE_STATUSES = ("pending", "running")

IDEMPOTENCY_KEY_RE = re.compile(r"^[A-Za-z0-9_.:\-]{8,64}$")


# --------------------------------------------------------------------------- #
# Time helpers
# --------------------------------------------------------------------------- #

def now_local() -> datetime:
    """Server-local naive time (matches every other timestamp in the DB)."""
    return datetime.now()


def now_iso() -> str:
    return now_local().isoformat()


def to_api_ts(value: Any) -> Optional[str]:
    """Convert a stored timestamp to an explicit-UTC ISO string (``...Z``).

    Stored values are naive server-local times. ``naive.astimezone()`` treats a
    naive value as local time, which is exactly how it was written (UTC inside
    the Linux container, local time on a developer machine).
    """
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        dt = value
    else:
        raw = str(value).strip()
        try:
            dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except ValueError:
            return raw
    if dt.tzinfo is None:
        dt = dt.astimezone()  # interpret as server-local
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def server_time_api() -> str:
    return to_api_ts(now_local())  # type: ignore[return-value]


def _parse_local(value: Any) -> Optional[datetime]:
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    if dt.tzinfo is not None:
        dt = dt.astimezone().replace(tzinfo=None)
    return dt


# --------------------------------------------------------------------------- #
# SQL dialect helpers
# --------------------------------------------------------------------------- #

def is_mysql() -> bool:
    return _get_db_type() == "mysql"


def insert_ignore_sql(table_and_columns: str, placeholders: str) -> str:
    verb = "INSERT IGNORE INTO" if is_mysql() else "INSERT OR IGNORE INTO"
    return f"{verb} {table_and_columns} VALUES ({placeholders})"


def _begin_write(conn) -> None:
    """Start a write transaction that serialises with other writers."""
    if is_mysql():
        # End any implicit REPEATABLE READ snapshot opened by earlier reads so
        # the consistent reads after the FOR UPDATE lock see fresh data.
        conn.commit()
        return
    if not is_mysql():
        # sqlite3 (legacy isolation) opens transactions lazily; take the write
        # lock now so the balance check and the debit cannot interleave.
        if getattr(conn, "in_transaction", False):
            conn.commit()
        conn.execute("BEGIN IMMEDIATE")


def _is_unique_violation(exc: Exception) -> bool:
    msg = str(exc).lower()
    if "unique constraint failed" in msg or "duplicate entry" in msg:
        return True
    try:
        return int(getattr(exc, "args", [None])[0]) == 1062
    except Exception:
        return False


# --------------------------------------------------------------------------- #
# Result de-duplication
# --------------------------------------------------------------------------- #

_CID_RE = re.compile(r"!1s(0x[0-9a-f]+:0x[0-9a-f]+)", re.IGNORECASE)
_PLACE_ID_RE = re.compile(r"!19s(ChIJ[\w-]+)")
_WS_RE = re.compile(r"\s+")


def dedupe_key_for(result: Dict[str, Any]) -> str:
    """Stable identity for one business, independent of search city.

    Google Maps place URLs carry the feature id (``!1s0x..:0x..``) or place id
    (``!19sChIJ..``) inside the ``data=`` segment; tracking/query parameters
    differ between searches, so the raw URL is not a reliable key.
    """
    url = str(result.get("google_maps_url") or "")
    canonical = ""
    m = _CID_RE.search(url) or _PLACE_ID_RE.search(url)
    if m:
        canonical = "id:" + m.group(1).lower()
    elif url:
        parsed = urlparse(url)
        path = unquote(parsed.path or "")
        # /maps/place/<name>/@lat,lng,zoom/data=... -> keep name + coarse coords
        parts = [p for p in path.split("/") if p]
        name = ""
        coords = ""
        if "place" in parts:
            i = parts.index("place")
            if i + 1 < len(parts):
                name = parts[i + 1].replace("+", " ").lower()
            for p in parts[i + 1:]:
                if p.startswith("@"):
                    bits = p[1:].split(",")
                    if len(bits) >= 2:
                        try:
                            coords = f"{float(bits[0]):.4f},{float(bits[1]):.4f}"
                        except ValueError:
                            coords = ""
                    break
        if name:
            canonical = f"place:{name}|{coords}"
    if not canonical:
        name = _WS_RE.sub(" ", str(result.get("business_name") or "")).strip().lower()
        addr = _WS_RE.sub(" ", str(result.get("address") or "")).strip().lower()
        phone = re.sub(r"\D", "", str(result.get("phone") or ""))
        canonical = f"nap:{name}|{addr}|{phone}"
    return hashlib.sha1(canonical.encode("utf-8")).hexdigest()


# --------------------------------------------------------------------------- #
# Credit cost / refund policy
# --------------------------------------------------------------------------- #

def estimate_cost(num_cities: int, max_results_per_city: int, cfg: Optional[dict] = None) -> int:
    cfg = cfg or get_credit_config()
    num_cities = max(0, int(num_cities))
    max_results_per_city = max(0, int(max_results_per_city))
    cost = cfg["base"] + num_cities * cfg["per_city"] + num_cities * max_results_per_city * cfg["per_result"]
    return int(max(cost, cfg["min_job"]))


REFUND_POLICIES = ("delivered", "unattempted", "none")


def refund_policy() -> str:
    """Billing rule applied when a job settles.

    The owner chose to return credits for unused lead slots. Jobs therefore
    default to ``delivered``; an operator can still select a different policy
    explicitly. Unknown values fall back to the chosen default.
    """
    policy = os.getenv("JOB_REFUND_POLICY", "delivered").strip().lower()
    return policy if policy in REFUND_POLICIES else "delivered"


def refund_policy_warning() -> Optional[str]:
    raw = os.getenv("JOB_REFUND_POLICY")
    if raw is None or not raw.strip():
        return ("JOB_REFUND_POLICY is not set: using 'delivered' (unused lead credits are returned). "
                "Set it explicitly to delivered | unattempted | none.")
    if raw.strip().lower() not in REFUND_POLICIES:
        return f"JOB_REFUND_POLICY={raw!r} is invalid: using 'delivered'. Valid: delivered | unattempted | none."
    return None


def compute_refund(
    *,
    charged: int,
    final_status: str,
    total_cities: int,
    attempted_cities: int,
    leads_delivered: int,
    max_results_per_city: int,
    cfg: Optional[dict] = None,
    policy: Optional[str] = None,
) -> int:
    """Credits to return when a job settles.

    ``delivered`` (default): the user pays the base charge, completed city
        charges, and for leads actually delivered (at least ``min_job``).
        A failed job with no leads, or a cancelled job with no completed city
        and no leads, gets a full refund.
    ``unattempted``: refund only cities that were never attempted, plus a full
        refund when the job failed without delivering anything.
    ``none``: never refund (legacy behaviour).
    """
    cfg = cfg or get_credit_config()
    policy = policy or refund_policy()
    charged = max(0, int(charged or 0))
    if charged == 0 or policy == "none":
        return 0

    attempted = max(0, min(int(attempted_cities or 0), int(total_cities or 0)))
    leads = max(0, int(leads_delivered or 0))

    if policy == "unattempted":
        if final_status == "failed" and leads == 0:
            return charged
        per_city_total = cfg["per_city"] + cfg["per_result"] * max(0, int(max_results_per_city or 0))
        unattempted = max(0, int(total_cities or 0) - attempted)
        return max(0, min(charged, unattempted * per_city_total))

    # delivered
    if leads == 0 and (final_status == "failed" or (final_status == "cancelled" and attempted == 0)):
        return charged
    earned = cfg["base"] + cfg["per_city"] * attempted + cfg["per_result"] * leads
    earned = max(earned, cfg["min_job"])
    return max(0, min(charged, charged - earned))


# --------------------------------------------------------------------------- #
# Job creation (atomic + idempotent)
# --------------------------------------------------------------------------- #

class JobCreateError(Exception):
    def __init__(self, status_code: int, detail: str):
        super().__init__(detail)
        self.status_code = status_code
        self.detail = detail


def normalize_idempotency_key(raw: Optional[str]) -> Optional[str]:
    if raw is None:
        return None
    key = str(raw).strip()
    if not key:
        return None
    if not IDEMPOTENCY_KEY_RE.match(key):
        raise JobCreateError(400, "Invalid Idempotency-Key (8-64 chars: letters, digits, _ . : -)")
    return key


def _find_job_by_key(cursor, user_id: int, key: str) -> Optional[str]:
    cursor.execute(
        "SELECT job_id FROM jobs WHERE user_id = ? AND idempotency_key = ? LIMIT 1",
        (user_id, key),
    )
    row = cursor.fetchone()
    return row[0] if row else None


def create_job_atomic(
    *,
    user_id: int,
    category: str,
    cities: List[str],
    max_results_per_city: int,
    idempotency_key: Optional[str],
    cfg: Optional[dict] = None,
) -> Dict[str, Any]:
    """Charge credits and create the job in one transaction.

    Returns ``{"job_id", "replayed", "credit_cost", "balance_after"}``.
    Raises ``JobCreateError`` with an HTTP status for user-facing failures.
    """
    cfg = cfg or get_credit_config()
    cost = estimate_cost(len(cities), max_results_per_city, cfg)
    now = now_local()
    now_s = now.isoformat()

    conn = get_db()
    try:
        cursor = conn.cursor()

        # Fast path: replay of an already-created job (no lock needed).
        if idempotency_key:
            existing = _find_job_by_key(cursor, user_id, idempotency_key)
            if existing:
                cursor.execute("SELECT credit_balance FROM users WHERE id = ?", (user_id,))
                bal = cursor.fetchone()
                return {
                    "job_id": existing,
                    "replayed": True,
                    "credit_cost": None,
                    "balance_after": int((bal or [0])[0] or 0),
                }

        _begin_write(conn)
        lock_sql = "SELECT credit_balance FROM users WHERE id = ?"
        if is_mysql():
            lock_sql += " FOR UPDATE"
        cursor.execute(lock_sql, (user_id,))
        row = cursor.fetchone()
        if not row:
            conn.rollback()
            raise JobCreateError(404, "User not found")
        balance = int(row[0] or 0)

        # Re-check idempotency under the lock (concurrent duplicate submit).
        if idempotency_key:
            existing = _find_job_by_key(cursor, user_id, idempotency_key)
            if existing:
                conn.rollback()
                return {"job_id": existing, "replayed": True, "credit_cost": None, "balance_after": balance}

        cursor.execute(
            "SELECT COUNT(*) FROM jobs WHERE user_id = ? AND status IN ('pending', 'running')",
            (user_id,),
        )
        concurrent = int((cursor.fetchone() or [0])[0] or 0)
        if concurrent >= int(cfg["max_concurrent_jobs"]):
            conn.rollback()
            raise JobCreateError(
                429,
                f"Maximum concurrent jobs ({cfg['max_concurrent_jobs']}) reached. "
                "Wait for current jobs to complete.",
            )

        cursor.execute(
            "SELECT COUNT(*) FROM jobs WHERE user_id = ? AND created_at >= ?",
            (user_id, (now - timedelta(hours=1)).isoformat()),
        )
        in_hour = int((cursor.fetchone() or [0])[0] or 0)
        if in_hour >= int(cfg["max_jobs_per_hour"]):
            conn.rollback()
            raise JobCreateError(429, f"Hourly job limit ({cfg['max_jobs_per_hour']}) reached. Try again later.")

        if balance < cost:
            conn.rollback()
            raise JobCreateError(402, f"Insufficient credits. Required: {cost}, Available: {balance}")

        cursor.execute(
            "UPDATE users SET credit_balance = credit_balance - ?, credit_updated_at = ? "
            "WHERE id = ? AND credit_balance >= ?",
            (cost, now_s, user_id, cost),
        )
        if cursor.rowcount != 1:
            conn.rollback()
            raise JobCreateError(402, f"Insufficient credits. Required: {cost}, Available: {balance}")
        new_balance = balance - cost

        job_id = str(uuid.uuid4())
        billing_snapshot = json.dumps({key: int(cfg[key]) for key in
                                       ("base", "per_city", "per_result", "min_job")})
        try:
            cursor.execute(
                """
                INSERT INTO jobs (job_id, user_id, category, cities_data, max_results_per_city, status,
                                  total_cities, credit_estimate, credit_charged, created_at,
                                  idempotency_key, completed_cities, failed_cities, attempts, credit_refunded,
                                  billing_snapshot)
                VALUES (?, ?, ?, ?, ?, 'pending', ?, ?, ?, ?, ?, 0, 0, 0, 0, ?)
                """,
                (
                    job_id, user_id, category, json.dumps(cities), max_results_per_city,
                    len(cities), cost, cost, now_s, idempotency_key, billing_snapshot,
                ),
            )
        except Exception as exc:
            conn.rollback()
            if idempotency_key and _is_unique_violation(exc):
                existing = _find_job_by_key(cursor, user_id, idempotency_key)
                if existing:
                    return {"job_id": existing, "replayed": True, "credit_cost": None, "balance_after": balance}
            raise

        cursor.execute(
            """
            INSERT INTO credit_ledger (user_id, job_id, amount, balance_after, transaction_type, reason, created_at, created_by)
            VALUES (?, ?, ?, ?, 'debit', ?, ?, NULL)
            """,
            (user_id, job_id, -cost, new_balance, f"Job charge: {category}"[:250], now_s),
        )
        cursor.executemany(
            "INSERT INTO job_logs (job_id, log_message, created_at) VALUES (?, ?, ?)",
            [
                (job_id, f"Job created for category: {category}", now_s),
                (job_id, f"Credits charged: {cost} ({len(cities)} cities x {max_results_per_city} results)", now_s),
                (job_id, "Queued - waiting for a scraping worker", now_s),
            ],
        )
        conn.commit()
        return {"job_id": job_id, "replayed": False, "credit_cost": cost, "balance_after": new_balance}
    finally:
        try:
            conn.close()
        except Exception:
            pass


# --------------------------------------------------------------------------- #
# Settlement (exactly-once refunds)
# --------------------------------------------------------------------------- #

def settle_job_credits(job_id: str) -> int:
    """Refund undelivered work for a terminal job. Safe to call repeatedly.

    Returns the number of credits refunded by THIS call (0 if already settled,
    not terminal, or nothing to refund).
    """
    conn = get_db()
    try:
        cursor = conn.cursor()
        _begin_write(conn)
        lock = " FOR UPDATE" if is_mysql() else ""
        cursor.execute(
            "SELECT user_id, status, credit_charged, total_cities, completed_cities, failed_cities, "
            "max_results_per_city, settled_at, category, billing_snapshot FROM jobs WHERE job_id = ?" + lock,
            (job_id,),
        )
        row = cursor.fetchone()
        if not row:
            conn.rollback()
            return 0
        user_id, status, charged, total, completed, failed, max_results, settled_at, category, billing_snapshot = row
        if settled_at or status not in TERMINAL_STATUSES:
            conn.rollback()
            return 0

        cursor.execute("SELECT COUNT(*) FROM results WHERE job_id = ?", (job_id,))
        leads = int((cursor.fetchone() or [0])[0] or 0)
        attempted = int(completed or 0)
        try:
            saved_cfg = json.loads(billing_snapshot) if billing_snapshot else None
            if saved_cfg is not None:
                saved_cfg = {key: int(saved_cfg[key]) for key in
                             ("base", "per_city", "per_result", "min_job")}
        except (TypeError, ValueError, KeyError):
            logger.warning("Job %s has an invalid billing snapshot; using current prices", job_id)
            saved_cfg = None
        refund = compute_refund(
            charged=int(charged or 0),
            final_status=str(status),
            total_cities=int(total or 0),
            attempted_cities=attempted,
            leads_delivered=leads,
            max_results_per_city=int(max_results or 0),
            cfg=saved_cfg,
        )
        now_s = now_iso()
        cursor.execute(
            "UPDATE jobs SET settled_at = ?, credit_refunded = ? WHERE job_id = ? AND settled_at IS NULL",
            (now_s, refund, job_id),
        )
        if cursor.rowcount != 1:
            conn.rollback()
            return 0
        if refund > 0:
            cursor.execute(
                "UPDATE users SET credit_balance = credit_balance + ?, credit_updated_at = ? WHERE id = ?",
                (refund, now_s, user_id),
            )
            cursor.execute("SELECT credit_balance FROM users WHERE id = ?", (user_id,))
            new_balance = int((cursor.fetchone() or [0])[0] or 0)
            cursor.execute(
                """
                INSERT INTO credit_ledger (user_id, job_id, amount, balance_after, transaction_type, reason, created_at, created_by)
                VALUES (?, ?, ?, ?, 'refund', ?, ?, NULL)
                """,
                (user_id, job_id, refund, new_balance,
                 f"Refund for undelivered work ({status}, {leads} leads)"[:250], now_s),
            )
            cursor.execute(
                "INSERT INTO job_logs (job_id, log_message, created_at) VALUES (?, ?, ?)",
                (job_id, f"Credits refunded: {refund} (charged {charged}, {leads} leads delivered)", now_s),
            )
        conn.commit()
        return refund
    except Exception:
        try:
            conn.rollback()
        except Exception:
            pass
        raise
    finally:
        try:
            conn.close()
        except Exception:
            pass


def settle_unsettled_terminal_jobs(limit: int = 50) -> int:
    """Safety net: settle terminal jobs that were never settled (e.g. crash)."""
    conn = get_db()
    try:
        cursor = conn.cursor()
        cursor.execute(
            # attempts > 0: only jobs the durable runner actually ran. Jobs finished by
            # older code (e.g. during a rollback window) were billed under the old
            # no-refund rules and must never be refunded retroactively.
            "SELECT job_id FROM jobs WHERE status IN ('completed', 'failed', 'cancelled') "
            "AND settled_at IS NULL AND COALESCE(attempts, 0) > 0 "
            "AND (worker_id IS NULL OR heartbeat_at IS NULL OR heartbeat_at < ?) "
            "ORDER BY created_at LIMIT " + str(int(limit)),
            ((now_local() - timedelta(seconds=stale_seconds())).isoformat(),),
        )
        ids = [r[0] for r in cursor.fetchall()]
    finally:
        conn.close()
    total = 0
    for jid in ids:
        try:
            total += settle_job_credits(jid)
        except Exception as exc:  # keep going; next sweep retries
            logger.error("Settlement failed for job %s: %r", jid, exc)
    return total


# --------------------------------------------------------------------------- #
# Worker ownership: claim / heartbeat / requeue
# --------------------------------------------------------------------------- #

def stale_seconds() -> int:
    try:
        return max(30, int(os.getenv("JOB_STALE_SECONDS", "120")))
    except ValueError:
        return 120


def max_attempts() -> int:
    try:
        return max(1, int(os.getenv("JOB_MAX_ATTEMPTS", "3")))
    except ValueError:
        return 3


def max_job_hours() -> float:
    try:
        return max(0.5, float(os.getenv("JOB_MAX_HOURS", "12")))
    except ValueError:
        return 12.0


def add_log(job_id: str, message: str, cursor=None) -> None:
    if cursor is not None:
        cursor.execute(
            "INSERT INTO job_logs (job_id, log_message, created_at) VALUES (?, ?, ?)",
            (job_id, message, now_iso()),
        )
        return
    conn = get_db()
    try:
        c = conn.cursor()
        c.execute(
            "INSERT INTO job_logs (job_id, log_message, created_at) VALUES (?, ?, ?)",
            (job_id, message, now_iso()),
        )
        conn.commit()
    finally:
        conn.close()


def list_claimable_job_ids(limit: int) -> List[str]:
    conn = get_db()
    try:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT job_id FROM jobs WHERE status = 'pending' ORDER BY created_at LIMIT " + str(int(max(0, limit))),
        )
        return [r[0] for r in cursor.fetchall()]
    finally:
        conn.close()


def claim_job(job_id: str, worker_id: str) -> bool:
    """Atomically take ownership of a pending job."""
    conn = get_db()
    try:
        cursor = conn.cursor()
        now_s = now_iso()
        cursor.execute(
            "UPDATE jobs SET status = 'running', worker_id = ?, heartbeat_at = ?, "
            "attempts = COALESCE(attempts, 0) + 1 WHERE job_id = ? AND status = 'pending'",
            (worker_id, now_s, job_id),
        )
        ok = cursor.rowcount == 1
        conn.commit()
        return ok
    finally:
        conn.close()


def heartbeat(job_id: str, worker_id: str) -> bool:
    """Refresh the lease. Returns False if this worker no longer owns the job."""
    conn = get_db()
    try:
        cursor = conn.cursor()
        cursor.execute(
            "UPDATE jobs SET heartbeat_at = ? WHERE job_id = ? AND worker_id = ? AND status = 'running'",
            (now_iso(), job_id, worker_id),
        )
        ok = cursor.rowcount == 1
        conn.commit()
        return ok
    finally:
        conn.close()


def _legacy_completed_cities(cursor, job_id: str) -> int:
    """For jobs created before migration 014: count finished cities from logs."""
    cursor.execute(
        "SELECT COUNT(*) FROM job_logs WHERE job_id = ? AND log_message LIKE ?",
        (job_id, "Found % businesses in %"),
    )
    return int((cursor.fetchone() or [0])[0] or 0)


def requeue_stale_jobs() -> Tuple[int, int]:
    """Requeue running jobs whose worker stopped heartbeating.

    Returns (requeued, failed). Jobs over ``JOB_MAX_ATTEMPTS`` or older than
    ``JOB_MAX_HOURS`` are failed (and later settled) instead of requeued.
    """
    cutoff = (now_local() - timedelta(seconds=stale_seconds())).isoformat()
    too_old = (now_local() - timedelta(hours=max_job_hours())).isoformat()
    conn = get_db()
    requeued = failed = 0
    try:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT job_id, attempts, completed_cities, heartbeat_at, created_at FROM jobs "
            "WHERE status = 'running' AND (heartbeat_at IS NULL OR heartbeat_at < ?)",
            (cutoff,),
        )
        rows = cursor.fetchall()
        for job_id, attempts, completed, hb, created in rows:
            attempts = int(attempts or 0)
            now_s = now_iso()
            if attempts >= max_attempts() or (created and str(created) < too_old):
                reason = (
                    "Job stopped: worker was interrupted too many times"
                    if attempts >= max_attempts()
                    else "Job timed out: exceeded maximum allowed duration"
                )
                cursor.execute(
                    "UPDATE jobs SET status = 'failed', error = ?, completed_at = ?, worker_id = NULL "
                    "WHERE job_id = ? AND status = 'running' AND (heartbeat_at IS NULL OR heartbeat_at < ?)",
                    (reason, now_s, job_id, cutoff),
                )
                if cursor.rowcount == 1:
                    add_log(job_id, reason, cursor)
                    failed += 1
                continue
            resume_at = int(completed or 0)
            if hb is None and resume_at == 0:
                resume_at = _legacy_completed_cities(cursor, job_id)
            cursor.execute(
                "UPDATE jobs SET status = 'pending', worker_id = NULL, completed_cities = ? "
                "WHERE job_id = ? AND status = 'running' AND (heartbeat_at IS NULL OR heartbeat_at < ?)",
                (resume_at, job_id, cutoff),
            )
            if cursor.rowcount == 1:
                add_log(job_id, f"Worker interrupted - job will resume from city {resume_at + 1}", cursor)
                requeued += 1
        conn.commit()
    finally:
        conn.close()
    return requeued, failed


# --------------------------------------------------------------------------- #
# Read model for the API
# --------------------------------------------------------------------------- #

def parse_cities(raw: Any) -> List[str]:
    cities: List[str] = []
    if not raw:
        return cities
    try:
        data = json.loads(raw) if isinstance(raw, str) else raw
    except (json.JSONDecodeError, TypeError):
        return cities
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict):
                city = item.get("city", "")
                state = item.get("state", "")
                if city:
                    cities.append(f"{city}, {state}" if state else city)
            elif isinstance(item, str) and item.strip():
                cities.append(item.strip())
    return cities


_JOB_COLUMNS = (
    "job_id, user_id, category, cities_data, max_results_per_city, status, progress, total_cities, "
    "current_city, error, created_at, completed_at, credit_charged, credit_refunded, completed_cities, "
    "failed_cities, attempts, heartbeat_at, settled_at, worker_id"
)

RESULT_COLUMNS = "business_name, phone, website, email, address, category, city, state, google_maps_url"


def _result_dict(row: Iterable[Any]) -> Dict[str, Any]:
    keys = RESULT_COLUMNS.replace(" ", "").split(",")
    return dict(zip(keys, row))


def fetch_job_row(cursor, job_id: str, user_id: Optional[int] = None) -> Optional[Dict[str, Any]]:
    sql = f"SELECT {_JOB_COLUMNS} FROM jobs WHERE job_id = ?"
    params: Tuple[Any, ...] = (job_id,)
    if user_id is not None:
        sql += " AND user_id = ?"
        params = (job_id, user_id)
    cursor.execute(sql, params)
    row = cursor.fetchone()
    if not row:
        return None
    keys = [k.strip() for k in _JOB_COLUMNS.split(",")]
    return dict(zip(keys, row))


def job_payload(
    cursor,
    job: Dict[str, Any],
    *,
    include_results: bool = True,
    logs_after: Optional[int] = None,
    log_limit: int = 1000,
) -> Dict[str, Any]:
    job_id = job["job_id"]
    cursor.execute("SELECT COUNT(*) FROM results WHERE job_id = ?", (job_id,))
    result_count = int((cursor.fetchone() or [0])[0] or 0)

    if logs_after is not None:
        cursor.execute(
            "SELECT id, log_message, created_at FROM job_logs WHERE job_id = ? AND id > ? ORDER BY id LIMIT "
            + str(int(log_limit)),
            (job_id, int(logs_after)),
        )
        log_rows = cursor.fetchall()
    else:
        cursor.execute(
            "SELECT id, log_message, created_at FROM job_logs WHERE job_id = ? ORDER BY id DESC LIMIT "
            + str(int(log_limit)),
            (job_id,),
        )
        log_rows = list(reversed(cursor.fetchall()))

    log_entries = [
        {"id": int(r[0]), "message": r[1], "created_at": to_api_ts(r[2])} for r in log_rows
    ]
    next_cursor = log_entries[-1]["id"] if log_entries else (int(logs_after) if logs_after is not None else 0)

    results: List[Dict[str, Any]] = []
    if include_results:
        cursor.execute(f"SELECT {RESULT_COLUMNS} FROM results WHERE job_id = ? ORDER BY id", (job_id,))
        results = [_result_dict(r) for r in cursor.fetchall()]

    status = str(job.get("status") or "pending")
    total = int(job.get("total_cities") or 0)
    completed = int(job.get("completed_cities") or 0)
    progress = int(job.get("progress") or 0)
    if status == "completed":
        progress = 100
    elif status in ACTIVE_STATUSES:
        progress = min(progress, 99)

    cities = parse_cities(job.get("cities_data"))
    from locations import derive_job_location

    return {
        "job_id": job_id,
        "status": status,
        "category": job.get("category"),
        "cities": cities,
        # Derived at read time from the stored city strings; never written back.
        **derive_job_location(cities),
        "max_results_per_city": job.get("max_results_per_city"),
        "progress": progress,
        "total_cities": total,
        "completed_cities": completed,
        "failed_cities": int(job.get("failed_cities") or 0),
        "current_city": job.get("current_city") or "",
        "result_count": result_count,
        "results": results,
        "results_included": include_results,
        "error": job.get("error"),
        "created_at": to_api_ts(job.get("created_at")),
        "completed_at": to_api_ts(job.get("completed_at")),
        "heartbeat_at": to_api_ts(job.get("heartbeat_at")),
        "server_time": server_time_api(),
        "credit_charged": int(job.get("credit_charged") or 0),
        "credit_refunded": int(job.get("credit_refunded") or 0),
        "settled": bool(job.get("settled_at")),
        "attempts": int(job.get("attempts") or 0),
        "logs": [e["message"] for e in log_entries],
        "log_entries": log_entries,
        "next_log_cursor": next_cursor,
    }
