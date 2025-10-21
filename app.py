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
from langdetect import detect
from openai import OpenAI
from PIL import Image
from prompts import CATEGORY_PROMPTS, TONE_TO_STYLE
from sqlalchemy import desc
from sqlalchemy import func
from sqlalchemy import or_
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
import shutil
import string
import time
import traceback
import uuid


log_file_path = "dreamr.log"
logger = logging.getLogger()
logger.setLevel(logging.DEBUG)
# Clear any existing handlers
logger.handlers = []
formatter = logging.Formatter('%(asctime)s [%(levelname)s] %(message)s')
file_handler = logging.FileHandler(log_file_path)
file_handler.setFormatter(formatter)
stream_handler = logging.StreamHandler()  # stdout (journalctl/systemd)
stream_handler.setFormatter(formatter)
logger.addHandler(file_handler)
logger.addHandler(stream_handler)

client = OpenAI()
openai.api_key = os.environ.get("OPENAI_API_KEY")

app = Flask(__name__)
app.config.from_pyfile('config.py')
# CORS(app, supports_credentials=True,origins=["https://dreamr.zentha.me", "https://dreamr-us-west-01.zentha.me", "http://localhost:5173"])
CORS(app, supports_credentials=True,origins=["https://dreamr.zentha.me", "http://localhost:5173"])

db = SQLAlchemy(app)
login_manager = LoginManager(app)
login_manager.init_app(app)
migrate = Migrate(app, db)
mail = Mail(app)

WEB_CLIENT_ID = "846080686597-61d3v0687vomt4g4tl7rueu7rv9qrari.apps.googleusercontent.com"
IOS_CLIENT_ID = "846080686597-8u85pj943ilkmlt583f3tct5h9ca0c3t.apps.googleusercontent.com"
ALLOWED_AUDS = {WEB_CLIENT_ID, IOS_CLIENT_ID}
ALLOWED_ISS = {"https://accounts.google.com", "accounts.google.com"}



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


# Notes
NOTES_MAX_LEN = 8000
NOTES_AI_ENABLED = False
REANALYZE_WITH_NOTES_ALLOWED = False
NOTES_POLICY_VERSION = "v1"

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
    if 'firstName' in data:
        user.first_name = data['firstName']
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
        user = User(email=email, first_name=name or "Unknown", password='', timezone='')
        db.session.add(user)
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
            user = User(email=email, first_name=idinfo.get("name") or "Unknown", password='', timezone='')
            db.session.add(user)
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


# New user registration
@app.route("/api/register", methods=["POST"])
def register():
    data = request.get_json()
    first_name = data.get("first_name")
    email = data.get("email", "").strip().lower()
    gender = data.get("gender")
    birthdate = data.get("birthdate")
    timezone_val = data.get("timezone")
    password = data.get("password")

    logger.info(f"📨 Registration attempt: {email}")

    EMAIL_REGEX = re.compile(r"^[^@]+@[^@]+\.[^@]+$")

    if not first_name or len(first_name.strip()) > 50:
        logger.warning("❌ Invalid name")
        return jsonify({"error": "Name must be 1–50 characters"}), 400

    if not password or len(password) < 8:
        logger.warning("❌ Invalid password")
        return jsonify({"error": "Password must be at least 8 characters"}), 400

    if not email or not EMAIL_REGEX.match(email):
        logger.warning("❌ Invalid email")
        return jsonify({"error": "Invalid email address"}), 400

    # Check for duplicates in users and pendingusers (case-insensitive)
    if User.query.filter(func.lower(User.email) == email).first() or \
        PendingUser.query.filter(func.lower(PendingUser.email) == email).first():
        logger.warning("⚠️ Duplicate user or pending registration")
        return jsonify({"error": "User already exists or is pending confirmation"}), 400

    hashed = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

    token = str(uuid.uuid4())
    pending = PendingUser(
        uuid=token,
        email=email,
        password=hashed,
        first_name=first_name,
        timezone=timezone_val,
        expires_at=datetime.utcnow() + timedelta(hours=24)
    )

    db.session.add(pending)
    db.session.commit()

    logger.info(f"✅ Registered new pending user: {email}")
    send_confirmation_email(email, token)

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
    token = request.args.get("token", "", type=str)
    if not token:
        return render_template_string(CONFIRM_PAGE_TEMPLATE, status="invalid"), 400

    pending = PendingUser.query.filter_by(uuid=token).first()
    if not pending:
        return render_template_string(CONFIRM_PAGE_TEMPLATE, status="invalid"), 400

    # Expired?
    if pending.expires_at and pending.expires_at < datetime.utcnow():
        db.session.delete(pending)
        db.session.commit()
        return render_template_string(CONFIRM_PAGE_TEMPLATE, status="expired"), 410

    # Already confirmed?
    existing = User.query.filter_by(email=pending.email).first()
    if existing:
        db.session.delete(pending)
        db.session.commit()
        return render_template_string(CONFIRM_PAGE_TEMPLATE, status="exists"), 200

    # Create the real user; NOTE: pending.password is already bcrypt-hashed in your /api/register
    new_user = User(
        email=pending.email,
        password=pending.password,
        first_name=pending.first_name,
        timezone=pending.timezone,
        signup_date=datetime.utcnow()
    )
    db.session.add(new_user)
    db.session.delete(pending)
    db.session.commit()

    # Do NOT login the browser session; we want app-only auth.
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
    pending = PendingUser.query.filter_by(uuid=token).first()

    if not pending:
        return jsonify({"error": "Invalid or expired confirmation link."}), 404

    # Optional: Check if expired
    if pending.expires_at and pending.expires_at < datetime.utcnow():
        db.session.delete(pending)
        db.session.commit()
        return jsonify({"error": "Confirmation link has expired."}), 410

    # Check if user already exists (paranoia)
    existing = User.query.filter_by(email=pending.email).first()
    if existing:
        db.session.delete(pending)
        db.session.commit()
        return jsonify({"message": "Account already confirmed."}), 200

    # Create real user
    new_user = User(
        email=pending.email,
        password=pending.password,
        first_name=pending.first_name,
        timezone=pending.timezone,
        signup_date=datetime.utcnow()
    )

    db.session.add(new_user)
    db.session.delete(pending)
    db.session.commit()

    login_user(new_user, remember=True)
    # return redirect("/dashboard?confirmed=1")  # this was for when i tested hitting the api directly from the confirmation link
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

              
def convert_dream_to_image_prompt(message, tone=None, quality="low"):
    if quality == "low":
        base_prompt = CATEGORY_PROMPTS["lq_image"]
    else:
        base_prompt = CATEGORY_PROMPTS["image"]
  
    tone = tone.strip() if tone else None
    logger.debug(f"[convert_dream_to_image_prompt] Received tone: {repr(tone)}")
    logger.debug(f"[convert_dream_to_image_prompt] Available tones: {list(TONE_TO_STYLE.keys())}")

    style = TONE_TO_STYLE.get(tone, "Artistic vivid style")
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

    try:
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

        # 2) Build prompt (adds recent life events if any)
        dream_prompt = CATEGORY_PROMPTS["dream"]
        prompt = _build_user_payload(dream_prompt, current_user.id, message)
        logger.info("Sending prompt to OpenAI")
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
            "should_generate_image": True,          # <-- authoritative “start”
        }), 200
      
    except Exception as e:
      db.session.rollback()
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
    logger.info(" /api/image_generate called")
    data = request.get_json()
    dream_id = data.get("dream_id")
    quality="high"

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
        logger.info("Converting dream to image prompt...")
        q = (quality or "low").lower()
        image_prompt = convert_dream_to_image_prompt(message, tone, q)
        # logger.debug(f"Image prompt: {image_prompt}")
        logger.info("Sending image generation request...")

        # Supported values are: 'gpt-image-1', 'gpt-image-1-mini', 'gpt-image-0721-mini-alpha', 'dall-e-2', and 'dall-e-3'
        model = "dall-e-2" if q == "low" else "dall-e-3"
        size  = "512x512"  if q == "low" else "1024x1024"
            
        image_response = client.images.generate(
            model=model,
            prompt=image_prompt,
            n=1,
            size=size,
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
        # dream.image_url = image_url
        dream.image_file = filename
        dream.image_prompt = image_prompt
        db.session.commit()
        logger.info("Dream successfully updated with image.")

        logger.info("Returning image response to frontend")
        return jsonify({
            "analysis": dream.analysis,
            "image": f"/static/images/dreams/{dream.image_file}"
        })

    except openai.OpenAIError as e:
        db.session.rollback()
        logger.error("...", exc_info=True)
        return jsonify({"error": "OpenAI image generation failed"}), 502
    except requests.RequestException as e:
        db.session.rollback()
        logger.error("...", exc_info=True)
        return jsonify({"error": "Failed to fetch image"}), 504
    except Exception:
        db.session.rollback()
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
            "enable_audio": current_user.enable_audio
        })
    return jsonify({"authenticated": False}), 401


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

