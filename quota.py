# quota.py
from __future__ import annotations  # postpone annotation evaluation
from typing import TYPE_CHECKING

from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo
from sqlalchemy import select, update, and_, text as sqltext
from sqlalchemy.exc import IntegrityError, OperationalError

PT = ZoneInfo("America/Los_Angeles")
WEEKLY_FREE_QUOTA = 2       # free credits bumped to this each Sunday
IMAGE_CREDIT_COST = 4       # credits deducted per image generation

if TYPE_CHECKING:
    # For editors only; never runs at runtime
    from app import UserCredits

def _pt_week_anchor(dt_utc: datetime) -> datetime:
    now_pt = dt_utc.astimezone(PT)
    # floor to Sunday 00:00 PT
    days_to_sunday = (now_pt.weekday() + 1) % 7  # Mon=0..Sun=6 => days back to Sunday
    sunday = (now_pt - timedelta(days=days_to_sunday)).replace(hour=0, minute=0, second=0, microsecond=0)
    return sunday.astimezone(timezone.utc).replace(tzinfo=None)  # naive UTC for DB

def _next_reset_iso(anchor_utc: datetime) -> str:
    return (anchor_utc + timedelta(days=7)).replace(tzinfo=timezone.utc).isoformat().replace("+00:00", "Z")

def _models():
    # late import avoids circular import at module import time
    from app import db, UserCredits
    return db, UserCredits

def _total_credits(uc) -> int:
    return (uc.free_credits or 0) + (uc.purchased_credits or 0)

def get_or_create_credits(user_id: int, max_retries: int = 3) -> "UserCredits":
    db, UserCredits = _models()

    for attempt in range(max_retries):
        try:
            # Fast path: already exists
            uc = UserCredits.query.get(user_id)
            if uc:
                return uc

            # Create new credits row
            anchor = _pt_week_anchor(datetime.utcnow())
            uc = UserCredits(
                user_id=user_id,
                free_credits=WEEKLY_FREE_QUOTA,
                purchased_credits=0,
                week_anchor_utc=anchor,
            )
            db.session.add(uc)
            db.session.commit()
            return uc

        except IntegrityError:
            # Most likely: another transaction inserted the row first
            db.session.rollback()
            uc = UserCredits.query.get(user_id)
            if uc:
                return uc
            raise

        except OperationalError as e:
            db.session.rollback()
            # MariaDB/MySQL deadlock = 1213
            orig = getattr(e, "orig", None)
            code = orig.args[0] if (orig and getattr(orig, "args", None)) else None
            if code == 1213 and attempt < max_retries - 1:
                continue
            raise


def ensure_week_current(user_id: int) -> "UserCredits":
    db, UserCredits = _models()
    now = datetime.utcnow()
    cur_anchor = _pt_week_anchor(now)
    # lock row
    uc = db.session.execute(
        select(UserCredits).where(UserCredits.user_id == user_id).with_for_update()
    ).scalars().first()
    if not uc:
        uc = get_or_create_credits(user_id)
        # lock it after creation
        uc = db.session.execute(
            select(UserCredits).where(UserCredits.user_id == user_id).with_for_update()
        ).scalars().first()

    if cur_anchor > (uc.week_anchor_utc or cur_anchor):
        uc.week_anchor_utc = cur_anchor
        # Bump free credits to weekly quota only if below it — never touch purchased_credits
        if uc.free_credits < WEEKLY_FREE_QUOTA:
            uc.free_credits = WEEKLY_FREE_QUOTA
        db.session.commit()
    return uc


def decrement_text_or_deny(user_id: int) -> tuple[bool, str | None]:
    """Deduct 1 credit for a dream analysis. Free credits consumed first."""
    db, UserCredits = _models()
    uc = ensure_week_current(user_id)
    if _total_credits(uc) <= 0:
        return False, _next_reset_iso(uc.week_anchor_utc)
    if uc.free_credits > 0:
        uc.free_credits -= 1
    else:
        uc.purchased_credits -= 1
    db.session.commit()
    return True, None


def refund_text(user_id: int) -> None:
    """Refund 1 credit on analysis failure. Refunds to free_credits."""
    db, UserCredits = _models()
    uc = UserCredits.query.get(user_id)
    if uc:
        uc.free_credits += 1
        db.session.commit()


def decrement_image_or_deny(user_id: int) -> bool:
    """Deduct IMAGE_CREDIT_COST credits for image generation. Free credits consumed first."""
    db, UserCredits = _models()
    uc = get_or_create_credits(user_id)
    if _total_credits(uc) < IMAGE_CREDIT_COST:
        return False
    remaining = IMAGE_CREDIT_COST
    free_use = min(uc.free_credits, remaining)
    uc.free_credits -= free_use
    remaining -= free_use
    if remaining > 0:
        uc.purchased_credits -= remaining
    db.session.commit()
    return True


def refund_image(user_id: int) -> None:
    """Refund IMAGE_CREDIT_COST credits on image generation failure."""
    db, UserCredits = _models()
    uc = UserCredits.query.get(user_id)
    if uc:
        uc.purchased_credits += IMAGE_CREDIT_COST
        db.session.commit()


def next_reset_iso(user_id: int) -> str:
    db, UserCredits = _models()
    uc = get_or_create_credits(user_id)
    return _next_reset_iso(uc.week_anchor_utc)
