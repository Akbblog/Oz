"""Admin credit reporting: ledger classification, per-account reconciliation,
time-windowed overview metrics and dependency health checks.

This module only reads. Every report runs inside ONE read-only transaction
with a consistent snapshot, so the balance, the ledger and the related jobs /
payments all describe the same instant (see ``_snapshot``).

Why it exists (docs/ADMIN_CREDIT_REPORTING.md): the old admin KPIs counted every
``transaction_type='credit'`` row as a purchase, so free signup credits and
staff grants showed as "Credits Purchased"; "Credits Used" summed gross search
charges and ignored refunds; and the overview put a "Last 24h" label above
lifetime totals.

Ledger facts this relies on (verified against every writer in the codebase):

* ``credit``      signup credits (exact approval reasons, written by the approval
                  flow: ``created_by`` equals ``users.approved_by`` and the row is
                  written within seconds of ``users.approved_at``); staff grants and
                  approved credit requests (``created_by`` = staff user id); and
                  payments, written by the system (``created_by`` NULL) with reason
                  "Safepay payment <tracker>[ [env]]" or legacy "Payment confirmed"
                  and, in the same write path, a ``credit_expiry`` row with
                  ``expiry_type='purchased'`` pointing at the ledger row.
* ``debit``       search charges (``job_id`` set).
* ``refund``      settlement refunds for undelivered work (``job_id`` set).
* ``bonus``       promo bonus credits and referral rewards.
* ``promotional`` subscription renewals.
"""
from __future__ import annotations

import logging
import os
import re
import time
import urllib.request
from contextlib import contextmanager
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Dict, Iterable, Iterator, List, Optional, Set, Tuple

from database import get_db

logger = logging.getLogger(__name__)

# --------------------------------------------------------------------------- #
# Consistent read-only snapshot
# --------------------------------------------------------------------------- #


def _is_mysql() -> bool:
    try:
        import database

        return database._get_db_type() == "mysql"
    except Exception:
        return False


@contextmanager
def _snapshot() -> Iterator[Any]:
    """Yield a cursor whose reads all see one consistent, read-only snapshot.

    MariaDB/MySQL: production runs READ COMMITTED, where every statement sees a
    new snapshot, so a charge committed between "read balance" and "read ledger"
    would make a healthy account look unreconciled. Force REPEATABLE READ for this
    one transaction and take the snapshot up front.

    SQLite: an explicit BEGIN holds a shared lock for the whole read; concurrent
    writers wait until it ends.
    """
    conn = get_db()
    cur = conn.cursor()
    try:
        try:
            conn.rollback()  # no transaction may be open before SET TRANSACTION
        except Exception:
            pass
        if _is_mysql():
            cur.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
            cur.execute("START TRANSACTION WITH CONSISTENT SNAPSHOT, READ ONLY")
        else:
            cur.execute("BEGIN")
        yield cur
    finally:
        try:
            conn.rollback()
        except Exception:
            pass
        conn.close()


# --------------------------------------------------------------------------- #
# Classification
# --------------------------------------------------------------------------- #

CATEGORY_LABELS: Dict[str, str] = {
    "starting_credits": "Free signup credits",
    "purchase": "Paid credits",
    "sandbox_test": "Sandbox test credits (not paid)",
    "purchase_unverified": "Unmatched payment credit",
    "admin_grant": "Staff grant",
    "promo_bonus": "Promo / referral bonus",
    "subscription_allocation": "Subscription allocation",
    "job_charge": "Search charge",
    "job_refund": "Search refund",
    "other_credit": "Other credit (unclassified)",
    "other_debit": "Other debit (unclassified)",
}

_SAFEPAY_REASON = re.compile(r"^Safepay payment (\S+?)(?: \[([a-z]+)\])?$")
_SAFEPAY_BONUS_REASON = re.compile(r"^Promo bonus credits \((\S+?)\)(?: \[([a-z]+)\])?$")
_SAFEPAY_REASON_LOOSE = re.compile(r"^Safepay payment (\S+)")  # display redaction only
_SAFEPAY_BONUS_LOOSE = re.compile(r"^Promo bonus credits \((\S+?)\)")
_LEGACY_PAYMENT_REASON = "Payment confirmed"
_LIVE_ENVIRONMENTS = (None, "", "production", "live")
# Written only by the approval flows (auto-approval, single and bulk approval).
_SIGNUP_REASONS = frozenset({
    "Starting credits on auto-approval",
    "Starting credits on account approval",
    "Starting credits on account approval (bulk)",
})
_SIGNUP_MAX_DELAY = timedelta(minutes=10)


def _is_live_env(env: Any) -> bool:
    return (env if env is None else str(env).strip().lower()) in _LIVE_ENVIRONMENTS


def _is_paid_env(payment: Dict[str, Any]) -> bool:
    """Safepay must say 'production' explicitly; legacy providers predate the column."""
    env = payment.get("environment")
    if payment.get("provider") == "safepay":
        return str(env or "").strip().lower() == "production"
    return _is_live_env(env)


def _parse_ts(value: Any) -> Optional[datetime]:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.replace(tzinfo=None)
    try:
        raw = str(value).strip().replace(" ", "T")
        return datetime.fromisoformat(raw[:26] if "+" not in raw[10:] else raw).replace(tzinfo=None)
    except ValueError:
        try:
            return datetime.fromisoformat(str(value).strip().replace(" ", "T")[:19])
        except ValueError:
            return None


def _verify_signups(entries: Iterable[Dict[str, Any]], approved_by: Any, approved_at: Any) -> Set[int]:
    """Ledger ids that are the account's real signup grant.

    The approval flows write exactly one row with a known reason, by the
    approving actor (NULL for auto-approval), seconds after ``approved_at``.
    A staff member typing "Starting credits…" into a manual grant fails at
    least one of these checks and stays a staff grant.
    """
    approved = _parse_ts(approved_at)
    approver = None if approved_by is None else int(approved_by)
    for e in sorted(entries, key=lambda x: x["id"]):
        if e.get("transaction_type") != "credit" or e.get("job_id"):
            continue
        if str(e.get("reason") or "") not in _SIGNUP_REASONS:
            continue
        actor = e.get("created_by")
        if (None if actor is None else int(actor)) != approver:
            continue
        written = _parse_ts(e.get("created_at"))
        if approved is None or written is None or abs(written - approved) > _SIGNUP_MAX_DELAY:
            continue
        return {e["id"]}  # one signup grant per account
    return set()


def _looks_like_payment(entry: Dict[str, Any]) -> bool:
    reason = str(entry.get("reason") or "")
    return bool(_SAFEPAY_REASON_LOOSE.match(reason)) or reason == _LEGACY_PAYMENT_REASON


def classify_entry(entry: Dict[str, Any], payment: Optional[Dict[str, Any]] = None,
                   signup: bool = False) -> str:
    """Return the reporting category for one ledger row.

    ``payment`` must only be passed when ``_match_payments`` verified the row's
    provenance (system-written, exact reason, purchased credit_expiry link,
    completed payment of the same amount, first claim on that payment).
    ``signup`` must only be True when ``_verify_signups`` accepted the row.
    """
    t = str(entry.get("transaction_type") or "").strip().lower()
    reason = str(entry.get("reason") or "")
    amount = int(entry.get("amount") or 0)
    has_job = bool(entry.get("job_id"))
    by_staff = entry.get("created_by") is not None

    if t == "debit":
        return "job_charge" if has_job else "other_debit"
    if t == "refund":
        return "job_refund" if has_job else "other_credit"
    if t == "bonus":
        if by_staff:
            return "admin_grant"
        if payment is not None and not _is_paid_env(payment):
            return "sandbox_test"
        if payment is None and _SAFEPAY_BONUS_REASON.match(reason) and reason.endswith("[sandbox]"):
            return "sandbox_test"
        return "promo_bonus"
    if t == "promotional":
        return "subscription_allocation"
    if t == "credit":
        if signup:
            return "starting_credits"
        if by_staff:
            # Staff can type anything as a reason ("Starting credits…", "Safepay
            # payment…"); text never turns a grant into signup credit or a purchase.
            return "admin_grant"
        if _looks_like_payment(entry):
            if payment is None or str(payment.get("status") or "").lower() != "completed":
                return "purchase_unverified"
            return "purchase" if _is_paid_env(payment) else "sandbox_test"
        return "other_credit"
    return "other_credit" if amount >= 0 else "other_debit"


def _match_payments(entries: List[Dict[str, Any]], payments: List[Dict[str, Any]],
                    purchased_links: Dict[int, int]) -> Dict[int, Dict[str, Any]]:
    """Map ledger entry id -> payment row, for entries whose provenance checks out.

    A payment credit is matched only when ALL hold:
      * the row was written by the system (``created_by`` NULL), not by staff;
      * its reason has the exact format the payment path writes;
      * the payment path's ``credit_expiry`` row ('purchased') links to this
        ledger id with the same amount (``purchased_links``);
      * a payment of the same user is ``completed``, has
        ``credits_purchased == amount`` and, for Safepay, the same tracker and
        an environment that agrees with the reason's ``[env]`` tag;
      * no earlier ledger row already claimed that payment (counted once).
    Bonus rows only need tracker + same user (they are never paid credits).
    """
    by_tracker: Dict[str, Dict[str, Any]] = {}
    legacy_pool: List[Dict[str, Any]] = []
    for p in payments:
        tracker = p.get("provider_transaction_id")
        if p.get("provider") == "safepay" and tracker:
            by_tracker[str(tracker)] = p
        elif p.get("provider") != "safepay" and str(p.get("status")).lower() == "completed":
            legacy_pool.append(p)
    legacy_pool.sort(key=lambda p: p["id"])
    claimed: Set[int] = set()
    matched: Dict[int, Dict[str, Any]] = {}
    for e in sorted(entries, key=lambda x: x["id"]):
        if e.get("created_by") is not None or e.get("job_id"):
            continue
        reason = str(e.get("reason") or "")
        amount = int(e.get("amount") or 0)
        ttype = e.get("transaction_type")
        if ttype == "bonus":
            m = _SAFEPAY_BONUS_REASON.match(reason)
            if m and m.group(1) in by_tracker:
                matched[e["id"]] = by_tracker[m.group(1)]
            continue
        if ttype != "credit" or purchased_links.get(e["id"]) != amount:
            continue
        m = _SAFEPAY_REASON.match(reason)
        if m:
            p = by_tracker.get(m.group(1))
            if p is None or p["id"] in claimed:
                continue
            tag = m.group(2)
            env = str(p.get("environment") or "").strip().lower()
            # Untagged reason = production payment; the payment row must say so explicitly.
            env_ok = (tag is None and env == "production") or (tag is not None and env == tag)
            if str(p.get("status")).lower() == "completed" and int(p.get("credits") or 0) == amount and env_ok:
                matched[e["id"]] = p
                claimed.add(p["id"])
            continue
        if reason == _LEGACY_PAYMENT_REASON:
            for i, p in enumerate(legacy_pool):
                if int(p.get("credits") or 0) == amount:
                    matched[e["id"]] = legacy_pool.pop(i)
                    claimed.add(p["id"])
                    break
    return matched


def _display_reason(entry: Dict[str, Any], payment: Optional[Dict[str, Any]]) -> str:
    """Reason text without raw provider identifiers."""
    reason = str(entry.get("reason") or "")
    ref = f"payment #{payment['id']}" if payment is not None else "unmatched payment"
    reason = _SAFEPAY_REASON_LOOSE.sub(f"Safepay {ref}", reason, count=1)
    reason = _SAFEPAY_BONUS_LOOSE.sub(f"Promo bonus credits ({ref})", reason, count=1)
    return reason


# --------------------------------------------------------------------------- #
# Per-account report
# --------------------------------------------------------------------------- #

def _rows(cursor, sql: str, params: Tuple = ()) -> List[tuple]:
    cursor.execute(sql, params)
    return list(cursor.fetchall() or [])


def _load_account(cursor, user_id: int) -> Optional[Dict[str, Any]]:
    rows = _rows(cursor, "SELECT id, username, credit_balance, created_at, approved_by, approved_at "
                         "FROM users WHERE id = ?", (user_id,))
    if not rows:
        return None
    r = rows[0]
    entries = [
        {"id": int(x[0]), "job_id": x[1], "amount": int(x[2] or 0),
         "balance_after": None if x[3] is None else int(x[3]),
         "transaction_type": x[4], "reason": x[5], "created_at": x[6],
         "created_by": None if x[7] is None else int(x[7])}
        for x in _rows(cursor,
                       "SELECT id, job_id, amount, balance_after, transaction_type, reason, created_at, created_by "
                       "FROM credit_ledger WHERE user_id = ? ORDER BY id", (user_id,))
    ]
    payments = [
        {"id": int(x[0]), "provider": x[1], "provider_transaction_id": x[2], "environment": x[3],
         "status": x[4], "credits": int(x[5] or 0), "amount_cents": int(x[6] or 0), "currency": x[7],
         "created_at": x[8], "completed_at": x[9]}
        for x in _rows(cursor,
                       "SELECT id, payment_provider, provider_transaction_id, provider_environment, status, "
                       "credits_purchased, amount_cents, currency, created_at, completed_at "
                       "FROM payment_transactions WHERE user_id = ? ORDER BY id", (user_id,))
    ]
    purchased_links = {
        int(x[0]): int(x[1] or 0)
        for x in _rows(cursor,
                       "SELECT credit_ledger_id, credits_granted FROM credit_expiry "
                       "WHERE user_id = ? AND expiry_type = 'purchased' AND credit_ledger_id IS NOT NULL", (user_id,))
    }
    jobs = {
        str(x[0]): {"job_id": str(x[0]), "status": x[1], "category": x[2],
                    "credit_charged": int(x[3] or 0), "credit_refunded": int(x[4] or 0), "leads": int(x[5] or 0),
                    "created_at": x[6]}
        for x in _rows(cursor,
                       "SELECT j.job_id, j.status, j.category, j.credit_charged, j.credit_refunded, "
                       "(SELECT COUNT(*) FROM results r WHERE r.job_id = j.job_id), j.created_at "
                       "FROM jobs j WHERE j.user_id = ?", (user_id,))
    }
    creator_ids = sorted({e["created_by"] for e in entries if e["created_by"] is not None})
    creators: Dict[int, str] = {}
    if creator_ids:
        ph = ", ".join("?" for _ in creator_ids)
        for x in _rows(cursor, f"SELECT id, username FROM users WHERE id IN ({ph})", tuple(creator_ids)):
            creators[int(x[0])] = x[1]
    return {
        "user": {"id": int(r[0]), "username": r[1], "credit_balance": int(r[2] or 0), "created_at": r[3],
                 "approved_by": r[4], "approved_at": r[5]},
        "entries": entries, "payments": payments, "purchased_links": purchased_links,
        "jobs": jobs, "creators": creators,
    }


def reconcile(entries: Iterable[Dict[str, Any]], current_balance: int) -> Dict[str, Any]:
    """Check that the ledger explains the balance.

    Two independent checks, both from an opening balance of 0 (a user row is
    created with 0 credits unless the signup path also writes its ledger row):

    * sum:   sum(amount) == users.credit_balance
    * chain: every row's balance_after == previous balance_after + amount
    """
    entries = list(entries)
    ledger_sum = sum(int(e.get("amount") or 0) for e in entries)
    breaks: List[Dict[str, Any]] = []
    prev = 0
    for e in entries:
        expected = prev + int(e.get("amount") or 0)
        actual = e.get("balance_after")
        if actual is None or int(actual) != expected:
            breaks.append({"entry_id": e["id"], "expected_balance_after": expected,
                           "recorded_balance_after": actual})
        prev = expected if actual is None else int(actual)
    last_recorded = prev if entries else 0
    difference = int(current_balance) - ledger_sum
    if not entries and int(current_balance) == 0:
        status = "no_history"
    elif difference == 0 and not breaks:
        status = "reconciled"
    else:
        status = "mismatch"
    return {
        "status": status,
        "opening_balance": 0,
        "ledger_sum": ledger_sum,
        "current_balance": int(current_balance),
        "last_recorded_balance_after": last_recorded,
        "difference": difference,
        "chain_breaks": len(breaks),
        "first_chain_break": breaks[0] if breaks else None,
    }


def build_credit_report(account: Dict[str, Any], page: int = 1, page_size: int = 25) -> Dict[str, Any]:
    entries = account["entries"]
    jobs = account["jobs"]
    matched = _match_payments(entries, account["payments"], account.get("purchased_links", {}))
    user = account["user"]
    signups = _verify_signups(entries, user.get("approved_by"), user.get("approved_at"))

    totals = {k: 0 for k in CATEGORY_LABELS}
    counts = {k: 0 for k in CATEGORY_LABELS}
    chain_prev = 0
    items: List[Dict[str, Any]] = []
    for e in entries:
        pay = matched.get(e["id"])
        cat = classify_entry(e, pay, signup=e["id"] in signups)
        totals[cat] += abs(int(e["amount"]))
        counts[cat] += 1
        expected = chain_prev + int(e["amount"])
        chain_ok = e["balance_after"] is not None and int(e["balance_after"]) == expected
        chain_prev = expected if e["balance_after"] is None else int(e["balance_after"])
        job = None
        if e["job_id"]:
            j = jobs.get(str(e["job_id"]))
            job = {"job_id": str(e["job_id"]), "exists": j is not None}
            if j is not None:
                job.update({"status": j["status"], "category": j["category"], "leads": j["leads"],
                            "credit_charged": j["credit_charged"], "credit_refunded": j["credit_refunded"]})
        items.append({
            "id": e["id"],
            "created_at": e["created_at"],
            "transaction_type": e["transaction_type"],
            "category": cat,
            "category_label": CATEGORY_LABELS[cat],
            "amount": int(e["amount"]),
            "balance_after": e["balance_after"],
            "expected_balance_after": expected,
            "chain_ok": chain_ok,
            "reason": _display_reason(e, pay),
            "granted_by": account["creators"].get(e["created_by"]) if e["created_by"] is not None else None,
            "job": job,
            "payment": None if pay is None else {
                "id": pay["id"], "provider": pay["provider"], "environment": pay["environment"] or "unknown",
                "status": pay["status"], "credits": pay["credits"], "amount_cents": pay["amount_cents"],
                "currency": pay["currency"],
            },
        })

    balance = account["user"]["credit_balance"]
    rec = reconcile(entries, balance)

    gross = totals["job_charge"]
    refunds = totals["job_refund"]
    on_file = list(jobs.values())
    leads_on_file = sum(j["leads"] for j in on_file)
    net_on_file = sum(j["credit_charged"] - j["credit_refunded"] for j in on_file)
    deleted_job_ids = {str(e["job_id"]) for e in entries if e["job_id"] and str(e["job_id"]) not in jobs}
    paid_payment_ids = {matched[e["id"]]["id"] for e in items if e["category"] == "purchase"}

    summary = {
        # The six headline figures, in display order:
        "starting_credits": totals["starting_credits"],
        "paid_credits": totals["purchase"],
        "job_charges_gross": gross,
        "job_refunds": refunds,
        "job_charges_net": gross - refunds,
        "current_balance": balance,
        # Other sources, kept separate:
        "admin_grants": totals["admin_grant"],
        "sandbox_test_credits": totals["sandbox_test"],
        "unverified_payment_credits": totals["purchase_unverified"],
        "promo_bonus_credits": totals["promo_bonus"],
        "subscription_credits": totals["subscription_allocation"],
        "other_credits": totals["other_credit"],
        "other_debits": totals["other_debit"],
        "confirmed_paid_payments": len(paid_payment_ids),
        "searches_on_file": len(on_file),
        "leads_on_file": leads_on_file,
        "net_credits_for_searches_on_file": net_on_file,
        "net_credits_per_lead_on_file": round(net_on_file / leads_on_file, 2) if leads_on_file else None,
        "charged_searches_since_deleted": len(deleted_job_ids),
    }

    page_size = max(1, min(int(page_size or 25), 200))
    total = len(items)
    pages = max(1, (total + page_size - 1) // page_size)
    page = max(1, min(int(page or 1), pages))
    newest_first = list(reversed(items))
    start = (page - 1) * page_size
    return {
        "user_id": account["user"]["id"],
        "username": account["user"]["username"],
        "summary": summary,
        "category_counts": counts,
        "reconciliation": rec,
        "transactions": newest_first[start:start + page_size],
        "pagination": {"page": page, "page_size": page_size, "total": total, "pages": pages},
        "definitions": ACCOUNT_DEFINITIONS,
    }


ACCOUNT_DEFINITIONS = {
    "starting_credits": "Free signup credits: the one grant written by the approval flow (exact reason, written by the approver within minutes of approval). Not a purchase. A manual grant with similar text is a staff grant.",
    "paid_credits": "Paid credits: system-written payment credits whose completed payment is explicitly 'production', has the same amount and is linked by the payment path. Each payment counts once across the account's whole ledger.",
    "job_charges_gross": "Search charges: every credit charged when searches started, before any refund.",
    "job_refunds": "Search refunds: credits returned at settlement for work a search did not deliver.",
    "job_charges_net": "Net search usage: search charges minus search refunds.",
    "current_balance": "Current balance: users.credit_balance in the same snapshot as the history.",
    "admin_grants": "Staff grants: credits added by a staff member (manual grants, approved credit requests), whatever their reason text says.",
    "sandbox_test_credits": "Sandbox test credits: Safepay sandbox payments and their promo bonuses. No money was charged.",
    "unverified_payment_credits": "Unmatched payment credits: rows that look like payments but fail a provenance check (no completed payment, amount differs, payment already counted, or no payment-path link).",
    "net_credits_per_lead_on_file": "Net credits (charged minus refunded) for searches that still exist, divided by the leads those searches hold.",
    "reconciliation": "Reconciled when, in one consistent snapshot, the ledger amounts sum (from 0) to the current balance AND every row's balance_after equals the previous row's balance_after plus its amount.",
}


def get_user_credit_report(user_id: int, page: int = 1, page_size: int = 25) -> Optional[Dict[str, Any]]:
    with _snapshot() as cur:
        account = _load_account(cur, int(user_id))
    if account is None:
        return None
    return build_credit_report(account, page=page, page_size=page_size)


# --------------------------------------------------------------------------- #
# Overview (time windowed)
# --------------------------------------------------------------------------- #

RANGES: Dict[str, Tuple[Optional[timedelta], str]] = {
    "24h": (timedelta(hours=24), "Last 24 hours"),
    "7d": (timedelta(days=7), "Last 7 days"),
    "30d": (timedelta(days=30), "Last 30 days"),
    "all": (None, "All time"),
}

# Timestamps are TEXT in mixed formats ("2026-01-10T09:56:30.6" and
# "2026-01-10 09:56:30"); a plain string compare puts every space-separated row
# before every T-separated one on the same day. Normalise the separator first.
# All writers use the server clock (UTC in production).
_TS = "REPLACE(CAST({col} AS CHAR), 'T', ' ')"


def _window_clause(col: str, start: Optional[str], end: str) -> Tuple[str, Tuple]:
    """Both bounds: start <= ts <= end (start omitted for 'all')."""
    ts = _TS.format(col=col)
    if start is None:
        return f"{ts} <= ?", (end + ".999999",)
    return f"{ts} >= ? AND {ts} <= ?", (start, end + ".999999")


def window_bounds(range_key: str, now: Optional[datetime] = None) -> Dict[str, Any]:
    if range_key not in RANGES:
        raise ValueError(f"range must be one of {', '.join(RANGES)}")
    delta, label = RANGES[range_key]
    now = (now or datetime.now()).replace(microsecond=0)
    start = None if delta is None else (now - delta)

    def aware(d: datetime) -> str:  # server-local naive -> ISO with explicit offset for display
        return d.astimezone().isoformat(timespec="seconds")

    return {
        "range": range_key, "label": label,
        "start": None if start is None else aware(start),
        "end": aware(now),
        # Naive server-local bounds, same clock/format family as the stored timestamps.
        "_start": None if start is None else start.strftime("%Y-%m-%d %H:%M:%S"),
        "_end": now.strftime("%Y-%m-%d %H:%M:%S"),
    }


OVERVIEW_DEFINITIONS = {
    "new_users": "Accounts created in the window (users.created_at).",
    "active_users": "Distinct accounts that performed at least one audited action in the window (sign-in, search, purchase, admin action; audit_events.actor_user_id). Not a live session count: the API uses stateless tokens and does not track sessions.",
    "searches_started": "Searches created in the window (jobs.created_at), by current status.",
    "leads_delivered": "Leads currently stored for searches started in the window.",
    "credits_charged_gross": "Search charges written to the ledger in the window, before refunds.",
    "credits_refunded": "Search refunds written to the ledger in the window.",
    "credits_charged_net": "Net search usage: search charges minus search refunds in the window (a refund can settle a search charged earlier).",
    "paid_credits": "Paid credits in the window: provenance-verified, completed, non-sandbox payments, each counted once.",
    "starting_credits": "Free signup credits granted in the window.",
    "admin_grants": "Staff grants in the window.",
    "sandbox_test_credits": "Credits from sandbox (test) payments in the window. No money was charged.",
    "snapshot": "Current values at request time; not affected by the range.",
}


def get_overview_metrics(range_key: str = "24h", now: Optional[datetime] = None) -> Dict[str, Any]:
    window = window_bounds(range_key, now)
    start, end = window.pop("_start"), window.pop("_end")
    metrics: Dict[str, Any] = {}
    snapshot: Dict[str, Any] = {}
    errors: List[str] = []

    with _snapshot() as cursor:
        def scalar(name: str, target: Dict[str, Any], sql: str, params: Tuple = ()) -> None:
            try:
                cursor.execute(sql, params)
                row = cursor.fetchone()
                target[name] = int((row[0] if row else 0) or 0)
            except Exception as exc:  # reported as unavailable, never as 0
                logger.warning("overview metric %s failed: %r", name, exc)
                target[name] = None
                errors.append(name)

        w_users, p_users = _window_clause("created_at", start, end)
        scalar("new_users", metrics, f"SELECT COUNT(*) FROM users WHERE {w_users}", p_users)
        scalar("active_users", metrics,
               f"SELECT COUNT(DISTINCT actor_user_id) FROM audit_events WHERE actor_user_id IS NOT NULL AND {w_users}",
               p_users)
        w_jobs, p_jobs = _window_clause("j.created_at", start, end)
        try:
            cursor.execute(f"SELECT j.status, COUNT(*) FROM jobs j WHERE {w_jobs} GROUP BY j.status", p_jobs)
            by_status = {str(r[0]): int(r[1]) for r in cursor.fetchall()}
            metrics["searches_started"] = sum(by_status.values())
            metrics["searches_by_status"] = by_status
        except Exception as exc:
            logger.warning("overview searches failed: %r", exc)
            metrics["searches_started"] = None
            metrics["searches_by_status"] = None
            errors.append("searches_started")
        scalar("leads_delivered", metrics,
               f"SELECT COUNT(*) FROM results r JOIN jobs j ON j.job_id = r.job_id WHERE {w_jobs}", p_jobs)

        w_led, p_led = _window_clause("l.created_at", start, end)
        scalar("credits_charged_gross", metrics,
               f"SELECT COALESCE(SUM(-l.amount), 0) FROM credit_ledger l WHERE l.transaction_type = 'debit' "
               f"AND l.job_id IS NOT NULL AND {w_led}", p_led)
        scalar("credits_refunded", metrics,
               f"SELECT COALESCE(SUM(l.amount), 0) FROM credit_ledger l WHERE l.transaction_type = 'refund' "
               f"AND l.job_id IS NOT NULL AND {w_led}", p_led)
        if metrics.get("credits_charged_gross") is not None and metrics.get("credits_refunded") is not None:
            metrics["credits_charged_net"] = metrics["credits_charged_gross"] - metrics["credits_refunded"]
        else:
            metrics["credits_charged_net"] = None

        # Credit inflows: classify every credit/bonus row of each affected account
        # against that account's FULL ledger (payment claims, signup grant), then
        # count only the rows inside the window. Matching inside the window alone
        # would let a duplicate in range claim a payment first credited earlier.
        try:
            cursor.execute(f"SELECT l.id, l.user_id FROM credit_ledger l "
                           f"WHERE l.transaction_type IN ('credit', 'bonus') AND {w_led}", p_led)
            in_window: Dict[int, int] = {int(r[0]): int(r[1]) for r in cursor.fetchall()}
            inflow = {"purchase": 0, "starting_credits": 0, "admin_grant": 0, "sandbox_test": 0}
            user_ids = sorted(set(in_window.values()))
            for i in range(0, len(user_ids), 500):
                chunk = user_ids[i:i + 500]
                ph = ", ".join("?" for _ in chunk)
                cursor.execute(
                    "SELECT id, user_id, job_id, amount, transaction_type, reason, created_by, created_at "
                    f"FROM credit_ledger WHERE transaction_type IN ('credit', 'bonus') AND user_id IN ({ph})",
                    tuple(chunk))
                by_user: Dict[int, List[Dict[str, Any]]] = {}
                for r in cursor.fetchall():
                    by_user.setdefault(int(r[1]), []).append(
                        {"id": int(r[0]), "user_id": int(r[1]), "job_id": r[2], "amount": int(r[3] or 0),
                         "transaction_type": r[4], "reason": r[5],
                         "created_by": None if r[6] is None else int(r[6]), "created_at": r[7]})
                cursor.execute(f"SELECT id, approved_by, approved_at FROM users WHERE id IN ({ph})", tuple(chunk))
                approval = {int(r[0]): (r[1], r[2]) for r in cursor.fetchall()}
                cursor.execute(
                    "SELECT id, user_id, payment_provider, provider_transaction_id, provider_environment, status, "
                    f"credits_purchased FROM payment_transactions WHERE user_id IN ({ph})", tuple(chunk))
                payments: Dict[int, List[Dict[str, Any]]] = {}
                for p in cursor.fetchall():
                    payments.setdefault(int(p[1]), []).append(
                        {"id": int(p[0]), "provider": p[2], "provider_transaction_id": p[3], "environment": p[4],
                         "status": p[5], "credits": int(p[6] or 0)})
                cursor.execute(
                    "SELECT credit_ledger_id, credits_granted FROM credit_expiry WHERE expiry_type = 'purchased' "
                    f"AND credit_ledger_id IS NOT NULL AND user_id IN ({ph})", tuple(chunk))
                links = {int(x[0]): int(x[1] or 0) for x in cursor.fetchall()}
                for uid, mine in by_user.items():
                    matched = _match_payments(mine, payments.get(uid, []), links)
                    signups = _verify_signups(mine, *approval.get(uid, (None, None)))
                    for r in mine:
                        if r["id"] not in in_window:
                            continue
                        cat = classify_entry(r, matched.get(r["id"]), signup=r["id"] in signups)
                        if cat in inflow:
                            inflow[cat] += r["amount"]
            metrics["paid_credits"] = inflow["purchase"]
            metrics["starting_credits"] = inflow["starting_credits"]
            metrics["admin_grants"] = inflow["admin_grant"]
            metrics["sandbox_test_credits"] = inflow["sandbox_test"]
        except Exception as exc:
            logger.warning("overview credit inflows failed: %r", exc)
            for k in ("paid_credits", "starting_credits", "admin_grants", "sandbox_test_credits"):
                metrics[k] = None
            errors.append("credit_inflows")

        scalar("total_users", snapshot, "SELECT COUNT(*) FROM users")
        scalar("pending_users", snapshot, "SELECT COUNT(*) FROM users WHERE is_approved = 0")
        scalar("credits_in_circulation", snapshot, "SELECT COALESCE(SUM(credit_balance), 0) FROM users")
        scalar("searches_in_progress", snapshot, "SELECT COUNT(*) FROM jobs WHERE status IN ('pending', 'running')")
        scalar("pending_credit_requests", snapshot, "SELECT COUNT(*) FROM credit_requests WHERE status = 'pending'")

    return {"window": window, "metrics": metrics, "snapshot": snapshot,
            "unavailable": errors, "definitions": OVERVIEW_DEFINITIONS}


# --------------------------------------------------------------------------- #
# Health
# --------------------------------------------------------------------------- #

_MIGRATIONS_DIR = Path(__file__).resolve().parent / "migrations"


def _expected_migration_versions() -> Optional[List[str]]:
    try:
        versions = sorted({p.name[:3] for p in _MIGRATIONS_DIR.glob("[0-9][0-9][0-9]_*.sql")})
        return versions or None
    except Exception:
        return None


def _check_database() -> Dict[str, Any]:
    t0 = time.perf_counter()
    try:
        conn = get_db()
        try:
            cur = conn.cursor()
            cur.execute("SELECT 1")
            cur.fetchone()
            latency = round((time.perf_counter() - t0) * 1000, 1)
            try:
                cur.execute("SELECT version FROM schema_migrations")
                applied: Optional[List[str]] = sorted({str(r[0]) for r in cur.fetchall() if r[0] is not None})
            except Exception:
                applied = None
        finally:
            conn.close()
    except Exception as exc:
        return {"status": "down", "detail": f"query failed ({type(exc).__name__})"}
    return {"status": "ok", "latency_ms": latency, "applied_versions": applied}


def _check_migrations(applied: Optional[List[str]], expected: Optional[List[str]] = None) -> Dict[str, Any]:
    expected = _expected_migration_versions() if expected is None else expected
    if applied is None or not expected:
        return {"status": "unknown", "detail": "could not read applied or expected migrations"}
    missing = sorted(set(expected) - set(applied))
    latest = applied[-1] if applied else None
    if missing:
        return {"status": "missing", "applied": latest, "expected": expected[-1], "missing": missing,
                "detail": f"not applied: {', '.join(missing)}"}
    return {"status": "ok", "applied": latest, "expected": expected[-1]}


def _check_job_runner(runner: Any, mode: str) -> Dict[str, Any]:
    if mode != "inprocess":
        return {"status": "unknown", "mode": mode,
                "detail": "Searches run in a separate worker process; this API process cannot observe it."}
    if runner is None:
        return {"status": "down", "mode": mode, "detail": "In-process job runner is not running."}
    last_ok = getattr(runner, "last_ok_pass_at", None)
    last_ok_flag = getattr(runner, "last_pass_ok", None)
    limit = max(60.0, 5 * float(getattr(runner, "poll_seconds", 3) or 3))
    out: Dict[str, Any] = {"mode": mode, "stale_after_seconds": limit,
                           "active_searches": len(getattr(runner, "active_job_ids", []) or [])}
    if last_ok_flag is False:
        out.update(status="failing",
                   detail=f"last scheduling pass failed: {getattr(runner, 'last_pass_error', None) or 'error'}")
        return out
    if last_ok is None:
        out.update(status="unknown", detail="Job runner has not completed a scheduling pass yet.")
        return out
    age = round(time.time() - float(last_ok), 1)
    out.update(status="ok" if age <= limit else "stale", last_pass_seconds_ago=age)
    return out


def _check_tunnel() -> Dict[str, Any]:
    url = os.getenv("TUNNEL_METRICS_URL", "").strip()
    if not url:
        return {"status": "unknown",
                "detail": "Not monitored from the backend (TUNNEL_METRICS_URL is not set). "
                          "External reachability is measured by the browser instead."}
    try:
        with urllib.request.urlopen(url.rstrip("/") + "/ready", timeout=3) as resp:  # noqa: S310 (operator-set URL)
            return {"status": "ok" if resp.status == 200 else "down", "http_status": resp.status}
    except Exception as exc:
        return {"status": "down", "detail": f"connector readiness check failed ({type(exc).__name__})"}


def get_internal_health(runner: Any = None, mode: Optional[str] = None) -> Dict[str, Any]:
    """Internal dependency health of THIS backend process.

    OK only when the database answers, every migration file is applied and the
    in-process runner's last scheduling pass succeeded recently. Anything
    failing makes it degraded/down; anything unobservable makes it unknown.
    """
    if mode is None:
        try:
            from job_runner import runner_mode
            mode = runner_mode()
        except Exception:
            mode = "unknown"
    db = _check_database()
    checks = {
        "database": {k: v for k, v in db.items() if k != "applied_versions"},
        "migrations": _check_migrations(db.get("applied_versions")) if db["status"] == "ok"
        else {"status": "unknown", "detail": "database unavailable"},
        "job_runner": _check_job_runner(runner, mode),
        "tunnel_connector": _check_tunnel(),
    }
    core = [checks["database"]["status"], checks["migrations"]["status"], checks["job_runner"]["status"]]
    if checks["database"]["status"] == "down":
        overall = "down"
    elif any(s in ("down", "stale", "failing", "missing") for s in core):
        overall = "degraded"
    elif all(s == "ok" for s in core):
        overall = "ok"
    else:
        overall = "unknown"
    return {"status": overall, "checked_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            "checks": checks,
            "scope": "Internal: database, schema migrations and job runner as seen by this API process. "
                     "The tunnel connector is informational and does not change the overall status."}
