"""Reconcile Google Play subscriptions with Dreamr DB.

Usage (from back_end/dreamr):
  python reconcile_google_subs.py --dry-run
  python reconcile_google_subs.py --apply --limit 100

This script does NOT run automatically; you call it when you want to
re-sync Google billing truth into user_subscriptions.
"""

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

        total = 0
        updated = 0

        for sub in q:
            total += 1
            token = sub.provider_transaction_id
            plan = sub.plan
            if plan is None:
                LOG.warning("user_subscriptions id=%s has no plan; skipping", sub.id)
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
                continue

            new_fields = map_google_to_local(resp)

            changed = (
                sub.status != new_fields["status"]
                or sub.end_date != new_fields["end_date"]
                or sub.auto_renew != new_fields["auto_renew"]
            )

            LOG.info(
                "Result user=%s sub=%s: status %s -> %s, end %s -> %s, auto_renew %s -> %s",
                sub.user_id,
                sub.id,
                sub.status,
                new_fields["status"],
                sub.end_date,
                new_fields["end_date"],
                sub.auto_renew,
                new_fields["auto_renew"],
            )

            if not dry_run and changed:
                sub.status = new_fields["status"]
                sub.end_date = new_fields["end_date"]
                sub.auto_renew = new_fields["auto_renew"]
                updated += 1

        if not dry_run:
            db.session.commit()

        LOG.info("Processed %s Google subs, updated %s", total, updated)


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
