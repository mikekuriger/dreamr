#!/opt/dreamr-venv/bin/python

"""Reconcile Google Play subscriptions with Dreamr DB.

Usage (from back_end/dreamr):
  python reconcile_google_subs.py --dry-run
  python reconcile_google_subs.py --apply --limit 100

This script does NOT run automatically; you call it when you want to
re-sync Google billing truth into user_subscriptions.
"""
import sys
from pathlib import Path

# Always import Dreamr app from the repo root, regardless of CWD
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent   # if script will live in dreamr/scripts/
sys.path.insert(0, str(REPO_ROOT))

import argparse
import datetime as dt
import logging
import os

from google.oauth2 import service_account
from googleapiclient.discovery import build

from app import app, db, UserSubscription, SubscriptionPlan


LOG = logging.getLogger("reconcile_google_subs")
SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]


def build_play_client():
    keyfile = os.environ["GOOGLE_PLAY_SERVICE_ACCOUNT_FILE"]
    creds = service_account.Credentials.from_service_account_file(
        keyfile,
        scopes=SCOPES,
    )
    return build("androidpublisher", "v3", credentials=creds, cache_discovery=False)


def map_google_to_local(sub_resp):
    """Map Google Play subscription resource to Dreamr fields.

    Returns dict: {"status": str, "end_date": datetime | None, "auto_renew": bool}.
    """
    expiry_ms = int(sub_resp.get("expiryTimeMillis", "0") or "0")
    end_date = dt.datetime.utcfromtimestamp(expiry_ms / 1000.0) if expiry_ms else None

    # auto_renew: whether renewal is currently on
    state = sub_resp.get("subscriptionState")
    if state is not None:
        # Newer API states
        # 1: ACTIVE, 3: IN_GRACE_PERIOD, 2/4/5: CANCELED / ON_HOLD / PAUSED, 6: EXPIRED
        state = int(state)
        auto_renew = state in (1, 3)
    else:
        # Legacy: rely on autoRenewing + cancelReason
        cancel_reason = int(sub_resp.get("cancelReason", 0) or 0)
        auto_renew = bool(sub_resp.get("autoRenewing")) and cancel_reason == 0

    now = dt.datetime.utcnow()

    # Entitlement status: active until end_date, then expired
    if end_date and now < end_date:
        status = "active"
    else:
        status = "expired"

    return {
        "status": status,
        "end_date": end_date,
        "auto_renew": auto_renew,
    }


def reconcile_google_subscriptions(dry_run=True, limit=None):
    with app.app_context():
        client = build_play_client()
        package_name = os.environ["GOOGLE_PLAY_PACKAGE_NAME"]

        q = UserSubscription.query.filter_by(payment_provider="google")
        q = q.filter(UserSubscription.provider_transaction_id.isnot(None))
        if limit is not None:
            q = q.limit(limit)

        db_count = q.count()
        LOG.info(
            "Found %s Google user_subscriptions with provider_transaction_id",
            db_count,
        )
        print(
            f"[reconcile_google_subs] Found {db_count} Google subs to check "
            f"(dry_run={dry_run})"
        )
        if db_count == 0:
            return

        total = 0
        updated = 0

        for sub in q:
            total += 1
            # Prefer the real Play purchase token from receipt_data; fall
            # back to provider_transaction_id only if needed.
            token = sub.receipt_data or sub.provider_transaction_id
            plan = sub.plan
            if plan is None:
                LOG.warning("user_subscriptions id=%s has no plan; skipping", sub.id)
                print(f"[reconcile_google_subs] SKIP user={sub.user_id} sub={sub.id}: no plan")
                continue

            subscription_id = plan.product_id or plan.id

            LOG.info(
                "Reconciling user=%s sub=%s plan=%s product_id=%s token=%s",
                sub.user_id,
                sub.id,
                sub.plan_id,
                subscription_id,
                token,
            )
            print(
                f"[reconcile_google_subs] Checking user={sub.user_id} sub={sub.id} "
                f"plan={sub.plan_id} product_id={subscription_id}"
            )

            try:
                resp = (
                    client.purchases()
                    .subscriptions()
                    .get(
                        packageName=package_name,
                        subscriptionId=subscription_id,
                        token=token,
                    )
                    .execute()
                )
            except Exception as e:  # noqa: BLE001
                LOG.error("Google API error user=%s sub=%s: %s", sub.user_id, sub.id, e)
                print(
                    f"[reconcile_google_subs] Google API ERROR user={sub.user_id} "
                    f"sub={sub.id}: {e}"
                )
                continue

            new_fields = map_google_to_local(resp)

            changed = (
                sub.status != new_fields["status"]
                or sub.end_date != new_fields["end_date"]
                or sub.auto_renew != new_fields["auto_renew"]
            )

            print(
                "[reconcile_google_subs] DB vs Google for "
                f"user={sub.user_id} sub={sub.id}: "
                f"status {sub.status} -> {new_fields['status']}, "
                f"end {sub.end_date} -> {new_fields['end_date']}, "
                f"auto_renew {sub.auto_renew} -> {new_fields['auto_renew']} "
                f"(changed={changed}, dry_run={dry_run})"
            )

            if not dry_run and changed:
                sub.status = new_fields["status"]
                sub.end_date = new_fields["end_date"]
                sub.auto_renew = new_fields["auto_renew"]
                updated += 1
                print(
                    f"[reconcile_google_subs] UPDATED user={sub.user_id} sub={sub.id} "
                    f"to status={sub.status}, end={sub.end_date}, auto_renew={sub.auto_renew}"
                )

        if not dry_run:
            db.session.commit()

        LOG.info("Processed %s Google subs, updated %s", total, updated)
        print(
            f"[reconcile_google_subs] Processed {total} Google subs, "
            f"updated {updated} (dry_run={dry_run})"
        )


def main():
    logging.basicConfig(level=logging.INFO)

    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="Log only, no DB writes")
    parser.add_argument("--apply", action="store_true", help="Apply DB changes")
    parser.add_argument("--limit", type=int, default=None, help="Limit number of subs")
    args = parser.parse_args()

    if args.dry_run and args.apply:
        raise SystemExit("Use either --dry-run or --apply, not both.")

    dry_run = not args.apply
    reconcile_google_subscriptions(dry_run=dry_run, limit=args.limit)


if __name__ == "__main__":
    main()
