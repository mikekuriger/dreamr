### File: app.py
from authlib.integrations.flask_client import OAuth # for google auth
from datetime import datetime, date, timezone, timedelta
from dateutil.relativedelta import relativedelta
from enum import Enum
from flask_cors import CORS
from flask import abort, Blueprint, current_app, Flask, jsonify, redirect, render_template, render_template_string, request, session, url_for
from flask_login import LoginManager, login_user, login_required, logout_user, current_user, UserMixin
from flask_mail import Message, Mail
from flask_migrate import Migrate
from flask_sqlalchemy import SQLAlchemy
from google.oauth2 import id_token
from google.auth.transport import requests as google_requests
from jwt import InvalidTokenError
import jwt
from langdetect import detect
from openai import OpenAI
from PIL import Image
from PIL import ImageFilter
from prompts import CATEGORY_PROMPTS, TONE_TO_STYLE
from quota import ensure_week_current, next_reset_iso, get_or_create_credits
from quota import decrement_text_or_deny, refund_text
from quota import decrement_image_or_deny, refund_image
from sqlalchemy import desc
from sqlalchemy import func
from sqlalchemy import or_
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.dialects.mysql import JSON as MySQLJSON
from werkzeug.utils import secure_filename
from zoneinfo import ZoneInfo
import base64
import bcrypt
import hashlib, secrets
import io
import json
import logging
import openai
import os
import re
import requests
import jwt
from jwt import PyJWKClient, InvalidTokenError
import shutil
import string
import time
import traceback
import uuid


logger = logging.getLogger()
logger.setLevel(logging.INFO)

if os.getenv("LOG_TO_STDOUT", "1") == "1":
    handler = logging.StreamHandler()
else:
    log_dir = os.getenv("LOG_DIR", "/home/mk7193/dreamr")
    os.makedirs(log_dir, exist_ok=True)
    handler = logging.FileHandler(os.path.join(log_dir, "dreamr.log"))

handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s"))
logger.addHandler(handler)


client = OpenAI()
openai.api_key = os.environ.get("OPENAI_API_KEY")

app = Flask(__name__)
# app.config.from_pyfile('config.py')
cfg_path = os.getenv("FLASK_CONFIG_FILE", "config.py")
if os.path.exists(cfg_path):
    app.config.from_pyfile(cfg_path)

# env overrides (Flask 3)
app.config.from_prefixed_env(prefix="DREAMR")

CORS(app, supports_credentials=True,origins=["https://dreamr.zentha.me", "https://dreamr-us-west-01.zentha.me", "http://localhost:5173"])

db = SQLAlchemy(app)
login_manager = LoginManager(app)
login_manager.init_app(app)
migrate = Migrate(app, db)
mail = Mail(app)

WEB_CLIENT_ID = "846080686597-61d3v0687vomt4g4tl7rueu7rv9qrari.apps.googleusercontent.com"
IOS_CLIENT_ID = "846080686597-8u85pj943ilkmlt583f3tct5h9ca0c3t.apps.googleusercontent.com"
ALLOWED_AUDS = {WEB_CLIENT_ID, IOS_CLIENT_ID}
ALLOWED_ISS = {"https://accounts.google.com", "accounts.google.com"}

APPLE_ISSUER = "https://appleid.apple.com"
APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"
# For native Sign in with Apple, this should match the client_id used on iOS (bundle id or service id).
APPLE_BUNDLE_ID = "me.zentha.dreamr"
APPLE_CLIENT_ID = os.getenv("APPLE_CLIENT_ID") or APPLE_BUNDLE_ID

_apple_jwk_client = PyJWKClient(APPLE_JWKS_URL)

# apple store
# @app.post("/appstore/notifications")
# def appstore_notifications():
#     data = request.get_json(force=True, silent=True)
#     # For v2, payload is usually in data["signedPayload"] (string JWS)
#     # TODO: verify JWS using Apple JWKS, then decode claims
#     # TODO: handle notificationType/subtype and update your DB
#     return jsonify({"status": "ok"}), 200

# @app.post("/appstore/notifications-sandbox")
# def appstore_notifications_sbx():
#     return jsonify({"status": "ok"}), 200


# --- Admin config ---
# ADMIN_EMAILS = {e.strip().lower() for e in os.getenv("ADMIN_EMAILS", "").split(",") if e.strip()}
app.config.setdefault("ADMIN_EMAILS", os.getenv("ADMIN_EMAILS", ""))


# Password reset with token (when user clicks the email)
# ---------------------------------------------------------------------------
# Minimal web reset page (temporary until mobile deep-link is live)
# ---------------------------------------------------------------------------
RESET_PAGE_TEMPLATE = """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Reset your Dreamr password</title>
  <meta name="robots" content="noindex,nofollow">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body { background:#0b0420; color:#fff; font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu; display:flex; min-height:100vh; align-items:center; justify-content:center; margin:0; }
    .card { width: min(480px, 92vw); background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.12); border-radius: 14px; padding: 22px; box-shadow: 0 6px 24px rgba(0,0,0,0.35); }
    h1 { font-size: 20px; margin: 0 0 8px; }
    p { color:#D1B2FF; margin: 0 0 16px; }
    input[type=password] { width:100%; padding:12px; border-radius:10px; border:1px solid rgba(255,255,255,0.25); background:rgba(0,0,0,0.3); color:#fff; margin-bottom:12px; }
    button { width:100%; padding:12px; border-radius:10px; border:0; background:#fff; color:#000; font-weight:600; cursor:pointer; }
    .msg{ margin-top:12px; padding:10px; border-radius:10px; }
    .err{ background:rgba(255,0,0,0.16); border:1px solid rgba(255,0,0,0.35);}
    .ok{ background:rgba(0,200,0,0.16); border:1px solid rgba(0,200,0,0.35);}
    .hint{ font-size:12px; color:#bfb8d8; margin-top:8px; text-align:center;}
  </style>
</head>
<body>
  <div class="card">
    {% if invalid %}
      <h1>Link expired or invalid</h1>
      <p>Please request a new reset link from the Dreamr app.</p>
      <div class="hint">You can close this window.</div>
    {% elif done %}
      <h1>Password updated</h1>
      <p>You can now open the Dreamr app and sign in with your new password.</p>
      <div class="hint">You can close this window.</div>
    {% else %}
      <h1>Set a new password</h1>
      <p>Enter a new password for your account.</p>
      {% if error %}<div class="msg err">{{ error }}</div>{% endif %}
      <form method="post">
        <input type="hidden" name="token" value="{{ token }}">
        <input type="password" name="pw1" placeholder="New password (min 8 chars)" minlength="8" required>
        <input type="password" name="pw2" placeholder="Confirm new password" minlength="8" required>
        <button type="submit">Update Password</button>
      </form>
      <div class="hint">After updating, open the Dreamr app and log in.</div>
    {% endif %}
  </div>
</body>
</html>
"""

# Confirm email with token
# ---------------------------------------------------------------------------
# Minimal web reset page (temporary until mobile deep-link is live)
# ---------------------------------------------------------------------------
CONFIRM_PAGE_TEMPLATE = """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Dreamr account confirmation</title>
  <meta name="robots" content="noindex,nofollow">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body { background:#0b0420; color:#fff; font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu; display:flex; min-height:100vh; align-items:center; justify-content:center; margin:0; }
    .card { width: min(520px, 92vw); background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.12); border-radius: 14px; padding: 22px; box-shadow: 0 6px 24px rgba(0,0,0,0.35); }
    h1 { font-size: 20px; margin: 0 0 8px; }
    p { color:#D1B2FF; margin: 0 0 16px; }
    .hint{ font-size:12px; color:#bfb8d8; margin-top:8px; text-align:center;}
  </style>
</head>
<body>
  <div class="card">
    {% if status == "ok" %}
      <h1>Account confirmed</h1>
      <p>You're all set! Open the Dreamr app and sign in.</p>
      <div class="hint">You can close this window.</div>
    {% elif status == "exists" %}
      <h1>Already confirmed</h1>
      <p>Your account was already active. Open the Dreamr app and sign in.</p>
      <div class="hint">You can close this window.</div>
    {% elif status == "expired" %}
      <h1>Link expired</h1>
      <p>Please request a new confirmation email from the Dreamr app.</p>
      <div class="hint">You can close this window.</div>
    {% else %}
      <h1>Invalid link</h1>
      <p>This confirmation link is not valid.</p>
      <div class="hint">You can close this window.</div>
    {% endif %}
  </div>
</body>
</html>
"""



# google auth
oauth = OAuth(app)

with open('google_oauth_credentials.json') as f:
    google_creds = json.load(f)

google = oauth.register(
    name='google',
    client_id=google_creds['web']['client_id'],
    client_secret=google_creds['web']['client_secret'],
    access_token_url='https://oauth2.googleapis.com/token',
    authorize_url='https://accounts.google.com/o/oauth2/auth',
    api_base_url='https://www.googleapis.com/oauth2/v2/',
    client_kwargs={'scope': 'openid email profile'},
    server_metadata_url='https://accounts.google.com/.well-known/openid-configuration'
)

# Models
class User(db.Model, UserMixin):
    __tablename__ = 'users'

    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(120), unique=True, nullable=False)
    # password = db.Column(db.String(128), nullable=False)
    password = db.Column(db.String(128), nullable=True, default='')
    first_name = db.Column(db.String(50), nullable=True)
    birthdate = db.Column(db.Date, nullable=True)
    gender = db.Column(db.String(20), nullable=True)  # e.g., "male", "female", prefer not to say"
    signup_date = db.Column(db.DateTime, default=db.func.now())
    timezone = db.Column(db.String(50), nullable=True)  # e.g., "America/Los_Angeles"
    language = db.Column(db.String(10), nullable=True, default='en')
    avatar_filename = db.Column(db.String(200), nullable=True)
    enable_audio = db.Column(db.Boolean, default=False)
    email_confirmed = db.Column(db.Boolean, nullable=False, server_default=text("0"))
    apple_user_id = db.Column(db.String(255), unique=True, nullable=True, index=True)
    subscriptions = db.relationship("UserSubscription", back_populates="user")
    payments = db.relationship("PaymentTransaction", back_populates="user")

class PendingUser(db.Model):
    __tablename__ = 'pendingusers'

    uuid = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    email = db.Column(db.String(120), unique=True, nullable=False)
    password = db.Column(db.String(128), nullable=False)
    first_name = db.Column(db.String(50), nullable=True)
    signup_date = db.Column(db.DateTime, default=db.func.now())
    timezone = db.Column(db.String(50), nullable=True)  # e.g., "America/Los_Angeles"
    language = db.Column(db.String(10), nullable=True, default='en')
    expires_at = db.Column(db.DateTime, default=lambda: datetime.utcnow() + timedelta(hours=24))

class Dream(db.Model):
    __tablename__ = "dream"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    text = db.Column(db.Text)                      # user's dream text
    analysis = db.Column(db.Text)                  # AI's response
    summary = db.Column(db.Text)                   # AI's response summarized
    tone = db.Column(db.String(50))                # AI's tone evaluation
    image_prompt = db.Column(db.Text)              # AI's image prompt
    hidden = db.Column(db.Boolean, default=False)  # Hides the entry (reversable)
    image_file = db.Column(db.String(255))         # saved filename (e.g., 'dream_123.png')
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    notes = db.Column(db.Text, nullable=True)
    notes_updated_at = db.Column(db.DateTime, nullable=True)
    is_question = db.Column(db.Boolean, nullable=False, server_default=db.text("0"))

    def set_notes(self, notes_text):
        # Only treat explicit None as clear
        if notes_text is None:
            self.notes = None
        else:
            # Optional normalization (keeps user’s spaces):
            txt = str(notes_text).replace("\r\n", "\n")
            self.notes = txt
        self.notes_updated_at = datetime.utcnow()


    def __repr__(self):
        return f"<Dream id={self.id} user_id={self.user_id} hidden={self.hidden}>"

class LifeEvent(db.Model):
    __tablename__ = "life_event"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)

    title = db.Column(db.String(120), nullable=False)     # e.g., "Car accident"
    details = db.Column(db.Text, nullable=True)           # optional narrative
    occurred_at = db.Column(db.DateTime, nullable=False)  # when it happened
    tags = db.Column(MySQLJSON, nullable=True)            # e.g., ["accident","injury"]

    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    # helpful indexes: (user_id, occurred_at) for quick recent-pull
    __table_args__ = (
        db.Index("ix_life_event_user_occurred", "user_id", "occurred_at"),
    )

    def __repr__(self):
        return f"<LifeEvent id={self.id} user_id={self.user_id} title={self.title!r}>"

class PasswordResetToken(db.Model):
    __tablename__ = 'password_reset_tokens'
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False, index=True)
    token_hash = db.Column(db.String(64), unique=True, nullable=False, index=True)  # sha256 hex
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    expires_at = db.Column(db.DateTime, nullable=False)
    used_at = db.Column(db.DateTime, nullable=True)
    request_ip = db.Column(db.String(64))
    user_agent = db.Column(db.String(256))
    user = db.relationship('User')


class EmailConfirmToken(db.Model):
    __tablename__ = 'email_confirm_tokens'

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False, index=True)
    token_hash = db.Column(db.String(64), unique=True, nullable=False, index=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    expires_at = db.Column(db.DateTime, nullable=False)
    used_at = db.Column(db.DateTime, nullable=True)
    user = db.relationship('User')

# models/subscriptions.py
# --- Subscription plans ---
class SubscriptionPlan(db.Model):
    __tablename__ = "subscription_plans"

    id = db.Column(db.String(50), primary_key=True)  # e.g., "pro_monthly"
    name = db.Column(db.String(100), nullable=False)
    description = db.Column(db.Text)
    price = db.Column(db.Numeric(10, 2), nullable=False)
    period = db.Column(db.String(20), nullable=False)  # 'monthly', 'yearly'
    features = db.Column(MySQLJSON)
    product_id = db.Column(db.String(100))

    created_at = db.Column(db.DateTime, server_default=text("CURRENT_TIMESTAMP"), nullable=False)
    updated_at = db.Column(
        db.DateTime,
        server_default=text("CURRENT_TIMESTAMP"),
        server_onupdate=text("CURRENT_TIMESTAMP"),
        nullable=False,
    )

    user_subscriptions = db.relationship("UserSubscription", back_populates="plan")

# --- User subscriptions ---
class UserSubscription(db.Model):
    __tablename__ = "user_subscriptions"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    plan_id = db.Column(db.String(50), db.ForeignKey("subscription_plans.id"), nullable=False, index=True)

    status = db.Column(db.String(20), nullable=False)  # active/canceled/expired
    start_date = db.Column(db.DateTime, nullable=False)
    end_date = db.Column(db.DateTime)

    auto_renew = db.Column(db.Boolean, server_default=text("0"), nullable=False)
    payment_method = db.Column(db.String(50))
    payment_provider = db.Column(db.String(50))
    provider_subscription_id = db.Column(db.String(100), index=True)
    provider_transaction_id = db.Column(db.String(100), index=True)
    receipt_data = db.Column(db.Text)

    created_at = db.Column(db.DateTime, server_default=text("CURRENT_TIMESTAMP"), nullable=False)
    updated_at = db.Column(
        db.DateTime,
        server_default=text("CURRENT_TIMESTAMP"),
        server_onupdate=text("CURRENT_TIMESTAMP"),
        nullable=False,
    )

    user = db.relationship("User", back_populates="subscriptions")
    plan = db.relationship("SubscriptionPlan", back_populates="user_subscriptions")
    payments = db.relationship("PaymentTransaction", back_populates="subscription")

# --- Payment transactions ---
class PaymentTransaction(db.Model):
    __tablename__ = "payment_transactions"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    subscription_id = db.Column(db.Integer, db.ForeignKey("user_subscriptions.id"), index=True)

    amount = db.Column(db.Numeric(10, 2), nullable=False)
    currency = db.Column(db.String(3), server_default=text("'USD'"), nullable=False)

    status = db.Column(db.String(20), nullable=False)   # pending/completed/failed
    provider = db.Column(db.String(50), nullable=False) # apple/google/stripe
    provider_transaction_id = db.Column(db.String(100), index=True)

    provider_response = db.Column(MySQLJSON)
    created_at = db.Column(db.DateTime, server_default=text("CURRENT_TIMESTAMP"), nullable=False)

    user = db.relationship("User", back_populates="payments")
    subscription = db.relationship("UserSubscription", back_populates="payments")

# --- For free users ---
class UserCredits(db.Model):
    __tablename__ = "user_credits"

    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), primary_key=True)
    text_remaining_week = db.Column(db.Integer, nullable=False, default=2)
    image_remaining_lifetime = db.Column(db.Integer, nullable=False, default=3)
    week_anchor_utc = db.Column(db.DateTime, nullable=False)
    updated_at = db.Column(
        db.DateTime,
        server_default=text("CURRENT_TIMESTAMP"),
        server_onupdate=text("CURRENT_TIMESTAMP"),
        nullable=False,
    )

    user = db.relationship("User", backref=db.backref("credits", uselist=False))

# --- Subscription Service ---
class SubscriptionService:
    @staticmethod
    def get_user_subscription_status(user_id):
        """Get the current subscription status for a user"""
        # Find the most recent active subscription
        subscription = UserSubscription.query.filter_by(
            user_id=user_id, 
            status='active'
        ).order_by(UserSubscription.end_date.desc()).first()
        
        if not subscription:
            # Return default free tier if no active subscription
            from quota import ensure_week_current, next_reset_iso  # safe import here
            uc = ensure_week_current(user_id)
            
            return {
                'tier': 'free',
                'expiry_date': None,
                'is_active': False,
                'auto_renew': False,
                'payment_method': None,
                'text_remaining_week': uc.text_remaining_week,
                'image_remaining_lifetime': uc.image_remaining_lifetime,
                'next_reset_iso': next_reset_iso(user_id)
            }
        
        # Get the plan details
        plan = subscription.plan
        
        return {
            'tier': plan.id,
            'expiry_date': subscription.end_date.isoformat() if subscription.end_date else None,
            'is_active': subscription.status == 'active',
            'auto_renew': subscription.auto_renew,
            'payment_method': subscription.payment_method
        }
    
    @staticmethod
    def get_subscription_plans():
        """Get all available subscription plans"""
        plans = SubscriptionPlan.query.all()
        return [{
            'id': plan.id,
            'name': plan.name,
            'description': plan.description,
            'price': float(plan.price),
            'period': plan.period,
            'features': plan.features,
            'product_id': plan.product_id
        } for plan in plans]
    
    @staticmethod
    def initiate_subscription(user_id, plan_id, payment_provider=None, receipt_data=None):
        """
        Initiate a subscription purchase
        
        Args:
            user_id: The user ID
            plan_id: The subscription plan ID
            payment_provider: The payment provider (apple/google/stripe)
            receipt_data: Receipt data for app store purchases
            
        Returns:
            Dictionary with subscription details or payment URL
        """
        # Allow lookup by primary key or by product_id (store product identifier)
        plan = SubscriptionPlan.query.get(plan_id)
        if not plan:
            plan = SubscriptionPlan.query.filter_by(product_id=plan_id).first()
        if not plan:
            raise ValueError(f"Plan {plan_id} not found")
        
        # Handle different payment providers
        if payment_provider in ('apple', 'google'):
            # Verify receipt with app store/google play
            if not receipt_data:
                raise ValueError("Receipt data required for app store/google play purchases")
            
            # Verify receipt (implementation depends on provider)
            if payment_provider == 'apple':
                verification_result = SubscriptionService._verify_apple_receipt(receipt_data)
            else:  # google
                verification_result = SubscriptionService._verify_google_receipt(receipt_data)
            
            if not verification_result.get('valid'):
                raise ValueError(f"Invalid receipt: {verification_result.get('message')}")
            
            # Create subscription record
            subscription = SubscriptionService._create_subscription(
                user_id=user_id,
                plan_id=plan_id,
                payment_provider=payment_provider,
                provider_subscription_id=verification_result.get('subscription_id'),
                provider_transaction_id=verification_result.get('transaction_id'),
                receipt_data=receipt_data,
                auto_renew=True
            )
            
            # Create payment record
            SubscriptionService._create_payment(
                user_id=user_id,
                subscription_id=subscription.id,
                amount=float(plan.price),
                provider=payment_provider,
                provider_transaction_id=verification_result.get('transaction_id'),
                provider_response=verification_result
            )
            
            return {'success': True}
        
        elif payment_provider == 'stripe':
            # For web payments, create a Stripe checkout session
            # This is a placeholder - you would integrate with Stripe API here
            payment_url = f"https://example.com/checkout?plan={plan_id}&user={user_id}"
            return {'payment_url': payment_url}
        
        else:
            # Default web payment flow (customize based on your payment processor)
            payment_url = f"https://example.com/checkout?plan={plan_id}&user={user_id}"
            return {'payment_url': payment_url}
    
    @staticmethod
    def cancel_subscription(user_id):
        """Cancel a user's subscription"""
        subscription = UserSubscription.query.filter_by(
            user_id=user_id, 
            status='active'
        ).order_by(UserSubscription.end_date.desc()).first()
        
        if not subscription:
            return False
        
        # Update subscription status
        subscription.status = 'canceled'
        subscription.auto_renew = False
        db.session.commit()
        
        # If using a payment provider, you might need to cancel with them too
        if subscription.payment_provider in ('apple', 'google', 'stripe'):
            # This would be implemented based on the provider's API
            pass
        
        return True
    
    @staticmethod
    def update_payment_method(user_id, payment_details):
        """Update a user's payment method"""
        subscription = UserSubscription.query.filter_by(
            user_id=user_id, 
            status='active'
        ).order_by(UserSubscription.end_date.desc()).first()
        
        if not subscription:
            return False
        
        # Update payment method
        subscription.payment_method = payment_details.get('method')
        db.session.commit()
        
        # If using a payment provider, you might need to update with them too
        if subscription.payment_provider in ('apple', 'google', 'stripe'):
            # This would be implemented based on the provider's API
            pass
        
        return True
    
    @staticmethod
    def _create_subscription(user_id, plan_id, payment_provider=None, 
                            provider_subscription_id=None, provider_transaction_id=None,
                            receipt_data=None, auto_renew=False):
        """Create a subscription record"""
        plan = SubscriptionPlan.query.get(plan_id)
        
        # Calculate end date based on period
        start_date = datetime.utcnow()
        if plan.period == 'monthly':
            end_date = start_date + relativedelta(months=1)
        elif plan.period == 'yearly':
            end_date = start_date + relativedelta(years=1)
        else:
            # Default to 30 days if period is unknown
            end_date = start_date + timedelta(days=30)
        
        subscription = UserSubscription(
            user_id=user_id,
            plan_id=plan_id,
            status='active',
            start_date=start_date,
            end_date=end_date,
            auto_renew=auto_renew,
            payment_method=payment_provider,
            payment_provider=payment_provider,
            provider_subscription_id=provider_subscription_id,
            provider_transaction_id=provider_transaction_id,
            receipt_data=receipt_data
        )
        
        db.session.add(subscription)
        db.session.commit()
        return subscription
    
    @staticmethod
    def _create_payment(user_id, subscription_id, amount, provider, 
                       provider_transaction_id=None, provider_response=None):
        """Create a payment record"""
        payment = PaymentTransaction(
            user_id=user_id,
            subscription_id=subscription_id,
            amount=amount,
            status='completed',
            provider=provider,
            provider_transaction_id=provider_transaction_id,
            provider_response=provider_response
        )
        
        db.session.add(payment)
        db.session.commit()
        return payment
    
    # added by AZAD, not used
    @staticmethod
    def upsert_manual_subscription(
        user_id,
        plan_id,
        months=None,
        years=None,
        expires_at=None,
        payment_provider=None,
    ):
        """Manually create or repair an active subscription for a user.

        Useful for admin repair tools when the store reports an active
        subscription but the local DB is out of sync.
        """
        plan = SubscriptionPlan.query.get(plan_id)
        if not plan:
            raise ValueError(f"Plan {plan_id} not found")

        now = datetime.utcnow()
        if expires_at is None:
            # Default to one billing period unless months/years override it
            if months is not None:
                expires_at = now + relativedelta(months=months)
            elif years is not None:
                expires_at = now + relativedelta(years=years)
            elif plan.period == 'monthly':
                expires_at = now + relativedelta(months=1)
            elif plan.period == 'yearly':
                expires_at = now + relativedelta(years=1)
            else:
                expires_at = now + timedelta(days=30)

        # Most recent subscription for this user/plan, if any
        sub = (
            UserSubscription.query
            .filter_by(user_id=user_id, plan_id=plan_id)
            .order_by(UserSubscription.end_date.desc())
            .first()
        )

        if sub is None:
            sub = UserSubscription(
                user_id=user_id,
                plan_id=plan_id,
                status='active',
                start_date=now,
                end_date=expires_at,
                auto_renew=True,
                payment_method=payment_provider or 'manual',
                payment_provider=payment_provider or 'manual',
            )
            db.session.add(sub)
        else:
            sub.status = 'active'
            sub.end_date = expires_at
            sub.auto_renew = True
            if payment_provider:
                sub.payment_provider = payment_provider
                sub.payment_method = payment_provider

        db.session.commit()
        return sub
    
    @staticmethod
    def _verify_apple_receipt(receipt_data):
        """
        Verify an Apple App Store receipt
        1. Send the receipt to Apple's verification endpoint
        2. Parse the response
        3. Validate the subscription details
        """
        verify_url = "https://buy.itunes.apple.com/verifyReceipt"  # Use sandbox URL for testing
        response = requests.post(verify_url, json={"receipt-data": receipt_data})
        result = response.json()
        # Validate the response and extract subscription details
        if result.get("status") == 0:  # 0 = valid receipt
            # Extract subscription ID, transaction ID, expiry date, etc.
            return {
                'valid': True,
                'subscription_id': result.get("latest_receipt_info")[0].get("original_transaction_id"),
                'transaction_id': result.get("latest_receipt_info")[0].get("transaction_id"),
                # 'expiry_date': # Convert timestamp to ISO date
            }
        else:
            return {'valid': False, 'message': f"Invalid receipt: {result.get('status')}"}

    
    @staticmethod
    def _verify_google_receipt(receipt_data):
        """
        Verify a Google Play receipt
        
        This is a placeholder. In a real implementation, you would:
        1. Verify the purchase token with Google's API
        2. Parse the response
        3. Validate the subscription details
        """
        # Placeholder implementation
        return {
            'valid': True,
            'subscription_id': f"google_{uuid.uuid4()}",
            'transaction_id': f"google_txn_{uuid.uuid4()}",
            'expiry_date': (datetime.utcnow() + relativedelta(months=1)).isoformat()
        }

    def _create_stripe_checkout_session(user_id, plan_id):
        """
        Create a Stripe checkout session for a subscription
        """
        plan = SubscriptionPlan.query.get(plan_id)
        # Create a Stripe checkout session
        session = stripe.checkout.Session.create(
            payment_method_types=['card'],
            line_items=[{
                'price_data': {
                    'currency': 'usd',
                    'product_data': {
                        'name': plan.name,
                        'description': plan.description,
                    },
                    'unit_amount': int(float(plan.price) * 100),  # Stripe uses cents
                    'recurring': {
                        'interval': 'month' if plan.period == 'monthly' else 'year',
                    },
                },
                'quantity': 1,
            }],
            mode='subscription',
            success_url=f"https://your-app.com/subscription/success?session_id={{CHECKOUT_SESSION_ID}}",
            cancel_url=f"https://your-app.com/subscription/cancel",
            client_reference_id=str(user_id),
            metadata={
                'user_id': user_id,
                'plan_id': plan_id,
            },
        )
        return session.url

    def process_subscription_renewals():
        """
        Process subscription renewals and expirations
        """
        # Get all active subscriptions that are due for renewal
        subscriptions = UserSubscription.query.filter(
            UserSubscription.status == 'active',
            UserSubscription.end_date <= datetime.utcnow() + timedelta(days=1),
            UserSubscription.auto_renew == True
        ).all()
        for subscription in subscriptions:
            # Process renewal based on payment provider
            if subscription.payment_provider == 'apple':
                # Verify subscription status with Apple
                pass
            elif subscription.payment_provider == 'google':
                # Verify subscription status with Google
                pass
            elif subscription.payment_provider == 'stripe':
                # Process renewal with Stripe
                pass


    
# Notes
NOTES_MAX_LEN = 8000
NOTES_AI_ENABLED = False
REANALYZE_WITH_NOTES_ALLOWED = False
NOTES_POLICY_VERSION = "v1"

# pro
def _user_is_pro(user_id: int) -> bool:
    try:
        st = SubscriptionService.get_user_subscription_status(user_id)
        tier = (st.get("tier") or "").lower()
        active = st.get("is_active") is True
        return active and (tier.startswith("pro") or tier.startswith("trial"))
    except Exception:
        return False

# Checks if user can generate images (pro or has free credits)
def _can_generate_image(user_id: int) -> bool:
    # Check if pro user
    if _user_is_pro(user_id):
        return True
    
    # Check if free user with remaining image credits
    try:
        credits = get_or_create_credits(user_id)
        return credits.image_remaining_lifetime > 0
    except Exception:
        return False

from functools import wraps
from flask import jsonify

def requires_pro(fn):
    @wraps(fn)
    def _wrap(*args, **kwargs):
        if not current_user.is_authenticated or not _user_is_pro(current_user.id):
            return jsonify({"error": "pro_required"}), 402
        return fn(*args, **kwargs)
    return _wrap

def _iso_utc(dt: datetime | None) -> str | None:
    if not dt:
        return None
    # store naive UTC in DB; emit ISO with Z for API consistency
    return dt.replace(tzinfo=timezone.utc).isoformat().replace("+00:00", "Z")

def _notes_conflict(d: Dream, last_seen: str | None) -> bool:
    """True if client-supplied last_seen doesn't match current server timestamp."""
    if not last_seen:
        return False
    cur = _iso_utc(d.notes_updated_at)
    return cur is not None and last_seen.strip() != cur.strip()


def _hash_token(raw: str) -> str:
    return hashlib.sha256(raw.encode('utf-8')).hexdigest()

RESET_TTL_MINUTES = 60  # tweak as you like

def _generate_raw_token() -> str:
    return secrets.token_urlsafe(32)

def _password_policy_ok(pw: str) -> bool:
    return isinstance(pw, str) and len(pw) >= 8  # expand if needed
  
# class DreamTone(Enum):
#     PEACEFUL = "Peaceful / gentle"
#     EPIC = "Epic / heroic"
#     WHIMSICAL = "Whimsical / surreal"
#     NIGHTMARISH = "Nightmarish / dark"
#     ROMANTIC = "Romantic / nostalgic"
#     ANCIENT = "Ancient / mythic"
#     FUTURISTIC = "Futuristic / uncanny"
#     ELEGANT = "Elegant / ornate"

@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))



# Sends confirmation email (new)
def send_confirmation_email(recipient_email, token):
    base = app.config.get("CONFIRM_LINK_BASE", "https://dreamr-us-west-01.zentha.me/confirm")
    confirm_url = f"{base}?token={token}"
    msg = Message(
        subject="Confirm your Dreamr✨account",
        recipients=[recipient_email],
        body=(
            "Welcome to Dreamr!\n\n"
            "Click the link below to confirm your account:\n\n"
            f"{confirm_url}\n\n"
            "After confirming, open the Dreamr app and sign in.\n"
            "If you didn't sign up for Dreamr, ignore this message."
        )
    )
    mail.send(msg)


# Profile pic stuff
UPLOAD_FOLDER = '/data/dreamr-frontend/static/avatars'
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


# --- Admin helpers ---
# def is_admin_user():
#     return current_user.is_authenticated and (current_user.email or "").lower() in ADMIN_EMAILS

def _get_admin_emails():
    cfg = (current_app.config.get("ADMIN_EMAILS")
           or os.getenv("ADMIN_EMAILS")
           or "")
    # allow comma or semicolon
    parts = cfg.replace(";", ",").split(",")
    return {p.strip().lower() for p in parts if p.strip()}

def is_admin_user():
    return current_user.is_authenticated and (current_user.email or "").lower() in _get_admin_emails()
    

def admin_required(fn):
    from functools import wraps
    @wraps(fn)
    @login_required
    def _wrap(*a, **k):
        if not is_admin_user():
            abort(403)
        return fn(*a, **k)
    return _wrap



# ROUTES
# for fetching all file names (not images) to display on landing page
@app.route("/api/images", methods=["GET"])
def get_images():
    IMAGE_DIR = "/data/dreamr-frontend/static/images/dreams"
    files = os.listdir(IMAGE_DIR)
    return jsonify([f for f in files if f.endswith(".png")])


# profile update page
@app.route('/api/profile', methods=['GET', 'POST'])
@login_required
def profile():
    user = current_user

    if request.method == 'GET':
        return jsonify({
            'email': user.email,
            'first_name': user.first_name,
            'birthdate': user.birthdate.isoformat() if user.birthdate else '',
            'gender': user.gender,
            'timezone': user.timezone,
            'avatar_url': f'/static/avatars/{user.avatar_filename}' if user.avatar_filename else '',
            'enable_audio': user.enable_audio
        })

    # POST: update profile
    data = request.form
    file = request.files.get('avatar')

    if 'email' in data:
        user.email = data['email']
    if 'first_name' in data:
        user.first_name = data['first_name']
    if 'birthdate' in data:
        try:
            user.birthdate = datetime.strptime(data['birthdate'], '%Y-%m-%d').date()
        except ValueError:
            return jsonify({'error': 'Invalid birthdate format'}), 400
    if 'gender' in data:
        user.gender = data['gender']
    if 'timezone' in data:
        user.timezone = data['timezone']

    if file and allowed_file(file.filename):
        filename = secure_filename(file.filename)
        filepath = os.path.join(UPLOAD_FOLDER, filename)
        os.makedirs(UPLOAD_FOLDER, exist_ok=True)
        file.save(filepath)
        user.avatar_filename = filename

    if 'enable_audio' in data:
      user.enable_audio = data['enable_audio'].lower() in ['true', '1', 'yes']

    db.session.commit()
    # return jsonify({'success': True})
    return jsonify({
      'first_name': user.first_name
  })


# for google logins via web app
@app.route('/login/google')
def login_google():
    redirect_uri = url_for('auth_google', _external=True)
    return google.authorize_redirect(redirect_uri)

# for google logins via web app
@app.route('/auth/google')
def auth_google():
    token = google.authorize_access_token()
    resp = google.get('userinfo')
    user_info = resp.json()

    email = user_info['email']
    full_name = user_info.get("name", "")
    name = full_name.split()[0] if full_name else ""

    # Check if user exists
    user = User.query.filter_by(email=email).first()
    if not user:
        user = User(
            email=email,
            first_name=name or "Unknown",
            password='',
            timezone='',
            email_confirmed=True,
        )
        db.session.add(user)
        db.session.commit()
    elif not user.email_confirmed:
        user.email_confirmed = True
        db.session.commit()

    # login_user(user)
    login_user(user, remember=True, duration=timedelta(days=90))
    # return redirect("/dashboard?confirmed=1")
    return redirect("/dashboard")



# for google logins via mobile app
@app.route('/api/google_login', methods=['POST'])
def api_google_login():
    data = request.get_json(silent=True) or {}
    token = data.get('id_token')
    if not token:
        return jsonify({"error": "missing id_token"}), 400

    try:
        req = google_requests.Request()
        # 1) Verify signature & claims, but don't pin the audience yet
        idinfo = id_token.verify_oauth2_token(token, req, audience=None)

        aud = idinfo.get("aud")
        azp = idinfo.get("azp")
        iss = idinfo.get("iss")
        email = idinfo.get("email")
        email_verified = idinfo.get("email_verified", False)
        full_name = idinfo.get("name") or ""
        first_name = full_name.split()[0] if full_name else "Unknown"

        # 2) Strict issuer check
        if iss not in ALLOWED_ISS:
            raise ValueError(f"bad iss: {iss}")

        # 3) Accept Web or iOS client as audience (common on native apps)
        if aud not in ALLOWED_AUDS:
            # Some Google flows put Web client in azp and iOS in aud — allow either.
            if azp not in ALLOWED_AUDS:
                raise ValueError(f"bad aud: {aud} azp: {azp}")

        if not email or not email_verified:
            raise ValueError("email not verified")

        # 4) Normal login / signup flow
        user = User.query.filter_by(email=email).first()
        if not user:
            user = User(
                email=email,
                first_name=first_name,
                password='',
                timezone='',
                email_confirmed=True,
            )
            db.session.add(user)
            db.session.commit()
        elif not user.email_confirmed:
            user.email_confirmed = True
            db.session.commit()

        login_user(user)
        return jsonify({"success": True})

    except Exception as e:
        # Optional: peek safe fields for troubleshooting (no full token logging)
        try:
            logger.info("google login failed: aud=%s azp=%s iss=%s email=%s err=%s",
                     idinfo.get("aud") if 'idinfo' in locals() else None,
                     idinfo.get("azp") if 'idinfo' in locals() else None,
                     idinfo.get("iss") if 'idinfo' in locals() else None,
                     idinfo.get("email") if 'idinfo' in locals() else None,
                     e)
        except Exception:
            logger.info("google login failed: %s", e)
        return jsonify({"error": "Invalid token, naughty!"}), 400

# helper for Apple verification
def verify_apple_identity_token(identity_token: str) -> dict:
    """Verify an Apple Sign in with Apple identity token (JWT) and return its claims."""
    if not APPLE_CLIENT_ID:
        raise RuntimeError(
            "APPLE_CLIENT_ID or APPLE_BUNDLE_ID must be configured on the server"
        )

    try:
        # Get the signing key for this token from Apple's JWKS
        signing_key = _apple_jwk_client.get_signing_key_from_jwt(identity_token)
    except Exception as e:
        logger.exception("Failed to get Apple signing key from JWKS: %s", e)
        raise

    try:
        claims = jwt.decode(
            identity_token,
            signing_key.key,
            algorithms=["RS256"],
            audience=APPLE_CLIENT_ID,
            issuer=APPLE_ISSUER,
        )
        # Log the good case at info level once while testing
        # logger.info(
        #     "Apple token verified: iss=%s aud=%s sub=%s email=%s exp=%s",
        #     claims.get("iss"),
        #     claims.get("aud"),
        #     claims.get("sub"),
        #     claims.get("email"),
        #     claims.get("exp"),
        # )
        return claims

    except InvalidTokenError as e:
        # Try decoding without verification just so we can inspect claims.
        try:
            raw_claims = jwt.decode(
                identity_token,
                options={
                    "verify_signature": False,
                    "verify_aud": False,
                    "verify_iss": False,
                    "verify_exp": False,
                },
            )
            # logger.warning(
            #     "Apple token failed verification (%s). Raw claims: iss=%s aud=%s sub=%s email=%s exp=%s",
            #     e,
            #     raw_claims.get("iss"),
            #     raw_claims.get("aud"),
            #     raw_claims.get("sub"),
            #     raw_claims.get("email"),
            #     raw_claims.get("exp"),
            # )
        except Exception as inner:
            logger.warning(
                "Apple token failed verification (%s) and could not decode raw claims: %s",
                e,
                inner,
            )
        raise

    except Exception as e:
        logger.exception("Unexpected error verifying Apple identity token: %s", e)
        raise



# Apple Logins on IOS
@app.route("/api/apple_login", methods=["POST"])
def apple_login():
    data = request.get_json(silent=True) or {}
    identity_token = data.get("identity_token")
    authorization_code = data.get("authorization_code")  # currently unused
    user_identifier = data.get("user_identifier")
    email = data.get("email")
    full_name = data.get("full_name")
    first_name = full_name.split()[0] if full_name else "Unknown"

    if not identity_token:
        return jsonify({"error": "Missing identity token"}), 400

    # Verify the Apple identity token (signature + iss/aud/exp).
    try:
        claims = verify_apple_identity_token(identity_token)
    except (InvalidTokenError, RuntimeError) as e:
        logger.info("Apple login failed token check: %s", e)
        return jsonify({"error": "Invalid Apple identity token"}), 400
    except Exception:
        logger.exception("Apple login unexpected error while verifying token")
        return jsonify({"error": "Apple identity token verification failed"}), 400

    token_sub = claims.get("sub")
    if not token_sub:
        return jsonify({"error": "Apple identity token missing subject"}), 400

    # If the client also sent a user_identifier, make sure it matches the token.
    if user_identifier and user_identifier != token_sub:
        return jsonify({"error": "Apple user id mismatch"}), 400

    apple_user_id = token_sub

    email_from_token = claims.get("email")
    email_verified = claims.get("email_verified")
    if isinstance(email_verified, str):
        email_verified = email_verified.lower() == "true"

    # Prefer the (verified) email from the token, but fall back to payload.
    if email_from_token and (email_verified is True or email_verified is None):
        email = email_from_token or email

    # 1) Try by apple_user_id first
    user = User.query.filter_by(apple_user_id=apple_user_id).first()

    # 2) If no user yet, try merge by email (if Apple gave one)
    if not user and email:
        user = User.query.filter_by(email=email).first()

    # 3) If still no user, create a new one
    if not user:
        if not email:
            # Apple should provide an email (real or relay) on first auth.
            # If not, we can't safely create an account.
            return jsonify({"error": "Apple did not provide an email address, try clearing your saved password for Dreamr in Settings/<your account>/Sign in with apple - and try again"}), 400

        user = User(
            apple_user_id=apple_user_id,
            email=email,
            first_name=first_name,
            password='',
            timezone='',
            email_confirmed=True,
        )
        db.session.add(user)
    else:
        # Attach Apple ID if we found user by email only
        if not user.apple_user_id:
            user.apple_user_id = apple_user_id

    try:
        db.session.commit()
    except IntegrityError:
        db.session.rollback()
        return jsonify({"error": "Account conflict, please contact support"}), 400

    # 4) Log the user in (session cookie, same as Google)
    login_user(user)

    return jsonify({"success": True}), 200



# New user registration
@app.route("/api/register", methods=["POST"])
def register():
    data = request.get_json(silent=True) or {}
    first_name = (data.get("first_name") or "").strip()
    email = (data.get("email") or "").strip().lower()
    timezone_val = data.get("timezone")
    password = data.get("password") or ""

    logger.info(f"📨 Registration attempt: {email}")

    EMAIL_REGEX = re.compile(r"^[^@]+@[^@]+\.[^@]+$")

    if not first_name or len(first_name) > 50:
        logger.warning("❌ Invalid name")
        return jsonify({"error": "Name must be 1–50 characters"}), 400

    if not password or len(password) < 8:
        logger.warning("❌ Invalid password")
        return jsonify({"error": "Password must be at least 8 characters"}), 400

    if not email or not EMAIL_REGEX.match(email):
        logger.warning("❌ Invalid email")
        return jsonify({"error": "Invalid email address"}), 400

    # Check for duplicates in users (case-insensitive)
    existing = User.query.filter(func.lower(User.email) == email).first()
    if existing:
        logger.warning("⚠️ Duplicate user registration attempt")
        return jsonify({"error": "User already exists"}), 400

    hashed = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

    # Create real user immediately
    user = User(
        email=email,
        password=hashed,
        first_name=first_name,
        timezone=timezone_val,
        signup_date=datetime.utcnow(),
    )

    db.session.add(user)
    db.session.flush()  # ensure user.id is populated

    # Create a confirmation token, but do not gate access on it
    try:
        raw_token = _generate_raw_token()
        ect = EmailConfirmToken(
            user_id=user.id,
            token_hash=_hash_token(raw_token),
            created_at=datetime.utcnow(),
            expires_at=datetime.utcnow() + timedelta(days=7),
        )
        db.session.add(ect)
        db.session.commit()

        logger.info(f"✅ Registered new user: {email}")
        send_confirmation_email(email, raw_token)
    except Exception:
        # Do not block registration/log-in if email sending fails
        logger.exception("Failed to create/send confirmation token")
        db.session.commit()

    # Log the user in immediately so the app can start using the session
    try:
        login_user(user, remember=True, duration=timedelta(days=90))
    except Exception:
        logger.exception("Failed to log in user immediately after registration")

    return jsonify({
        "message": "Please check your email to confirm your Dreamr✨account"
    })


# Request Password Reset (no user enumeration)
@app.route("/api/request_password_reset", methods=["POST"])
def api_request_password_reset():
    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()

    # Always say 200
    user = User.query.filter(func.lower(User.email) == email).first()
    if user:
        # invalidate outstanding tokens
        PasswordResetToken.query.filter_by(user_id=user.id, used_at=None)\
            .update({PasswordResetToken.used_at: datetime.utcnow()})
        db.session.flush()

        raw = _generate_raw_token()
        prt = PasswordResetToken(
            user_id=user.id,
            token_hash=_hash_token(raw),
            created_at=datetime.utcnow(),
            expires_at=datetime.utcnow() + timedelta(minutes=RESET_TTL_MINUTES),
            request_ip=request.remote_addr,
            user_agent=request.headers.get("User-Agent", "")[:250],
        )
        db.session.add(prt)
        db.session.commit()

        try:
            base = app.config.get("RESET_LINK_BASE", "https://dreamr.zentha.me/reset")
            link = f"{base}?token={raw}"
            msg = Message(
                subject="Reset your Dreamr password",
                recipients=[user.email],
                body=(
                    "We received a request to reset your password.\n\n"
                    f"Open this link to set a new password (expires in {RESET_TTL_MINUTES} minutes):\n{link}\n\n"
                    "If you didn’t request this, ignore this email."
                ),
            )
            mail.send(msg)
        except Exception:
            logger.exception("Failed to send reset email") 

    return jsonify({"message": "If that email exists, a reset link was sent."}), 200


# Confirmation (new)
@app.route("/confirm", methods=["GET"])
def confirm_page():
    """Finalize account via token and show a simple message."""
    raw = request.args.get("token", "", type=str)
    if not raw:
        return render_template_string(CONFIRM_PAGE_TEMPLATE, status="invalid"), 400

    # Primary path: new-style email confirmation tokens
    h = _hash_token(raw)
    ect = EmailConfirmToken.query.filter_by(token_hash=h).first()
    if ect:
        if ect.expires_at < datetime.utcnow():
            return render_template_string(CONFIRM_PAGE_TEMPLATE, status="expired"), 410

        user = ect.user or User.query.get(ect.user_id)
        if not user:
            return render_template_string(CONFIRM_PAGE_TEMPLATE, status="invalid"), 400

        if ect.used_at is not None or user.email_confirmed:
            return render_template_string(CONFIRM_PAGE_TEMPLATE, status="exists"), 200

        user.email_confirmed = True
        ect.used_at = datetime.utcnow()
        db.session.commit()
        return render_template_string(CONFIRM_PAGE_TEMPLATE, status="ok"), 200

    # Legacy fallback for older PendingUser-based links
    pending = PendingUser.query.filter_by(uuid=raw).first()
    if not pending:
        return render_template_string(CONFIRM_PAGE_TEMPLATE, status="invalid"), 400

    if pending.expires_at and pending.expires_at < datetime.utcnow():
        db.session.delete(pending)
        db.session.commit()
        return render_template_string(CONFIRM_PAGE_TEMPLATE, status="expired"), 410

    existing = User.query.filter_by(email=pending.email).first()
    if existing:
        db.session.delete(pending)
        db.session.commit()
        return render_template_string(CONFIRM_PAGE_TEMPLATE, status="exists"), 200

    new_user = User(
        email=pending.email,
        password=pending.password,
        first_name=pending.first_name,
        timezone=pending.timezone,
        signup_date=datetime.utcnow(),
        email_confirmed=True,
    )
    db.session.add(new_user)
    db.session.delete(pending)
    db.session.commit()

    return render_template_string(CONFIRM_PAGE_TEMPLATE, status="ok"), 200


@app.route("/reset", methods=["GET", "POST"])
def reset_page():
    """
    Temporary web UI for password reset.
    GET: show form if token valid, else show 'expired/invalid'.
    POST: set new password and show 'success—open the app'.
    """
    if request.method == "GET":
        raw = request.args.get("token", "", type=str)
        if not raw:
            return render_template_string(RESET_PAGE_TEMPLATE, invalid=True), 400
        h = _hash_token(raw)
        prt = PasswordResetToken.query.filter_by(token_hash=h).first()
        if not prt or prt.used_at is not None or prt.expires_at < datetime.utcnow():
            return render_template_string(RESET_PAGE_TEMPLATE, invalid=True), 400
        return render_template_string(RESET_PAGE_TEMPLATE, token=raw, invalid=False, done=False)

    # POST
    raw = request.form.get("token", "")
    pw1 = request.form.get("pw1", "")
    pw2 = request.form.get("pw2", "")
    if not raw or not pw1 or not pw2:
        return render_template_string(RESET_PAGE_TEMPLATE, invalid=True), 400
    if pw1 != pw2:
        return render_template_string(RESET_PAGE_TEMPLATE, token=raw, error="Passwords do not match"), 400
    if len(pw1) < 8:
        return render_template_string(RESET_PAGE_TEMPLATE, token=raw, error="Use at least 8 characters"), 400

    h = _hash_token(raw)
    prt = PasswordResetToken.query.filter_by(token_hash=h).first()
    if not prt or prt.used_at is not None or prt.expires_at < datetime.utcnow():
        return render_template_string(RESET_PAGE_TEMPLATE, invalid=True), 400

    user = prt.user
    user.password = bcrypt.hashpw(pw1.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
    prt.used_at = datetime.utcnow()
    db.session.commit()

    # (Optional) invalidate other sessions here.

    return render_template_string(RESET_PAGE_TEMPLATE, done=True)


# Password Reset with token
@app.route("/api/reset_password", methods=["POST"])
def api_reset_password():
    data = request.get_json(silent=True) or {}
    raw = data.get("token") or ""
    new_pw = data.get("new_password") or ""
    if not raw or not new_pw:
        return jsonify({"error": "token and new_password required"}), 400
    if not _password_policy_ok(new_pw):
        return jsonify({"error": "Password does not meet policy"}), 400

    h = _hash_token(raw)
    prt = PasswordResetToken.query.filter_by(token_hash=h).first()
    if not prt or prt.used_at is not None or prt.expires_at < datetime.utcnow():
        return jsonify({"error": "Invalid or expired token"}), 400

    user = prt.user
    # set bcrypt hash
    user.password = bcrypt.hashpw(new_pw.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
    prt.used_at = datetime.utcnow()

    # optional: invalidate other sessions here

    db.session.commit()
    return jsonify({"message": "Password updated"}), 200


# Change Password (logged in)
@app.route("/api/change_password", methods=["POST"])
@login_required
def api_change_password():
    data = request.get_json(silent=True) or {}
    current_pw = data.get("current_password") or ""
    new_pw = data.get("new_password") or ""
    if not new_pw:
        return jsonify({"error": "new_password required"}), 400
    if not _password_policy_ok(new_pw):
        return jsonify({"error": "Password does not meet policy"}), 400

    user = current_user  # User

    # If the account was created via Google and has no local password yet
    if not user.password or user.password == "":
        # allow setting initial local password without current_pw
        user.password = bcrypt.hashpw(new_pw.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
        db.session.commit()
        return jsonify({"message": "Password set"}), 200

    # Normal flow: verify current
    ok = False
    try:
        ok = bcrypt.checkpw(current_pw.encode('utf-8'), user.password.encode('utf-8'))
    except Exception:
        ok = False
    if not ok:
        return jsonify({"error": "Current password incorrect"}), 401

    # Disallow reusing same password
    if bcrypt.checkpw(new_pw.encode('utf-8'), user.password.encode('utf-8')):
        return jsonify({"error": "New password must be different"}), 400

    user.password = bcrypt.hashpw(new_pw.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

    # optional: invalidate other sessions here

    db.session.commit()
    return jsonify({"message": "Password changed"}), 200


# Confirmation (for old web-app)
@app.route("/api/confirm/<token>", methods=["GET"])
def confirm_account(token):
    """JSON confirmation endpoint; does not gate access, just flips a flag."""
    raw = token or ""
    if not raw:
        return jsonify({"error": "Invalid or expired confirmation link."}), 404

    # Primary path: new-style confirmation tokens
    h = _hash_token(raw)
    ect = EmailConfirmToken.query.filter_by(token_hash=h).first()
    if ect:
        if ect.expires_at < datetime.utcnow():
            return jsonify({"error": "Confirmation link has expired."}), 410

        user = ect.user or User.query.get(ect.user_id)
        if not user:
            return jsonify({"error": "Invalid or expired confirmation link."}), 404

        if ect.used_at is not None or user.email_confirmed:
            return jsonify({"message": "Account already confirmed."}), 200

        user.email_confirmed = True
        ect.used_at = datetime.utcnow()
        db.session.commit()
        return jsonify({"message": "Account confirmed."}), 200

    # Legacy fallback for older PendingUser-based links
    pending = PendingUser.query.filter_by(uuid=raw).first()
    if not pending:
        return jsonify({"error": "Invalid or expired confirmation link."}), 404

    if pending.expires_at and pending.expires_at < datetime.utcnow():
        db.session.delete(pending)
        db.session.commit()
        return jsonify({"error": "Confirmation link has expired."}), 410

    existing = User.query.filter_by(email=pending.email).first()
    if existing:
        db.session.delete(pending)
        db.session.commit()
        return jsonify({"message": "Account already confirmed."}), 200

    new_user = User(
        email=pending.email,
        password=pending.password,
        first_name=pending.first_name,
        timezone=pending.timezone,
        signup_date=datetime.utcnow(),
        email_confirmed=True,
    )

    db.session.add(new_user)
    db.session.delete(pending)
    db.session.commit()

    login_user(new_user, remember=True)
    return jsonify({"message": "Logged in"})


@app.route("/api/login", methods=["POST"])
def login():
    data = request.get_json() or {}
    email = data.get("email", "").strip().lower() 
    password = data.get("password") or ""
    user = User.query.filter_by(email=email).first()
    if not user or not bcrypt.checkpw(password.encode('utf-8'), user.password.encode('utf-8')):
        return jsonify({"error": "Invalid credentials"}), 401
    login_user(user, remember=True)
    # return jsonify({"message": "Logged in"})
    return jsonify({
        "message": "Logged in",
        "user": {
            "id": user.id,
            "email": user.email
        }
    })


@app.route("/api/logout", methods=["POST"])
@login_required
def logout():
    logout_user()
    return jsonify({"message": "Logged out"})



def call_openai_with_retry(prompt, retries=3, delay=2):
    for attempt in range(retries):
        try:
            response = openai.chat.completions.create(
                model="gpt-4o",
                messages=[{"role": "user", "content": prompt}]
            )
            return response
        except Exception as e:
            logger.warning(f"[GPT Retry] Attempt {attempt+1} failed: {e}")
            if attempt < retries - 1:
                time.sleep(delay)
            else:
                raise

              
def convert_dream_to_image_prompt(message, tone=None, quality="high"):
    if quality == "low":
        base_prompt = CATEGORY_PROMPTS["image_free"]
    else:
        base_prompt = CATEGORY_PROMPTS["image"]
  
    tone = tone.strip() if tone else None
    logger.debug(f"[convert_dream_to_image_prompt] Received tone: {repr(tone)}")
    logger.debug(f"[convert_dream_to_image_prompt] Available tones: {list(TONE_TO_STYLE.keys())}")

    style = TONE_TO_STYLE.get(tone, "Photo Realistic")
    # style = "Steampunk"
    # style = "Photo Realistic"
    # style = "Artistic vivid style"
    # style = "Watercolor fantasy"
    # style = "Concept art"
    # style = "Whimsical children’s book"
    # style = "Dark fairytale"
    # style = "Impressionist art"
    # style = "Mythological fantasy"
    # style = "Cyberdream / retrofuturism"
    # style = "Art Nouveau or Oil Painting"
    logger.debug(f"[convert_dream_to_image_prompt] Selected style: {style}")

    full_prompt = f"{base_prompt}\n\nRender the image in the style of \"{style}\".\n\nDream: {message}"
    response = client.chat.completions.create(
        model="gpt-4o",
        messages=[{"role": "user", "content": full_prompt}]
    )
    return response.choices[0].message.content.strip()


# Use profile details in prompt
def _age_years(birthdate: date | None, asof: date | None = None) -> int | None:
    if not birthdate:
        return None
    asof = asof or datetime.now(timezone.utc).date()
    y = asof.year - birthdate.year
    return y - 1 if (asof.month, asof.day) < (birthdate.month, birthdate.day) else y


def intro_line_for_prompt(user, *, include_gender: bool = True, include_timezone: bool = False) -> str | None:
    """
    Build something like:
      "My name is Mike. I'm a 46-year-old male, based in Los Angeles (America/Los_Angeles)."
    Returns None if nothing useful is available.
    """
    bits = []

    # if user.first_name:
        # bits.append(f"My name is {user.first_name}.")

    age = _age_years(user.birthdate)
    who = []
    if age is not None:
        who.append(f"{age}-year-old")
    if include_gender and user.gender:
        who.append(user.gender.strip().lower())
    if who:
        bits.append("I'm a " + " ".join(who) + ".")

    if include_timezone and user.timezone:
        city = user.timezone.split("/")[-1].replace("_", " ")
        bits.append(f"Based in {city} ({user.timezone}).")

    return " ".join(bits) or None


api = Blueprint("api", __name__)
def _life_event_to_dict(ev: LifeEvent):
    return {
        "id": ev.id,
        "title": ev.title,
        "details": ev.details,
        "occurred_at": ev.occurred_at.replace(tzinfo=timezone.utc).isoformat(),
        "tags": ev.tags or [],
        "created_at": (ev.created_at.replace(tzinfo=timezone.utc).isoformat()
                       if ev.created_at else None),
    }

@api.route("/api/life_events", methods=["GET"])
@login_required
@requires_pro
def list_life_events():
    # ?limit=50 (default), newest first
    try:
        limit = min(int(request.args.get("limit", 50)), 200)
    except Exception:
        limit = 50
    q = LifeEvent.query.filter_by(user_id=current_user.id).order_by(desc(LifeEvent.occurred_at)).limit(limit)
    return jsonify([_life_event_to_dict(ev) for ev in q.all()])

@api.route("/api/life_events", methods=["POST"])
@login_required
@requires_pro
def create_life_event():
    data = request.get_json(force=True, silent=False) or {}
    title = (data.get("title") or "").strip()
    occurred_at_raw = data.get("occurred_at")
    if not title or not occurred_at_raw:
        abort(400, "title and occurred_at are required")
    try:
        occurred_at = datetime.fromisoformat(occurred_at_raw.replace("Z", "+00:00"))
    except Exception:
        abort(400, "occurred_at must be ISO8601")

    details = (data.get("details") or None)
    tags = data.get("tags") or None
    if tags is not None and not isinstance(tags, list):
        abort(400, "tags must be a list of strings")

    ev = LifeEvent(
        user_id=current_user.id,
        title=title,
        details=details,
        occurred_at=occurred_at,
        tags=tags,
    )
    db.session.add(ev)
    db.session.commit()
    return jsonify(_life_event_to_dict(ev)), 201

@api.route("/api/life_events/<int:event_id>", methods=["PATCH"])
@login_required
@requires_pro
def update_life_event(event_id: int):
    ev = LifeEvent.query.filter_by(id=event_id, user_id=current_user.id).first()
    if not ev:
        abort(404)

    data = request.get_json(force=True, silent=False) or {}

    if "title" in data:
        t = (data.get("title") or "").strip()
        if not t:
            abort(400, "title cannot be empty")
        ev.title = t

    if "details" in data:
        ev.details = data.get("details") or None

    if "occurred_at" in data:
        try:
            ev.occurred_at = datetime.fromisoformat(data["occurred_at"].replace("Z", "+00:00"))
        except Exception:
            abort(400, "occurred_at must be ISO8601")

    if "tags" in data:
        tags = data.get("tags")
        if tags is not None and not isinstance(tags, list):
            abort(400, "tags must be a list")
        ev.tags = tags or None

    db.session.commit()
    return jsonify(_life_event_to_dict(ev))

@api.route("/api/life_events/<int:event_id>", methods=["DELETE"])
@login_required
def delete_life_event(event_id: int):
    ev = LifeEvent.query.filter_by(id=event_id, user_id=current_user.id).first()
    if not ev:
        abort(404)
    db.session.delete(ev)
    db.session.commit()
    return jsonify({"ok": True})


# add personal notes
def update_dream_notes(dream_id: int, user_id: int, notes: str | None):
    d = Dream.query.filter_by(id=dream_id, user_id=user_id).first()
    if not d:
        return None
    d.set_notes(notes)
    db.session.commit()
    return d


# Generate blurry images for free gallery (decided to blur images from app side so as to keep the high res images in the back end)
# def generate_blurred_tile(input_path, output_path, size=(256,256)):
#     with Image.open(input_path) as img:
#         img.thumbnail(size)
#         img = img.filter(ImageFilter.GaussianBlur(radius=6))
#         os.makedirs(os.path.dirname(output_path), exist_ok=True)
#         img.save(output_path, "PNG")

# # inside /api/image_generate after saving the main file:
# tile_path = os.path.join("static","images","tiles", filename)
# blur_path = os.path.join("static","images","tiles_blur", filename)
# generate_resized_image(image_path, tile_path, size=(256,256))
# generate_blurred_tile(image_path, blur_path, size=(256,256))



# --- NEW: helpers ------------------------------------------------------------
_TYPE_LINE = r"^\s*\**\s*Type\s*:\s*(Dream|Question)\s*\**\s*$"
_FLAGS = re.I | re.M
_TYPE_RE = re.compile(_TYPE_LINE, _FLAGS)

def _parse_is_question(ai_text: str) -> bool:
    m = _TYPE_RE.search(ai_text or "")
    return bool(m and m.group(1).lower() == "question")

def _parse_iso_dt(value: str) -> datetime:
    # Accept "YYYY-MM-DD" or full ISO; raise on bad input
    v = value.strip()
    try:
        if len(v) == 10:  # YYYY-MM-DD
            return datetime.strptime(v, "%Y-%m-%d")
        # naive ISO fallback (e.g., 2025-10-12T14:30:00Z or without Z)
        return datetime.fromisoformat(v.replace("Z", "+00:00")).replace(tzinfo=None)
    except Exception:
        raise ValueError("Invalid occurred_at; use YYYY-MM-DD or ISO 8601")


def _events_for_prompt(user_id: int, days: int | None = None, cap: int = 5) -> list[str]:
    """
    Fetch up to `cap` most recent life events.
    If `days` is None => no date cutoff (useful for long-ago events like childhood).
    """
    q = (LifeEvent.query
         .filter(LifeEvent.user_id == user_id)
         .order_by(LifeEvent.occurred_at.desc()))
    if days is not None:
        q = q.filter(LifeEvent.occurred_at >= datetime.utcnow() - timedelta(days=days))
    rows = q.limit(cap).all()
    # return [f"{r.occurred_at.date()}: {r.details}" for r in rows]
    return [f"{r.occurred_at.date()}: {r.title}" for r in rows]


def _build_user_payload(dream_prompt: str, user_id: int, dream_text: str) -> str:
    try:
        u = User.query.get(user_id)   # your User model
        intro = intro_line_for_prompt(u, include_gender=True, include_timezone=True) if u else None
    except Exception:
        logger.warning("user fetch/intro build failed", exc_info=True)
        intro = None

    try:
        ctx_items = _events_for_prompt(user_id)
    except Exception:
        logger.warning("life_event fetch failed", exc_info=True)
        ctx_items = []

    parts = [dream_prompt]
    if intro:
        parts.append("User:\n- " + intro)
    if ctx_items:
        parts.append("Context:\n" + "\n".join(f"- {x}" for x in ctx_items))
    parts.append("Dream:\n" + dream_text.strip())
    return "\n\n".join(parts)


def _strip_trailing_type_block(text: str) -> str:
    if not text:
        return text
    if "**Type:**" in text:
        return text.rsplit("**Type:**", 1)[0].rstrip()
    if "Type:" in text:
        return text.rsplit("Type:", 1)[0].rstrip()
    return text


# dream analysis
@app.route("/api/chat", methods=["POST"])
@login_required
def chat():
    logger.info(" /api/chat called")
    data = request.get_json()
    logger.debug(f"Received JSON: {data}")

    message = data.get("message")
    if not message:
        logger.debug("[WARN] Missing dream message.")
        return jsonify({"error": "Missing dream message."}), 400

    # Check if user is using a free plan, and update counts
    decremented_text = False
    is_pro = _user_is_pro(current_user.id)
    

    try:
        if not is_pro:
            ok, reset_iso = decrement_text_or_deny(current_user.id)
            if not ok:
                return jsonify({"error": "quota_exhausted", "kind": "text", "next_reset_iso": reset_iso}), 402
            decremented_text = True

        # 1) Save bare dream
        logger.info("Saving dream to database...")
        dream = Dream(
            user_id=current_user.id,
            text=message,
            created_at=datetime.utcnow()
        )
        db.session.add(dream)
        db.session.commit()
        logger.debug(f"Dream saved with ID: {dream.id}")
        
        q = "pro" if is_pro else "simple"
        
        # 2) Build prompt (adds recent life events if any)
        dream_prompt = CATEGORY_PROMPTS["dream"] if is_pro else CATEGORY_PROMPTS["dream_free"]
        prompt = _build_user_payload(dream_prompt, current_user.id, message)
        logger.info(f"Sending {q} prompt to OpenAI")
        logger.debug(f"Dream Analysis Prompt: {prompt}")

        response = call_openai_with_retry(prompt)
        if not getattr(response, "choices", None) or not response.choices[0].message:
            logger.error("[ERROR] AI response was empty.")
            return jsonify({"error": "AI response was empty"}), 500

        content = response.choices[0].message.content.strip()
        logger.debug(f"Dream Analysis Reply: {content}")


        # 3) Parse Analysis / Summary / Tone / Type
        analysis = summary = tone = None
        type_val = None
        is_question = is_nonsense = False
        
        # Accept bold (**X:**) or plain (X:)
        ANALYSIS_MARK = "**Analysis:**" if "**Analysis:**" in content else ("Analysis:" if "Analysis:" in content else None)
        SUMMARY_MARK  = "**Summary:**"  if "**Summary:**"  in content else ("Summary:"  if "Summary:"  in content else None)
        TONE_MARK     = "**Tone:**"     if "**Tone:**"     in content else ("Tone:"     if "Tone:"     in content else None)
        TYPE_MARK     = "**Type:**"     if "**Type:**"     in content else ("Type:"     if "Type:"     in content else None)
        
        # Positions (or -1 if missing)
        iA = content.find(ANALYSIS_MARK) if ANALYSIS_MARK else -1
        iS = content.find(SUMMARY_MARK)  if SUMMARY_MARK  else -1
        iT = content.find(TONE_MARK)     if TONE_MARK     else -1
        iY = content.find(TYPE_MARK)     if TYPE_MARK     else -1
        
        def slice_between(start_mark, start_idx, end_idx):
            if start_idx == -1 or not start_mark:
                return None
            start = start_idx + len(start_mark)
            end   = len(content) if end_idx == -1 else end_idx
            return content[start:end].strip()
        
        # 1) Analysis = between Analysis and Summary
        analysis = slice_between(ANALYSIS_MARK, iA, iS)
        
        # 2) Summary = between Summary and Tone (if Tone exists) else up to Type else to end
        summary_end_idx = iT if iT != -1 else (iY if iY != -1 else -1)
        summary = slice_between(SUMMARY_MARK, iS, summary_end_idx)
        
        # 3) Tone = between Tone and Type (if Type exists) else to end; keep only first line
        tone_block = slice_between(TONE_MARK, iT, iY)
        tone = tone_block.splitlines()[0].strip().rstrip(string.punctuation) if tone_block else None
        
        # 4) Type = whatever comes after Type marker (used for routing, not rendered)
        type_val = slice_between(TYPE_MARK, iY, -1)
        tv = (type_val or "").strip().lower()
        is_question = tv.startswith("question")
        is_nonsense = tv.startswith("decline")
        
        # 5) Fallbacks:
        # If no Analysis/Summary/Tone were found at all, show the model text minus any 'Type:' lines
        if not any([analysis, summary, tone]):
            content_without_type = "\n".join(
                ln for ln in content.splitlines()
                if not ln.strip().lower().startswith(("**type:**", "type:"))
            ).strip()
            analysis = content_without_type or content


        logger.debug(f"[parsed] is_question={is_question} is_nonsense={is_nonsense} tone={tone} summary_present={bool(summary)}")

        # --- Decline (non-dream / unrelated) ---
        if is_nonsense:
            # Use whatever we parsed; if parsing missed, fall back to whole content
            # but strip trailing "Type:" so the user never sees it.
            def _strip_trailing_type_block(text: str) -> str:
                if not text: 
                    return text
                if "**Type:**" in text:
                    return text.rsplit("**Type:**", 1)[0].rstrip()
                if "Type:" in text:
                    return text.rsplit("Type:", 1)[0].rstrip()
                return text
        
            user_analysis = analysis or content
            user_analysis = _strip_trailing_type_block(user_analysis)
        
            # Keep the row (don’t delete), hide it by default, and save the AI reply.
            dream.analysis = user_analysis
            dream.summary  = summary or "Non-dream entry"
            dream.tone     = None
            dream.is_question = False
            dream.hidden   = True
            dream.image_file = "placeholders/decline.png"  # neutral icon so FE has a thumbnail
            db.session.commit()
        
            # Return the same shape the FE expects
            return jsonify({
                "dream_id": dream.id,
                "analysis": dream.analysis,
                "tone": dream.tone,
                "is_question": False,
                "should_generate_image": False,
            }), 200

        
        # Question → keep, but no image
        if is_question:
            dream.analysis = analysis
            dream.summary  = summary
            dream.tone     = None
            dream.is_question = True
            dream.image_file = f"placeholders/question2.png" 
            db.session.commit()
            return jsonify({
                "dream_id": dream.id,
                "analysis": dream.analysis,
                "tone": dream.tone,
                "is_question": True,                # <-- give the client a real flag
                "should_generate_image": False,     # <-- authoritative “don’t start”
            }), 200
        
        # Dream → keep + image
        dream.analysis = analysis
        dream.summary  = summary
        dream.tone     = tone
        dream.is_question = False
        db.session.commit()
        
        # only dreams are allowed to enqueue image
        # enqueue_image(dream.id)

        return jsonify({
            "dream_id": dream.id,
            "analysis": dream.analysis,
            "tone": dream.tone,
            "is_question": False,
            "should_generate_image": _can_generate_image(current_user.id),          # <-- check if user is "pro", or "free + has credits"
        }), 200
      
    except Exception as e:
        db.session.rollback()
        if decremented_text and not is_pro:
            refund_text(current_user.id)
        logger.error("Exception during dream processing", exc_info=True)
        return jsonify({"error": "internal error"}), 500


# Create a life event
@app.post("/api/life-events")
@login_required
def create_life_event():
    data = request.get_json(force=True) or {}
    title = (data.get("title") or "").strip()
    if not title:
        return jsonify({"error": "title is required"}), 400
    if len(title) > 120:
        return jsonify({"error": "title too long (max 120)"}), 400

    try:
        occurred_at = _parse_iso_dt(data.get("occurred_at") or "")
    except ValueError as e:
        return jsonify({"error": str(e)}), 400

    ev = LifeEvent(
        user_id=current_user.id,
        title=title,
        occurred_at=occurred_at,
        details=(data.get("details") or None),
        tags=(data.get("tags") or None),  # list or None; OK with JSON column
    )
    db.session.add(ev)
    db.session.commit()

    return jsonify({
        "id": ev.id,
        "title": ev.title,
        "occurred_at": ev.occurred_at.isoformat() + "Z",
        "details": ev.details,
        "tags": ev.tags,
        "created_at": ev.created_at.isoformat() + "Z",
    }), 201


# Update a life event
@app.patch("/api/life-events/<int:event_id>")
@login_required
def update_life_event(event_id):
    ev = LifeEvent.query.filter_by(id=event_id, user_id=current_user.id).first()
    if not ev:
        return jsonify({"error": "not found"}), 404

    data = request.get_json(force=True) or {}

    if "title" in data:
        title = (data.get("title") or "").strip()
        if not title:
            return jsonify({"error": "title cannot be empty"}), 400
        if len(title) > 120:
            return jsonify({"error": "title too long (max 120)"}), 400
        ev.title = title

    if "occurred_at" in data and data.get("occurred_at"):
        try:
            ev.occurred_at = _parse_iso_dt(data["occurred_at"])
        except ValueError as e:
            return jsonify({"error": str(e)}), 400

    if "details" in data:
        ev.details = (data.get("details") or None)

    if "tags" in data:
        ev.tags = (data.get("tags") or None)

    db.session.commit()

    return jsonify({
        "id": ev.id,
        "title": ev.title,
        "occurred_at": ev.occurred_at.isoformat() + "Z",
        "details": ev.details,
        "tags": ev.tags,
        "created_at": ev.created_at.isoformat() + "Z",
    })


# Delete life event
@app.delete("/api/life-events/<int:event_id>")
@login_required
def delete_life_event(event_id):
    ev = LifeEvent.query.filter_by(id=event_id, user_id=current_user.id).first()
    if not ev:
        return jsonify({"error": "not found"}), 404
    db.session.delete(ev)
    db.session.commit()
    return jsonify({"ok": True})


# Fetch all life events for the UI/Editor
@app.get("/api/life-events")
@login_required
def list_life_events():
    page = max(int(request.args.get("page", 1)), 1)
    per_page = min(max(int(request.args.get("per_page", 20)), 1), 100)

    since = request.args.get("since")  # optional
    until = request.args.get("until")  # optional

    q = LifeEvent.query.filter(LifeEvent.user_id == current_user.id)
    if since:
        try:
            q = q.filter(LifeEvent.occurred_at >= _parse_iso_dt(since))
        except ValueError as e:
            return jsonify({"error": str(e)}), 400
    if until:
        try:
            q = q.filter(LifeEvent.occurred_at <= _parse_iso_dt(until))
        except ValueError as e:
            return jsonify({"error": str(e)}), 400

    q = q.order_by(desc(LifeEvent.occurred_at), desc(LifeEvent.id))
    items = q.limit(per_page).offset((page - 1) * per_page).all()

    return jsonify({
        "page": page,
        "per_page": per_page,
        "items": [{
            "id": r.id,
            "title": r.title,
            "occurred_at": r.occurred_at.isoformat() + "Z",
            "details": r.details,
            "tags": r.tags,
            "created_at": r.created_at.isoformat() + "Z",
        } for r in items]
    })
  
# Tiny endpoint to fetch recent events (for the picker)
# GET /api/life-events/recent?days=90&limit=10
@app.get("/api/life-events/recent")
@login_required
def recent_life_events():
    days = int(request.args.get("days", 90))
    limit = int(request.args.get("limit", 10))
    rows = (LifeEvent.query
            .filter(LifeEvent.user_id == current_user.id,
                    LifeEvent.occurred_at >= datetime.utcnow() - timedelta(days=days))
            .order_by(LifeEvent.occurred_at.desc())
            .limit(limit).all())
    return jsonify([{
        "id": r.id,
        "title": r.title,
        "occurred_at": r.occurred_at.isoformat() + "Z"
    } for r in rows])



# used to generate smaller images for journal and tiles
def generate_resized_image(input_path, output_path, size=(48, 48)):
    try:
        with Image.open(input_path) as img:
            img.thumbnail(size)
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            img.save(output_path, "PNG")
            logger.info(f"Resized image saved to {output_path}")
    except Exception as e:
        logger.error(f"[ERROR] Failed to create resized image ({size}): {e}")


@app.post("/api/image_generate")
@login_required
def generate_dream_image():
    is_pro = _user_is_pro(current_user.id)

    # Free user: gate before any work
    decremented_image = False
    if not is_pro:
        ok = decrement_image_or_deny(current_user.id)
        if not ok:
            return jsonify({"error": "quota_exhausted", "kind": "image"}), 402
        decremented_image = True

    # was unable to get usable images from "low" quality engine, so skipping completely.
    # q = "high" if is_pro else "low" 
    q = "high"
    
    logger.info(" /api/image_generate called")
    data = request.get_json()
    dream_id = data.get("dream_id")

    # 1) Input guard
    if not dream_id:
        logger.debug("[WARN] Missing dream ID.")
        return jsonify({"error": "Missing dream ID."}), 400

    # 2) Lookup + auth (keep separate => correct 404 semantics)
    dream = Dream.query.get(dream_id)
    if dream is None or dream.user_id != current_user.id:
        return jsonify({"error": "Dream not found or unauthorized"}), 404

    # 3) Skip conditions (no need to check "not dream" again)
    # if dream.hidden or dream.is_question or not dream.summary or not dream.tone:
    if dream.hidden or dream.is_question:
        return jsonify({
            "skipped": True,
            "image_file": dream.image_file  # no need for getattr; dream exists
        }), 200

    message = dream.text
    tone = dream.tone

    try:
        logger.info(f"Converting dream to {q} quality image prompt...")
        image_prompt = convert_dream_to_image_prompt(message, tone, q)
        logger.info("Sending image generation request...")

        # Supported values are: 'gpt-image-1', 'gpt-image-1-mini', 'gpt-image-0721-mini-alpha', 'dall-e-2', and 'dall-e-3'
        # model = "dall-e-2" if q == "low" else "dall-e-3"
        # size  = "512x512"  if q == "low" else "1024x1024"
            
        image_response = client.images.generate(
            model="dall-e-3",
            prompt=image_prompt,
            n=1,
            size="1024x1024",
            response_format="url"
        )
        image_url = image_response.data[0].url
        logger.info(f"Image URL received: {image_url}")

        filename = f"{uuid.uuid4().hex}.png"
        image_path = os.path.join("static", "images", "dreams", filename)
        tile_path = os.path.join("static", "images", "tiles", filename)
        os.makedirs(os.path.dirname(image_path), exist_ok=True)

        # Fetch and save the image with a timeout
        img_response = requests.get(image_url, timeout=30)
        img_response.raise_for_status()

        with open(image_path, "wb") as f:
            f.write(img_response.content)
        logger.info(f"Image saved to {image_path}")
        
        # image_response = client.images.generate(
        #     model="gpt-image-1",
        #     prompt=image_prompt,
        #     n=1,
        #     size="1024x1024",
        # )
        # b64 = image_response.data[0].b64_json
        # img_bytes = base64.b64decode(b64)
        # logger.info(f"Image data received")

        # filename = f"{uuid.uuid4().hex}.png"
        # image_path = os.path.join("static", "images", "dreams", filename)
        # tile_path = os.path.join("static", "images", "tiles", filename)
        # os.makedirs(os.path.dirname(image_path), exist_ok=True)

        # with open(image_path, "wb") as f:
        #     f.write(img_bytes)
        # logger.info(f"Image saved to {image_path}")

        generate_resized_image(image_path, tile_path, size=(256, 256))

        # Update DB
        dream.image_file = filename
        dream.image_prompt = image_prompt
        db.session.commit()
        logger.info("Dream successfully updated with image.")

        logger.info("Returning image response to frontend")
        return jsonify({
            # "analysis": dream.analysis,
            "image": f"/static/images/dreams/{dream.image_file}"
        })

    except openai.OpenAIError as e:
        db.session.rollback()
        if decremented_image:
            refund_image(current_user.id)
        logger.error("...", exc_info=True)
        return jsonify({"error": "OpenAI image generation failed"}), 502
    except requests.RequestException as e:
        db.session.rollback()
        if decremented_image:
            refund_image(current_user.id)
        logger.error("...", exc_info=True)
        return jsonify({"error": "Failed to fetch image"}), 504
    except Exception:
        db.session.rollback()
        if decremented_image:
            refund_image(current_user.id)
        logger.exception("Unexpected error during image generation")
        return jsonify({"error": "Image generation failed"}), 500

    # except openai.OpenAIError as e:
    #     logger.error(f"[ERROR] OpenAI image generation failed: {e}")
    #     return jsonify({"error": "OpenAI image generation failed"}), 502

    # except requests.RequestException as e:
    #     logger.error(f"[ERROR] Failed to fetch image from URL: {e}")
    #     return jsonify({"error": "Failed to fetch image"}), 504

    # except Exception as img_error:
    #     logger.exception("Unexpected error during image generation")
    #     return jsonify({"error": "Image generation failed"}), 500

    # finally:
    #     db.session.rollback()  # Only triggers on unhandled exception


# all dreams need to be displayed in the manage page
@app.route("/api/alldreams", methods=["GET"])
@login_required
def get_alldreams():
    user_tz = ZoneInfo(current_user.timezone or "UTC") 

    dreams = Dream.query.filter(Dream.user_id == current_user.id).order_by(Dream.created_at.desc()).all()
    
    def convert_created_at(dt):
        try:
            print(f"Original datetime: {dt} (tzinfo={dt.tzinfo})")
            return dt.replace(tzinfo=timezone.utc).astimezone(user_tz).isoformat()
        except Exception as e:
            print(f"[ERROR] Timestamp conversion failed: {e}")
            traceback.print_exc()
            return None

    return jsonify([
        {
            "id": d.id,
            "summary": d.summary,
            "text": d.text,
            "analysis": d.analysis,
            "hidden": d.hidden,
            "tone": d.tone,
            "image_file": f"/static/images/dreams/{d.image_file}" if d.image_file else None,
            "image_tile": f"/static/images/tiles/{d.image_file}" if d.image_file else None,
            "created_at": convert_created_at(d.created_at) if d.created_at else None
        } for d in dreams
    ])

# fetch gallery images
@app.route("/api/gallery", methods=["GET"])
@login_required
def get_gallery():
    user_tz = ZoneInfo(current_user.timezone or "UTC")

    # dreams = Dream.query.filter(
    #     Dream.user_id == current_user.id,
    #     or_(Dream.hidden == False, Dream.hidden.is_(None))
    # ).order_by(Dream.created_at.desc()).all()

    dreams = (
        Dream.query
        .filter(
            Dream.user_id == current_user.id,
            or_(Dream.hidden == False, Dream.hidden.is_(None)),

            # has an image filename
            Dream.image_file.isnot(None),
            func.length(func.trim(Dream.image_file)) > 0,

            # EXCLUDE placeholders (matches 'placeholder' or 'placeholders')
            ~func.lower(Dream.image_file).like("%placehold%"),

            # EXCLUDE AI questions
            or_(Dream.is_question == False, Dream.is_question.is_(None)),
        )
        .order_by(Dream.created_at.desc())
        .all()
    )

    def convert_created_at(dt):
        try:
            print(f"Original datetime: {dt} (tzinfo={dt.tzinfo})")
            return dt.replace(tzinfo=timezone.utc).astimezone(user_tz).isoformat()
        except Exception as e:
            print(f"[ERROR] Timestamp conversion failed: {e}")
            traceback.print_exc()
            return None

    return jsonify([
        {
            "id": d.id,
            "summary": d.summary,
            "text": d.text,
            "analysis": d.analysis,
            "tone": d.tone,
            "image_file": f"/static/images/dreams/{d.image_file}" if d.image_file else None,
            "image_tile": f"/static/images/tiles/{d.image_file}" if d.image_file else None,
            "created_at": convert_created_at(d.created_at) if d.created_at else None,
            "notes": d.notes
        } for d in dreams
    ])

    
# fetch dreams
@app.route("/api/dreams", methods=["GET"])
@login_required
def get_dreams():
    user_tz = ZoneInfo(current_user.timezone or "UTC") 

    dreams = Dream.query.filter(
        Dream.user_id == current_user.id,
        or_(Dream.hidden == False, Dream.hidden.is_(None))
    ).order_by(Dream.created_at.desc()).all()
    
    def convert_created_at(dt):
        try:
            print(f"Original datetime: {dt} (tzinfo={dt.tzinfo})")
            return dt.replace(tzinfo=timezone.utc).astimezone(user_tz).isoformat()
        except Exception as e:
            print(f"[ERROR] Timestamp conversion failed: {e}")
            traceback.print_exc()
            return None

    return jsonify([
        {
            "id": d.id,
            "summary": d.summary,
            "text": d.text,
            "analysis": d.analysis,
            "tone": d.tone,
            "image_file": f"/static/images/dreams/{d.image_file}" if d.image_file else None,
            "image_tile": f"/static/images/tiles/{d.image_file}" if d.image_file else None,
            "created_at": convert_created_at(d.created_at) if d.created_at else None,
            "notes": d.notes
        } for d in dreams
    ])

# For deleting dreams, and moving the images
@app.route("/api/dreams/<int:dream_id>", methods=["DELETE"])
@login_required
def delete_dream(dream_id):
    dream = Dream.query.get_or_404(dream_id)
    if dream.user_id != current_user.id:
        return jsonify({"error": "Unauthorized"}), 403

    # Move image files to archive folder
    if dream.image_file:
        try:
            image_path = os.path.join("static", "images", "dreams", dream.image_file)
            tile_path = os.path.join("static", "images", "tiles", dream.image_file)
            archive_dir = os.path.join("static", "images", "deleted")

            os.makedirs(archive_dir, exist_ok=True)

            for path in [image_path, tile_path]:
                if os.path.exists(path):
                    shutil.move(path, os.path.join(archive_dir, os.path.basename(path)))

        except Exception as e:
            print(f"[WARN] Failed to archive image: {e}")

    db.session.delete(dream)
    db.session.commit()
    return '', 204

@app.route("/api/dreams/<int:dream_id>/toggle-hidden", methods=["POST"])
@login_required
def toggle_hidden_dream(dream_id):
    dream = Dream.query.get_or_404(dream_id)
    if dream.user_id != current_user.id:
        return jsonify({"error": "Unauthorized"}), 403
    dream.hidden = not dream.hidden
    db.session.commit()
    return jsonify({"hidden": dream.hidden})


# --- for notes ---
@app.patch("/api/dreams/<int:dream_id>/notes")
@login_required
def patch_dream_notes(dream_id):
    """
    Update/clear personal notes on a dream.
    - Never logs note content.
    - 8k hard cap.
    - Optional optimistic concurrency via last_seen_notes_updated_at.
    """
    # Lookup + ownership guard; return 404 on missing OR not-owned
    dream = Dream.query.get(dream_id)
    if dream is None or dream.user_id != current_user.id:
        return jsonify({"error": "not found"}), 404

    data = request.get_json(silent=True) or {}

    # Validate 'notes'
    if "notes" not in data:
        return jsonify({"error": "invalid_request", "message": "Field 'notes' is required"}), 422
    notes = data.get("notes")
    if notes is not None and not isinstance(notes, str):
        return jsonify({"error": "invalid_request", "message": "Field 'notes' must be string or null"}), 422
    if isinstance(notes, str) and len(notes) > NOTES_MAX_LEN:
        return jsonify({"error": "too_large", "message": f"Notes exceed {NOTES_MAX_LEN} characters."}), 413

    last_seen = data.get("last_seen_notes_updated_at")

    # Conflict?
    if _notes_conflict(dream, last_seen):
        # DO NOT log content; include current server state only
        logger.info("notes_update_conflict user_id=%s dream_id=%s", current_user.id, dream.id)
        return jsonify({
            "error": "conflict",
            "message": "Notes were updated elsewhere.",
            "current": {
                "notes": dream.notes,
                "notes_updated_at": _iso_utc(dream.notes_updated_at)
            }
        }), 409

    # Normalize & short-circuit if unchanged (trim compare)
    incoming = (notes or "").strip() or None
    if (dream.notes or "").strip() == (incoming or ""):
        # return 200 with current object for simplicity/consistency
        return jsonify({
            "id": dream.id,
            "notes": dream.notes,
            "notes_updated_at": _iso_utc(dream.notes_updated_at)
        }), 200

    # Apply update (set_notes already bumps notes_updated_at)
    dream.set_notes(incoming)
    db.session.commit()

    # Log IDs only—never the text
    logger.info("notes_updated user_id=%s dream_id=%s", current_user.id, dream.id)

    return jsonify({
        "id": dream.id,
        "notes": dream.notes,
        "notes_updated_at": _iso_utc(dream.notes_updated_at)
    }), 200


# --- reanalyze the dream with notes included scaffold (policy OFF by default) ---
@app.post("/api/dreams/<int:dream_id>/reanalyze")
@login_required
def reanalyze_dream(dream_id):
    """
    Trigger a re-analysis. Notes inclusion is disabled by policy for now,
    but we return explicit policy metadata so we can flip it later.
    """
    dream = Dream.query.get(dream_id)
    if dream is None or dream.user_id != current_user.id:
        return jsonify({"error": "not found"}), 404

    data = request.get_json(silent=True) or {}
    include_notes_req = (data.get("include_notes") or "auto").lower()
    if include_notes_req not in ("never", "auto", "always"):
        return jsonify({"error": "invalid_request", "message": "include_notes must be 'never'|'auto'|'always'"}), 422

    # Resolver (OFF today)
    included_notes = False
    reason = "disabled_by_policy"  # future: "no_consent"|"per_dream_block"|"ok"

    # If you later enable, gate on NOTES_AI_ENABLED && REANALYZE_WITH_NOTES_ALLOWED
    # and user/dream consents before setting included_notes=True.

    # If you later queue jobs, put a job_id here; keeping sync for now.
    return jsonify({
        "included_notes": included_notes,
        "notes_policy_version": NOTES_POLICY_VERSION,
        "notes_policy_reason": reason
    }), 200

# get notes
@app.get("/api/dreams/<int:dream_id>/notes")
@login_required
def get_dream_notes(dream_id):
    dream = Dream.query.get(dream_id)
    if dream is None or dream.user_id != current_user.id:
        return jsonify({"error": "not found"}), 404
    # Never log content
    logger.info("notes_read user_id=%s dream_id=%s", current_user.id, dream.id)
    def _iso_utc(dt):
        from datetime import timezone
        return dt.replace(tzinfo=timezone.utc).isoformat().replace("+00:00","Z") if dt else None
    return jsonify({
        "id": dream.id,
        "notes": dream.notes,
        "notes_updated_at": _iso_utc(dream.notes_updated_at),
    })



@app.route("/api/check_auth", methods=["GET"])
def check_auth():
    if current_user.is_authenticated:
        return jsonify({
            "authenticated": True,
            "first_name": current_user.first_name,
            "enable_audio": current_user.enable_audio,
            # "email": current_user.email
        })
    return jsonify({"authenticated": False}), 401




# --- Subscription API Endpoints ---
@app.route("/api/subscription/status", methods=["GET"])
@login_required
def get_subscription_status():
    """Get the current subscription status for the logged-in user"""
    try:
        status = SubscriptionService.get_user_subscription_status(current_user.id)

        # If not subscribed, attach counters
        tier = (status.get("tier") or "").lower()
        if status.get("is_active") and (tier.startswith("pro") or tier.startswith("trial")):
            return jsonify(status)
        
        uc = ensure_week_current(current_user.id)
        status.update({
            "text_remaining_week": uc.text_remaining_week,
            "image_remaining_lifetime": uc.image_remaining_lifetime,
            "next_reset_iso": next_reset_iso(current_user.id),
        })
        return jsonify(status)
    except Exception as e:
        logger.error(f"Error fetching subscription status: {e}", exc_info=True)
        return jsonify({"error": "Failed to fetch subscription status"}), 500

@app.route("/api/subscription/plans", methods=["GET"])
@login_required
def get_subscription_plans():
    """Get all available subscription plans"""
    try:
        plans = SubscriptionService.get_subscription_plans()
        return jsonify(plans)
    except Exception as e:
        logger.error(f"Error fetching subscription plans: {e}", exc_info=True)
        return jsonify({"error": "Failed to fetch subscription plans"}), 500

@app.route("/api/subscription/purchase", methods=["POST"])
@login_required
def purchase_subscription():
    """Initiate a subscription purchase

    NOTE: The mobile app may send either the internal plan id (e.g. "pro_monthly")
    or the store product id (e.g. "dreamr_pro_monthly"). To be robust, accept
    both by resolving via primary key *or* SubscriptionPlan.product_id.
    """
    data = request.get_json(silent=True) or {}
    raw_plan = data.get("plan_id")

    if not raw_plan:
        return jsonify({"error": "plan_id is required"}), 400

    # Allow lookup by primary key OR by product_id used in the stores
    plan = SubscriptionPlan.query.get(raw_plan)
    if not plan:
        plan = SubscriptionPlan.query.filter_by(product_id=raw_plan).first()
    if not plan:
        return jsonify({"error": f"Plan {raw_plan} not found"}), 404

    try:
        # Determine payment provider
        payment_provider = data.get("payment_provider")
        receipt_data = data.get("receipt_data")

        # Initiate subscription (pass the canonical plan id)
        result = SubscriptionService.initiate_subscription(
            user_id=current_user.id,
            plan_id=plan.id,
            payment_provider=payment_provider,
            receipt_data=receipt_data,
        )

        return jsonify(result)
    except ValueError as e:
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        logger.error(f"Error initiating subscription: {e}", exc_info=True)
        return jsonify({"error": "Failed to initiate subscription"}), 500

@app.route("/api/subscription/cancel", methods=["POST"])
@login_required
def cancel_subscription():
    """Cancel the current subscription"""
    try:
        success = SubscriptionService.cancel_subscription(current_user.id)
        return jsonify({"success": success})
    except Exception as e:
        logger.error(f"Error canceling subscription: {e}", exc_info=True)
        return jsonify({"error": "Failed to cancel subscription"}), 500

@app.route("/api/subscription/payment-method", methods=["POST"])
@login_required
def update_payment_method():
    """Update the payment method for the current subscription"""
    data = request.get_json(silent=True) or {}
    
    try:
        success = SubscriptionService.update_payment_method(current_user.id, data)
        return jsonify({"success": success})
    except Exception as e:
        logger.error(f"Error updating payment method: {e}", exc_info=True)
        return jsonify({"error": "Failed to update payment method"}), 500

# added by AZAD, not used
@app.route("/api/admin/subscription/force_set", methods=["POST"])
@admin_required
def admin_force_set_subscription():
    """Admin-only endpoint to manually create or repair a user's subscription.

    Useful when the store reports an active subscription but the local DB is
    out of sync and requires repairing a single user record.
    """
    data = request.get_json(silent=True) or {}
    user_id = data.get("user_id")
    plan_id = data.get("plan_id")
    months = data.get("months")
    years = data.get("years")

    if not user_id or not plan_id:
        return jsonify({"error": "user_id and plan_id are required"}), 400

    try:
        sub = SubscriptionService.upsert_manual_subscription(
            user_id=int(user_id),
            plan_id=str(plan_id),
            months=months,
            years=years,
            payment_provider="admin-force",
        )
        return jsonify({
            "success": True,
            "subscription": {
                "id": sub.id,
                "user_id": sub.user_id,
                "plan_id": sub.plan_id,
                "status": sub.status,
                "start_date": sub.start_date.isoformat(),
                "end_date": sub.end_date.isoformat() if sub.end_date else None,
            },
        })
    except Exception as e:
        logger.error("admin_force_set_subscription error: %s", e, exc_info=True)
        return jsonify({"error": str(e)}), 500
    
# --- Optional: Webhook Handlers for App Store and Google Play ---
@app.route("/api/webhooks/apple-iap", methods=["POST"])
def apple_iap_webhook():
    """
    Handle Apple App Store Server Notifications
    
    This endpoint receives server-to-server notifications from Apple
    about subscription events (renewals, cancellations, etc.)
    """
    data = request.get_json(silent=True) or {}
    logger.info(f"Received Apple IAP webhook: {data}")
    
    # Process the notification (implementation depends on your business logic)
    # ...
    
    return jsonify({"status": "received"}), 200

@app.route("/api/webhooks/google-play", methods=["POST"])
def google_play_webhook():
    """
    Handle Google Play Developer API Notifications
    
    This endpoint receives server-to-server notifications from Google
    about subscription events (renewals, cancellations, etc.)
    """
    data = request.get_json(silent=True) or {}
    logger.info(f"Received Google Play webhook: {data}")
    
    # Process the notification (implementation depends on your business logic)
    # ...
    
    return jsonify({"status": "received"}), 200


# =========================
# Admin blueprint (HTML)
# =========================
# admin_bp = Blueprint("admin", __name__, url_prefix="/admin") breaks app

# Minimal inline templates to avoid files
ADMIN_SHELL = """<!doctype html><meta charset="utf-8">
<title>{{ title or 'Admin' }}</title>
<style>
  /* page width */
  :root { --page-width: 1400px; }               /* make larger if you want */
  html,body{height:100%;margin:0;padding:0}
  *{box-sizing:border-box}
  body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu;color:#151515;background:#fff}
  .wrap{width:min(96vw, var(--page-width)); margin:20px auto; padding:0 8px;}

  a{color:#0a58ca;text-decoration:none}
  .msg{padding:6px 10px;border-radius:8px;background:#eef;display:inline-block}
  nav a{margin-right:12px}
  hr{border:0;border-top:1px solid #ddd;margin:12px 0}

  table{border-collapse:collapse;width:100%;margin:10px 0; table-layout:auto}
  th,td{border:1px solid #ddd;padding:8px;vertical-align:top}
  th{background:#f4f4f4}
</style>

<div class="wrap">
  <h1>Dreamr Admin</h1>
  <nav>
    <a href="/admin/">Dashboard</a>
    <a href="/admin/users">Users</a>
    <a href="/admin/logout" onclick="event.preventDefault();document.getElementById('al').submit()">Logout</a>
  </nav>
  <hr>
  {{ body|safe }}
  <form id="al" method="post" action="/admin/logout"></form>
</div>
"""


def _render_admin(body_tpl: str, title: str, **ctx):
    body = render_template_string(body_tpl, **ctx)
    return render_template_string(ADMIN_SHELL, title=title, body=body)

# --- Admin login form (HTML) reusing your User + bcrypt + Flask-Login ---
# ----- Admin HTML login -----
@app.get("/admin/login")
def admin_login_form():
    if current_user.is_authenticated and is_admin_user():
        return redirect("/admin/")
    return """
    <form method='post' action='/admin/login' style='max-width:340px;margin:60px auto;font-family:system-ui'>
      <h3>Admin login</h3>
      <input name='email' placeholder='Email' style='width:100%;padding:8px;margin:6px 0'>
      <input name='password' type='password' placeholder='Password' style='width:100%;padding:8px;margin:6px 0'>
      <button type='submit' style='padding:8px 12px'>Sign in</button>
      <p style='font-size:12px;color:#666'>Email must match ADMIN_EMAILS</p>
    </form>
    """

@app.post("/admin/login")
def admin_login_submit():
    email = (request.form.get("email") or "").strip().lower()
    password = request.form.get("password") or ""
    u = User.query.filter_by(email=email).first()
    if not u or not u.password:
        return "Invalid credentials", 401
    ok = False
    try:
        ok = bcrypt.checkpw(password.encode("utf-8"), u.password.encode("utf-8"))
    except Exception:
        ok = False
    if not ok:
        return "Invalid credentials", 401
    login_user(u, remember=True, duration=timedelta(days=90))
    return redirect("/admin/")

@app.post("/admin/logout")
@login_required
def admin_logout():
    logout_user()
    return redirect("/admin/login")

# ----- Admin pages -----
@app.get("/admin/")
@admin_required
def admin_dashboard():
    total_users = db.session.query(func.count(User.id)).scalar()
    total_dreams = db.session.query(func.count(Dream.id)).scalar()
    active_subs = (db.session.query(func.count(UserSubscription.id))
                   .filter(UserSubscription.status.in_(["active","trial"])).scalar())
    pending = db.session.query(func.count(PendingUser.uuid)).scalar()
    recent_payments = (db.session.query(PaymentTransaction)
                       .order_by(desc(PaymentTransaction.created_at)).limit(10).all())
    BODY = """
    <h2>Dashboard</h2>
    <div class="msg">Total users: <b>{{ total_users }}</b></div>
    <div class="msg">Total dreams: <b>{{ total_dreams }}</b></div>
    <div class="msg">Active/trial subs: <b>{{ active_subs }}</b></div>
    <div class="msg">Pending signups: <b>{{ pending }}</b></div>
    <h3>Recent payments</h3>
    <table>
      <tr><th>ID</th><th>User</th><th>Amount</th><th>Status</th><th>Provider</th><th>When</th></tr>
      {% for p in recent_payments %}
      <tr>
        <td>{{ p.id }}</td>
        <td><a href="{{ url_for('admin_user_detail', user_id=p.user_id) }}">#{{ p.user_id }}</a></td>
        <td>{{ '%.2f'|format(p.amount) }} {{ p.currency }}</td>
        <td>{{ p.status }}</td>
        <td>{{ p.provider }}</td>
        <td>{{ p.created_at }}</td>
      </tr>
      {% endfor %}
    </table>
    """
    return _render_admin(BODY, "Dashboard",
                         total_users=total_users, total_dreams=total_dreams,
                         active_subs=active_subs, pending=pending,
                         recent_payments=recent_payments)

@app.get("/admin/users")
@admin_required
def admin_users_list():
    try: page = max(1, int(request.args.get("page", 1)))
    except: page = 1
    try: per_page = min(200, max(1, int(request.args.get("per_page", 50))))
    except: per_page = 50
    q = (request.args.get("q") or "").strip()
    sort = request.args.get("sort", "-signup")

    qry = User.query
    if q:
        like = f"%{q}%"
        qry = qry.filter(or_(User.email.ilike(like), User.first_name.ilike(like)))

    if sort == "email":
        qry = qry.order_by(User.email.asc())
    elif sort == "name":
        qry = qry.order_by(User.first_name.asc(), User.email.asc())
    else:
        qry = qry.order_by(User.signup_date.is_(None), User.signup_date.desc())

    rows = qry.limit(per_page + 1).offset((page - 1) * per_page).all()
    has_more = len(rows) > per_page
    users = rows[:per_page]

    subq = (db.session.query(UserSubscription.user_id,
                             func.max(UserSubscription.created_at).label("mx"))
            .group_by(UserSubscription.user_id).subquery())
    latest_subs = {
        s.user_id: s for s in db.session.query(UserSubscription)
        .join(subq, (UserSubscription.user_id == subq.c.user_id) & (UserSubscription.created_at == subq.c.mx))
        .all()
    }
    credits_map = {c.user_id: c for c in UserCredits.query.filter(UserCredits.user_id.in_([u.id for u in users])).all()}

    BODY = """
    <h2>Users</h2>
    <form method="get">
      <input name="q" value="{{ q or '' }}" placeholder="search email or name">
      <select name="sort">
        <option value="-signup" {% if sort=='-signup' %}selected{% endif %}>Newest</option>
        <option value="email" {% if sort=='email' %}selected{% endif %}>Email</option>
        <option value="name" {% if sort=='name' %}selected{% endif %}>Name</option>
      </select>
      <button type="submit">Search</button>
    </form>
    <table>
      <tr><th>ID</th><th>Email</th><th>Name</th><th>Signup</th><th>Plan</th><th>Status</th><th>Text/wk</th><th>Images</th></tr>
      {% for u in users %}
        {% set s = latest_subs.get(u.id) %}
        {% set c = credits_map.get(u.id) %}
        <tr>
          <td><a href="{{ url_for('admin_user_detail', user_id=u.id) }}">{{ u.id }}</a></td>
          <td>{{ u.email }}</td>
          <td>{{ u.first_name or '' }}</td>
          <td>{{ u.signup_date or '' }}</td>
          <td>{{ s.plan_id if s else '' }}</td>
          <td>{{ s.status if s else '' }}</td>
          <td>{{ c.text_remaining_week if c else 0 }}</td>
          <td>{{ c.image_remaining_lifetime if c else 0 }}</td>
        </tr>
      {% endfor %}
    </table>
    <div>
      {% if page>1 %}<a href="?page={{ page-1 }}&per_page={{ per_page }}&q={{ q }}&sort={{ sort }}">Prev</a>{% endif %}
      <span>Page {{ page }}</span>
      {% if has_more %}<a href="?page={{ page+1 }}&per_page={{ per_page }}&q={{ q }}&sort={{ sort }}">Next</a>{% endif %}
    </div>
    """
    return _render_admin(BODY, "Users",
                         users=users, latest_subs=latest_subs, credits_map=credits_map,
                         page=page, per_page=per_page, q=q, sort=sort, has_more=has_more)

@app.get("/admin/users/<int:user_id>")
@admin_required
def admin_user_detail(user_id: int):
    u = User.query.get_or_404(user_id)
    subs = (UserSubscription.query.filter_by(user_id=u.id)
            .order_by(UserSubscription.created_at.desc()).all())
    credits = UserCredits.query.get(u.id)
    dreams = (Dream.query.filter_by(user_id=u.id)
              .order_by(Dream.created_at.desc()).limit(50).all())
    payments = (PaymentTransaction.query.filter_by(user_id=u.id)
                .order_by(PaymentTransaction.created_at.desc()).all())
    plans = (SubscriptionPlan.query
         .order_by(SubscriptionPlan.period.asc(), SubscriptionPlan.price.asc())
         .all())
    current_sub = (
        UserSubscription.query
        .filter(UserSubscription.user_id == u.id,
                UserSubscription.status.in_(["active", "trial"]))
        .order_by(
            UserSubscription.end_date.is_(None),     # non-nulls first
            UserSubscription.end_date.desc(),
            UserSubscription.start_date.desc(),
        )
        .first()
    ) or (
        UserSubscription.query
        .filter(UserSubscription.user_id == u.id)
        .order_by(
            UserSubscription.end_date.is_(None),
            UserSubscription.end_date.desc(),
            UserSubscription.start_date.desc(),
        )
        .first()
    )
    
    BODY = """
    <h2>User #{{ u.id }} — {{ u.email }}</h2>
    <p>Name: {{ u.first_name or '' }} | TZ: {{ u.timezone or '' }} | Lang: {{ u.language or '' }} | Audio: {{ 'on' if u.enable_audio else 'off' }}</p>

    {% if request.args.get('msg') %}
      <div class="msg">{{ request.args.get('msg') }}</div>
    {% endif %}

    <h3>Credits</h3>
    <form method="post" action="/admin/users/{{ u.id }}/credits">
      <label>Text remaining this week:
        <input type="number" name="text_remaining_week" value="{{ credits.text_remaining_week if credits else 0 }}" min="0">
      </label>
      <label>Images remaining lifetime:
        <input type="number" name="image_remaining_lifetime" value="{{ credits.image_remaining_lifetime if credits else 0 }}" min="0">
      </label>
      <button type="submit">Update credits</button>
    </form>

    <h3>Subscription</h3>

    {% if not plans %}
      <div class="msg">No plans found. <a href="/admin/plans">Seed default plans</a>.</div>
    {% endif %}
    
    {% if current_sub %}
      <div class="msg">
        Current: <b>{{ current_sub.plan_id }}</b>
        · status {{ current_sub.status }}
        · start {{ current_sub.start_date }}
        · end {{ current_sub.end_date or '—' }}
        · auto renew {{ 'yes' if current_sub.auto_renew else 'no' }}
      </div>
    {% else %}
      <div class="msg">No subscription on record</div>
    {% endif %}
    <h3></h3>
    <form method="post" action="/admin/users/{{ u.id }}/subscription" class="grid2">
      <label>Action</label>
      <select name="action">
        <option value="create">Create new</option>
        <option value="update_latest">Update latest</option>
      </select>
    
      <label>Plan</label>
      <select name="plan_id">
        {% for p in plans %}
          <option value="{{ p.id }}"
            {% if current_sub and p.id == current_sub.plan_id %}selected{% endif %}>
            {{ p.id }} ({{ p.period }}, ${{ '%.2f'|format(p.price) }})
          </option>
        {% endfor %}
      </select>
    
      <label>Status</label>
      <select name="status">
        {% for s in ['active','trial','canceled','expired'] %}
          <option value="{{ s }}"
            {% if current_sub and s == current_sub.status %}selected{% endif %}>{{ s }}</option>
        {% endfor %}
      </select>
    
      <label>Auto renew</label>
      <select name="auto_renew">
        <option value="0" {% if current_sub and not current_sub.auto_renew %}selected{% endif %}>no</option>
        <option value="1" {% if current_sub and current_sub.auto_renew %}selected{% endif %}>yes</option>
      </select>
    
      <label>Start (blank = now)</label>
      <input name="start_date" placeholder="YYYY-MM-DD or ISO"
             value="{{ current_sub.start_date if current_sub else '' }}">
    
      <label>End (blank = auto by plan)</label>
      <input name="end_date" placeholder="YYYY-MM-DD or ISO"
             value="{{ current_sub.end_date if current_sub else '' }}">
    
      <label>Payment provider</label>
      <select name="payment_provider">
        <option></option><option>apple</option><option>google</option><option>stripe</option>
      </select>
    
      <label>Payment method</label>
      <input name="payment_method" placeholder="card / apple / google">
    
      <div></div><button class="btn" type="submit">Save subscription</button>
    </form>

    <h3>Set password</h3>
    <form method="post" action="/admin/users/{{ u.id }}/password">
      <input name="password" type="password" minlength="8" required placeholder="New password">
      <button type="submit">Set password</button>
    </form>

    <h3>Dreams (latest 50)</h3>
    <table>
      <tr><th>ID</th><th>Created</th><th>Hidden</th><th>Summary</th><th>Text</th><th>Analysis</th><th>Actions</th></tr>
      {% for d in dreams %}
        <tr>
          <td>{{ d.id }}</td>
          <td>{{ d.created_at }}</td>
          <td>{{ d.hidden and 'yes' or 'no' }}</td>
          <td>{{ d.summary or (d.text[:80] ~ ('…' if d.text and d.text|length>80 else '')) }}</td>
          <td>{{ d.text or (d.text[:80] ~ ('…' if d.text and d.text|length>80 else '')) }}</td>
          <td>{{ d.analysis }}</td>
          <td>
            <form class="inline" method="post" action="/admin/users/{{ u.id }}/dreams/{{ d.id }}/toggle-hidden">
              <button type="submit">{{ d.hidden and 'Unhide' or 'Hide' }}</button>
            </form>
            <form class="inline" method="post" action="/admin/users/{{ u.id }}/dreams/{{ d.id }}/delete" onsubmit="return confirm('Delete dream {{ d.id }}? This moves images to /static/images/deleted');">
              <button type="submit">Delete</button>
            </form>
          </td>
        </tr>
      {% endfor %}
    </table>

    <h3>Subscriptions (history)</h3>
    <table>
      <tr><th>ID</th><th>Plan</th><th>Status</th><th>Start</th><th>End</th><th>Auto</th><th>Provider</th></tr>
      {% for s in subs %}
        <tr><td>{{ s.id }}</td><td>{{ s.plan_id }}</td><td>{{ s.status }}</td><td>{{ s.start_date }}</td><td>{{ s.end_date or '' }}</td><td>{{ 'yes' if s.auto_renew else 'no' }}</td><td>{{ s.payment_provider or '' }}</td></tr>
      {% endfor %}
    </table>

    <h3>Payments</h3>
    <table>
      <tr><th>ID</th><th>Amount</th><th>Status</th><th>Provider</th><th>Txn</th><th>When</th></tr>
      {% for p in payments %}
        <tr><td>{{ p.id }}</td><td>{{ '%.2f'|format(p.amount) }} {{ p.currency }}</td><td>{{ p.status }}</td><td>{{ p.provider }}</td><td>{{ p.provider_transaction_id or '' }}</td><td>{{ p.created_at }}</td></tr>
      {% endfor %}
    </table>
    """
    return _render_admin(BODY, f"User {u.id}",
                         u=u, subs=subs, credits=credits, dreams=dreams, payments=payments, plans=plans, current_sub=current_sub)

# Optional: debug
@app.get("/admin/debug")
def admin_debug():
    emails = list(_get_admin_emails())
    return {
        "is_authenticated": current_user.is_authenticated,
        "email": (current_user.email or None) if current_user.is_authenticated else None,
        "ADMIN_EMAILS": emails,
        "match": current_user.is_authenticated and (current_user.email or "").lower() in emails,
    }, 200


# --- Helpers ---
def _parse_iso_optional(s: str | None):
    if not s:
        return None
    v = s.strip()
    if not v:
        return None
    try:
        if len(v) == 10:
            return datetime.strptime(v, "%Y-%m-%d")
        return datetime.fromisoformat(v.replace("Z", "+00:00")).replace(tzinfo=None)
    except Exception:
        raise ValueError("Invalid date; use YYYY-MM-DD or ISO 8601")

def _admin_redirect(user_id: int, msg: str = ""):
    msg_q = f"?msg={requests.utils.quote(msg)}" if msg else ""
    return redirect(f"/admin/users/{user_id}{msg_q}")

# --- Update credits ---
@app.post("/admin/users/<int:user_id>/credits")
@admin_required
def admin_update_credits(user_id: int):
    u = User.query.get_or_404(user_id)
    try:
        tw = int(request.form.get("text_remaining_week", "0"))
        iw = int(request.form.get("image_remaining_lifetime", "0"))
        if tw < 0 or iw < 0:
            return _admin_redirect(user_id, "Credits must be >= 0")
        uc = UserCredits.query.get(user_id)
        if not uc:
            # week_anchor_utc required; set to start of current week in UTC
            now = datetime.utcnow()
            week_anchor = now - timedelta(days=now.weekday())  # Monday
            uc = UserCredits(user_id=user_id, week_anchor_utc=week_anchor, text_remaining_week=tw, image_remaining_lifetime=iw)
            db.session.add(uc)
        else:
            uc.text_remaining_week = tw
            uc.image_remaining_lifetime = iw
        db.session.commit()
        return _admin_redirect(user_id, "Credits updated")
    except Exception:
        db.session.rollback()
        return _admin_redirect(user_id, "Failed to update credits")

# --- Create or update subscription ---
@app.post("/admin/users/<int:user_id>/subscription")
@admin_required
def admin_update_subscription(user_id: int):
    u = User.query.get_or_404(user_id)
    action = (request.form.get("action") or "create").strip()
    plan_id = (request.form.get("plan_id") or "").strip()
    status = (request.form.get("status") or "active").strip()
    auto_renew = (request.form.get("auto_renew") or "0").strip() in ("1", "true", "yes")
    payment_provider = (request.form.get("payment_provider") or "").strip() or None
    payment_method = (request.form.get("payment_method") or "").strip() or None
    start_date = request.form.get("start_date") or ""
    end_date = request.form.get("end_date") or ""

    plan = SubscriptionPlan.query.get(plan_id) if plan_id else None
    if not plan:
        return _admin_redirect(user_id, "Invalid plan")

    try:
        sd = _parse_iso_optional(start_date) or datetime.utcnow()
        ed = _parse_iso_optional(end_date)
        if not ed:
            # compute by plan.period
            if (plan.period or "").lower().startswith("month"):
                ed = sd + relativedelta(months=1)
            elif (plan.period or "").lower().startswith("year"):
                ed = sd + relativedelta(years=1)
            else:
                ed = sd + timedelta(days=30)

        if action == "update_latest":
            latest = (UserSubscription.query
                      .filter_by(user_id=user_id)
                      .order_by(UserSubscription.created_at.desc()).first())
            if not latest:
                return _admin_redirect(user_id, "No subscription to update")
            latest.plan_id = plan_id
            latest.status = status
            latest.start_date = sd
            latest.end_date = ed
            latest.auto_renew = auto_renew
            latest.payment_provider = payment_provider
            latest.payment_method = payment_method
            db.session.commit()
            return _admin_redirect(user_id, "Subscription updated")
        else:
            sub = UserSubscription(
                user_id=user_id,
                plan_id=plan_id,
                status=status,
                start_date=sd,
                end_date=ed,
                auto_renew=auto_renew,
                payment_provider=payment_provider,
                payment_method=payment_method
            )
            db.session.add(sub)
            db.session.commit()
            return _admin_redirect(user_id, "Subscription created")
    except ValueError as ve:
        db.session.rollback()
        return _admin_redirect(user_id, str(ve))
    except Exception:
        db.session.rollback()
        return _admin_redirect(user_id, "Failed to save subscription")

# --- Toggle dream hidden ---
@app.post("/admin/users/<int:user_id>/dreams/<int:dream_id>/toggle-hidden")
@admin_required
def admin_toggle_dream_hidden(user_id: int, dream_id: int):
    d = Dream.query.get_or_404(dream_id)
    if d.user_id != user_id:
        return _admin_redirect(user_id, "Dream does not belong to user")
    try:
        d.hidden = not bool(d.hidden)
        db.session.commit()
        return _admin_redirect(user_id, f"Dream {dream_id} {'hidden' if d.hidden else 'unhidden'}")
    except Exception:
        db.session.rollback()
        return _admin_redirect(user_id, "Failed to toggle")

# --- Delete dream (with image archival) ---
@app.post("/admin/users/<int:user_id>/dreams/<int:dream_id>/delete")
@admin_required
def admin_delete_dream(user_id: int, dream_id: int):
    d = Dream.query.get_or_404(dream_id)
    if d.user_id != user_id:
        return _admin_redirect(user_id, "Dream does not belong to user")
    try:
        if d.image_file:
            try:
                image_path = os.path.join("static", "images", "dreams", d.image_file)
                tile_path = os.path.join("static", "images", "tiles", d.image_file)
                archive_dir = os.path.join("static", "images", "deleted")
                os.makedirs(archive_dir, exist_ok=True)
                for path in [image_path, tile_path]:
                    if os.path.exists(path):
                        shutil.move(path, os.path.join(archive_dir, os.path.basename(path)))
            except Exception:
                pass
        db.session.delete(d)
        db.session.commit()
        return _admin_redirect(user_id, f"Dream {dream_id} deleted")
    except Exception:
        db.session.rollback()
        return _admin_redirect(user_id, "Failed to delete dream")

# --- Set user password ---
@app.post("/admin/users/<int:user_id>/password")
@admin_required
def admin_set_password(user_id: int):
    u = User.query.get_or_404(user_id)
    pw = request.form.get("password") or ""
    if len(pw) < 8:
        return _admin_redirect(user_id, "Password must be at least 8 chars")
    try:
        u.password = bcrypt.hashpw(pw.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")
        db.session.commit()
        return _admin_redirect(user_id, "Password updated")
    except Exception:
        db.session.rollback()
        return _admin_redirect(user_id, "Failed to update password")



if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

