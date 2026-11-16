"""Interactively reset the password of an existing administrator.

Run from any directory: python backend/scripts/reset_admin_password.py --email you@example.com
The backend .env (or process environment) selects the database.
"""

import argparse
import getpass
import os
import sys
from pathlib import Path
from urllib.parse import urlparse

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

import config  # noqa: E402  Loads backend/.env before database/auth imports.
from auth import get_password_hash  # noqa: E402
from database import _get_db_type, get_db  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--email", required=True, help="Email of an existing admin")
    parser.add_argument("--password-env", help="Environment variable containing the new password")
    args = parser.parse_args()

    db_type = _get_db_type()
    parsed = urlparse(config.DATABASE_URL)
    location = parsed.hostname if db_type == "mysql" else parsed.path
    print(f"Database: {db_type} ({location})")
    print(f"Admin email: {args.email}")
    if input("Type RESET to continue: ").strip() != "RESET":
        print("Cancelled.")
        return 1

    if args.password_env:
        password = os.getenv(args.password_env, "")
        confirmation = password
    else:
        password = getpass.getpass("New password: ")
        confirmation = getpass.getpass("Confirm new password: ")
    if password != confirmation or len(password) < 12:
        print("Passwords must match and contain at least 12 characters.")
        return 1

    conn = get_db()
    try:
        cursor = conn.cursor()
        placeholder = "%s" if db_type == "mysql" else "?"
        cursor.execute(
            f"SELECT id, is_admin, role FROM users WHERE email = {placeholder}",
            (args.email,),
        )
        row = cursor.fetchone()
        if not row or (not bool(row[1]) and row[2] not in ("admin", "owner")):
            print("No existing administrator found with that email.")
            return 1

        cursor.execute(
            f"UPDATE users SET password_hash = {placeholder} WHERE id = {placeholder}",
            (get_password_hash(password), row[0]),
        )
        cursor.execute(
            f"UPDATE password_reset_tokens SET used = 1 WHERE user_id = {placeholder} AND used = 0",
            (row[0],),
        )
        conn.commit()
        print("Admin password reset. Existing access tokens remain valid until expiry.")
        return 0
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
