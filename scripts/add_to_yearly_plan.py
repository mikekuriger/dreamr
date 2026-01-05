#!/usr/bin/env python3
import argparse, sys, json
from datetime import datetime, timezone
import pymysql

PRO_PLAN_ID = "pro_yearly"

SQL_FIND_USERS_BY_EMAIL = """
SELECT id, email FROM users WHERE email IN ({})
"""

SQL_LOAD_USER_SUBS = """
SELECT id, plan_id, status FROM user_subscriptions WHERE user_id=%s
"""

SQL_CANCEL_SUB = """
UPDATE user_subscriptions
SET status='canceled', updated_at=NOW(), end_date=IFNULL(end_date, NOW())
WHERE id=%s AND status <> 'canceled'
"""

SQL_INSERT_SUB = """
INSERT INTO user_subscriptions
(user_id, plan_id, status, start_date, end_date, auto_renew,
 payment_method, payment_provider, provider_subscription_id, provider_transaction_id, receipt_data)
VALUES
(%s, %s, 'active', %s, NULL, 0, NULL, NULL, NULL, NULL, NULL)
"""

def parse_args():
    p = argparse.ArgumentParser(description="Grant pro_yearly to test users (never expire).")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=3306)
    p.add_argument("--user", default="dreamr_user")
    p.add_argument("--password", default="M!ke&7@r425!")
    p.add_argument("--database", default="dreamr")

    group = p.add_mutually_exclusive_group(required=True)
    group.add_argument("--emails", nargs="+", help="List of user emails")
    group.add_argument("--email-file", help="File with one email per line")
    group.add_argument("--user-ids", nargs="+", type=int, help="List of user IDs")

    p.add_argument("--dry-run", action="store_true", help="Show actions; do not commit")
    p.add_argument("--verbose", "-v", action="store_true")
    # Optional: set far-future end date instead of NULL if your app needs it.
    p.add_argument("--end-date-2099", action="store_true", help="Set end_date to 2099-12-31 instead of NULL")
    return p.parse_args()

def load_emails_from_file(path):
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]

def main():
    args = parse_args()

    # Resolve user IDs
    user_ids = []
    conn = pymysql.connect(
        host=args.host, port=args.port, user=args.user, password=args.password,
        db=args.database, charset="utf8mb4", autocommit=False, cursorclass=pymysql.cursors.DictCursor
    )

    try:
        with conn.cursor() as cur:
            if args.user_ids:
                user_ids = list(dict.fromkeys(args.user_ids))
            else:
                emails = args.emails or load_emails_from_file(args.email_file)
                if not emails:
                    print("No emails provided.", file=sys.stderr); sys.exit(1)
                placeholders = ",".join(["%s"] * len(emails))
                cur.execute(SQL_FIND_USERS_BY_EMAIL.format(placeholders), emails)
                rows = cur.fetchall()
                found = {r["email"]: r["id"] for r in rows}
                missing = [e for e in emails if e not in found]
                if missing:
                    print(f"WARNING: {len(missing)} emails not found: {missing}", file=sys.stderr)
                user_ids = list(found.values())

            if not user_ids:
                print("No users to update.", file=sys.stderr); return 0

            if args.verbose:
                print(f"Processing user_ids={user_ids}")

            now = datetime.now(timezone.utc).replace(tzinfo=timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

            # Optionally prepare a different insert if forcing 2099 end date
            insert_sql = SQL_INSERT_SUB
            if args.end_date_2099:
                insert_sql = """
                INSERT INTO user_subscriptions
                (user_id, plan_id, status, start_date, end_date, auto_renew,
                 payment_method, payment_provider, provider_subscription_id, provider_transaction_id, receipt_data)
                VALUES
                (%s, %s, 'active', %s, '2099-12-31 23:59:59', 0, NULL, NULL, NULL, NULL, NULL)
                """

            for uid in user_ids:
                # Load existing subs
                cur.execute(SQL_LOAD_USER_SUBS, (uid,))
                subs = cur.fetchall()

                # If already has active pro_yearly, skip
                already_good = any(s["plan_id"] == PRO_PLAN_ID and s["status"] == "active" for s in subs)
                if already_good:
                    if args.verbose:
                        print(f"[SKIP] user_id={uid} already active on {PRO_PLAN_ID}")
                    continue

                # Cancel other active subs for the user
                for s in subs:
                    if s["status"] != "canceled":
                        if args.verbose:
                            print(f"[CANCEL] sub_id={s['id']} user_id={uid} plan={s['plan_id']}")
                        if not args.dry_run:
                            cur.execute(SQL_CANCEL_SUB, (s["id"],))

                # Insert our permanent pro_yearly
                if args.verbose:
                    print(f"[GRANT] user_id={uid} -> {PRO_PLAN_ID} start={now} end=NULL")
                if not args.dry_run:
                    cur.execute(insert_sql, (uid, PRO_PLAN_ID, now))

            if args.dry_run:
                print("Dry-run complete. No changes committed.")
                conn.rollback()
            else:
                conn.commit()
                if args.verbose:
                    print("Committed.")
        return 0
    except Exception as e:
        conn.rollback()
        print(f"ERROR: {e}", file=sys.stderr)
        return 2
    finally:
        conn.close()

if __name__ == "__main__":
    sys.exit(main())

