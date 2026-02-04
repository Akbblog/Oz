from __future__ import annotations

import secrets
import string
from datetime import datetime, timedelta
from typing import Any, Dict, Optional

import config
from db.base import execute_query
from utils.time_utils import now_db_string


ALPHABET = string.ascii_uppercase + string.digits


def _generate_code(length: int) -> str:
    return "".join(secrets.choice(ALPHABET) for _ in range(length))


class ReferralService:
    def ensure_user_referral_code(self, user_id: int) -> str:
        row = execute_query(
            "SELECT referral_code FROM users WHERE id = ?",
            (user_id,),
            fetch_one=True,
            commit=False,
        )
        existing = (row[0] if row else None) or ""
        if existing:
            return str(existing)

        length = int(config.REFERRAL_CONFIG.get("referral_code_length", 8))
        for _ in range(20):
            code = _generate_code(length)
            try:
                execute_query(
                    "UPDATE users SET referral_code = ? WHERE id = ?",
                    (code, user_id),
                )
                return code
            except Exception:
                # Likely uniqueness violation on users(referral_code)
                continue
        raise RuntimeError("Failed to generate a unique referral code")

    def record_referral_signup(self, *, referred_user_id: int, referral_code: str) -> bool:
        if not referral_code:
            return False

        ref_row = execute_query(
            "SELECT id FROM users WHERE referral_code = ?",
            (referral_code.strip().upper(),),
            fetch_one=True,
            commit=False,
        )
        if not ref_row:
            return False
        referrer_user_id = int(ref_row[0])
        if referrer_user_id == referred_user_id:
            return False

        now = now_db_string()
        try:
            execute_query(
                """
                INSERT INTO referrals (
                    referrer_user_id, referred_user_id, referral_code, status,
                    referrer_credits_awarded, referred_credits_awarded,
                    completed_at, rewarded_at, created_at, updated_at
                ) VALUES (?, ?, ?, 'pending', 0, 0, NULL, NULL, ?, ?)
                """,
                (referrer_user_id, referred_user_id, referral_code.strip().upper(), now, now),
            )
            return True
        except Exception:
            # Duplicate unique_referral or other constraint.
            return False

    def get_referrer_stats(self, user_id: int) -> Dict[str, Any]:
        code = self.ensure_user_referral_code(user_id)

        total_row = execute_query(
            "SELECT COUNT(*) FROM referrals WHERE referrer_user_id = ?",
            (user_id,),
            fetch_one=True,
            commit=False,
        )
        completed_row = execute_query(
            "SELECT COUNT(*) FROM referrals WHERE referrer_user_id = ? AND status IN ('completed', 'rewarded')",
            (user_id,),
            fetch_one=True,
            commit=False,
        )
        rewarded_row = execute_query(
            "SELECT COALESCE(SUM(referrer_credits_awarded), 0) FROM referrals WHERE referrer_user_id = ?",
            (user_id,),
            fetch_one=True,
            commit=False,
        )

        total = int(total_row[0] or 0) if total_row else 0
        completed = int(completed_row[0] or 0) if completed_row else 0
        earned = int(rewarded_row[0] or 0) if rewarded_row else 0
        pending = max(0, total - completed)

        return {
            "referral_code": code,
            "total_referrals": total,
            "completed_referrals": completed,
            "pending_referrals": pending,
            "total_credits_earned": earned,
        }

    def _grant_referral_credits(self, *, user_id: int, credits: int, reason: str) -> None:
        if credits <= 0:
            return
        created_at = now_db_string()
        execute_query(
            "UPDATE users SET credit_balance = COALESCE(credit_balance, 0) + ? WHERE id = ?",
            (credits, user_id),
        )
        bal_row = execute_query(
            "SELECT credit_balance FROM users WHERE id = ?",
            (user_id,),
            fetch_one=True,
            commit=False,
        )
        balance_after = int(bal_row[0] or 0) if bal_row else 0

        ledger_id = execute_query(
            """
            INSERT INTO credit_ledger (user_id, job_id, amount, balance_after, transaction_type, reason, created_at, created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (user_id, None, credits, balance_after, "bonus", reason, created_at, None),
        )

        expiry_days = int(config.DEFAULT_CREDIT_CONFIG.get("bonus_expiry_days", 0) or 0)
        expires_at = None
        if expiry_days > 0:
            expires_at = (datetime.utcnow() + timedelta(days=expiry_days)).replace(microsecond=0).isoformat()

        execute_query(
            """
            INSERT INTO credit_expiry (
                user_id, credit_ledger_id, credits_granted, credits_remaining, expiry_type, expires_at, created_at, updated_at
            ) VALUES (?, ?, ?, ?, 'referral', ?, ?, ?)
            """,
            (user_id, int(ledger_id), credits, credits, expires_at, created_at, created_at),
        )

    def maybe_reward_on_purchase(self, *, referred_user_id: int, paid_amount_cents: int) -> None:
        """
        If the user signed up with a referral and this is their first qualifying purchase,
        award credits to both referrer and referred user.
        """
        min_purchase = int(config.REFERRAL_CONFIG.get("min_purchase_for_reward", 0) or 0)
        if paid_amount_cents < min_purchase:
            return

        row = execute_query(
            """
            SELECT id, referrer_user_id, status
            FROM referrals
            WHERE referred_user_id = ? AND status = 'pending'
            ORDER BY created_at ASC
            LIMIT 1
            """,
            (referred_user_id,),
            fetch_one=True,
            commit=False,
        )
        if not row:
            return

        referral_id = int(row[0])
        referrer_user_id = int(row[1])

        referrer_bonus = int(config.REFERRAL_CONFIG.get("referrer_bonus_credits", 0) or 0)
        referred_bonus = int(config.REFERRAL_CONFIG.get("referred_bonus_credits", 0) or 0)
        now = now_db_string()

        execute_query(
            """
            UPDATE referrals
            SET status = 'rewarded',
                referrer_credits_awarded = ?,
                referred_credits_awarded = ?,
                completed_at = ?,
                rewarded_at = ?,
                updated_at = ?
            WHERE id = ? AND status = 'pending'
            """,
            (referrer_bonus, referred_bonus, now, now, now, referral_id),
        )

        self._grant_referral_credits(
            user_id=referrer_user_id,
            credits=referrer_bonus,
            reason="Referral reward (referrer)",
        )
        self._grant_referral_credits(
            user_id=referred_user_id,
            credits=referred_bonus,
            reason="Referral reward (referred)",
        )

