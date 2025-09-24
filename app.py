### File: app.py
from authlib.integrations.flask_client import OAuth # for google auth
from datetime import datetime, timezone, timedelta
from enum import Enum
from flask_cors import CORS
from flask import Flask, request, jsonify, url_for, redirect, session, Blueprint, render_template, render_template_string
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
from sqlalchemy import func
from sqlalchemy import or_
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
logger.setLevel(logging.DEBUG)  # or INFO if you want less detail
# Clear any existing handlers (especially important when running under Gunicorn)
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
CORS(app, supports_credentials=True,origins=["https://dreamr.zentha.me", "http://localhost:5173"])

db = SQLAlchemy(app)
login_manager = LoginManager(app)
login_manager.init_app(app)
migrate = Migrate(app, db)
mail = Mail(app)


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
    # is_draft = db.Column(db.Boolean, default=False)  # Saved dreams that have not been analyzed


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


# for fetching all file names (not images) to display on landing page
@app.route("/api/images", methods=["GET"])
def get_images():
    IMAGE_DIR = "/data/dreamr-frontend/static/images/dreams"
    files = os.listdir(IMAGE_DIR)
    return jsonify([f for f in files if f.endswith(".png")])


# Profile 
UPLOAD_FOLDER = '/data/dreamr-frontend/static/avatars'
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

# @profile_bp.route('/api/profile', methods=['GET', 'POST'])
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



# begin - these seem to be unused
# @app.route('/api/gallery/<dream_id>')
# def get_dream_by_id(dream_id):
#     dream = Dream.query.get(dream_id)
#     # if not dream or not dream.hidden:
#     if not dream or dream.hidden:
#         return jsonify({'error': 'Dream not found'}), 404

#     return jsonify({
#         'id': dream.id,
#         'summary': dream.summary,
#         'image_file': dream.image_file,
#         'created_at': dream.created_at.isoformat()
#     })


# @app.route('/gallery/<dream_id>')
# def public_gallery_view(dream_id):
#     dream = Dream.query.get(dream_id)
#     # if not dream or not dream.hidden:
#     if not dream or dream.hidden:
#         return "Dream not found", 404
#     return render_template("public_dream.html", dream=dream)
# end - these seem to be unused



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

    login_user(user)
    # return redirect("/dashboard?confirmed=1")
    return redirect("/dashboard")


# for google logins via mobile app
@app.route('/api/google_login', methods=['POST'])
def api_google_login():
    data = request.get_json()
    token = data.get('id_token')

    try:
        # ✅ Correct usage: instantiate request object
        req = google_requests.Request()
        # idinfo = id_token.verify_oauth2_token(token, req)
        idinfo = id_token.verify_oauth2_token(token, req, google_creds['web']['client_id'])

        email = idinfo['email']
        name = idinfo.get('name')

        user = User.query.filter_by(email=email).first()
        if not user:
            user = User(email=email, first_name=name or "Unknown", password='', timezone='')
            db.session.add(user)
            db.session.commit()

        login_user(user)
        return jsonify({"success": True})

    except ValueError:
        return jsonify({"error": "Invalid token"}), 400


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


def send_confirmation_email(recipient_email, token):
    confirm_url = f"https://dreamr.zentha.me/confirm/{token}"
    msg = Message(
        subject="Confirm your Dreamr✨account",
        recipients=[recipient_email],
        body=(
            f"Welcome to Dreamr!\n\n"
            f"Click the link below to confirm your account:\n\n"
            f"{confirm_url}\n\n"
            f"If you didn't sign up for Dreamr, ignore this message."
        )
    )
    mail.send(msg)


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
    data = request.get_json()
    # email = data.get("email")
    email = data.get("email", "").strip().lower()  # 🔒 Normalize email
    password = data.get("password")
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

              
def convert_dream_to_image_prompt(message, tone=None):
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


# dream analysis
@app.route("/api/chat", methods=["POST"])
@login_required
def chat():
    logger.info(" /api/chat called")
    data = request.get_json()
    logger.debug(f"Received JSON: {data}")

    message = data.get("message")
    # dream_id = data.get("id")  # Optional - used if submitting from a draft
  
    if not message:
        logger.debug("[WARN] Missing dream message.")
        return jsonify({"error": "Missing dream message."}), 400

    try:
        # Step 1: Save dream
        # if dream_id:
        #     logger.info(f"Updating existing draft with ID {dream_id}")
        #     dream = Dream.query.filter_by(id=dream_id, user_id=current_user.id).first()
        #     if not dream:
        #         logger.warning(f"No draft found with ID {dream_id} for user {current_user.id}")
        #         return jsonify({"error": "Draft not found."}), 404
        #     dream.text = message
        #     dream.is_draft = False
        #     # dream.created_at = datetime.utcnow()  # Optional: refresh timestamp
        # else:
        #     logger.info("Saving new dream to database...")
        #     dream = Dream(
        #         user_id=current_user.id,
        #         text=message,
        #         created_at=datetime.utcnow(),
        #         is_draft=False
        #     )
        #     db.session.add(dream)
        
        # db.session.commit()
        # logger.debug(f"Dream record saved with ID: {dream.id}")

        logger.info("Saving dream to database...")
        dream = Dream(
            user_id=current_user.id,
            text=message,
            created_at=datetime.utcnow()
        )
        db.session.add(dream)
        db.session.commit()

        logger.debug(f"Dream saved in with ID: {dream.id}")

        # Step 2: GPT Analysis
        dream_prompt = CATEGORY_PROMPTS["dream"]
        prompt = f"{dream_prompt}\n\nDream:\n{message}"
        logger.info("Sending prompt to OpenAI:")
        logger.debug(f"Dream Analysis Prompt: {prompt}")

        response = call_openai_with_retry(prompt)

        if not response.choices or not response.choices[0].message:
            logger.error("[ERROR] AI response was empty.")
            return jsonify({"error": "AI response was empty"}), 500

        content = response.choices[0].message.content.strip()
        logger.debug(f"Dream Analysis Reply: {content}")

        analysis = summary = tone = None

        if "**Analysis:**" in content and "**Summary:**" in content and "**Tone:**" in content:
            try:
                parts = content.split("**Summary:**")
                analysis_part = parts[0].replace("**Analysis:**", "").strip()
                summary_tone_part = parts[1].strip().split("**Tone:**")
                summary = summary_tone_part[0].strip()
                tone_candidate = summary_tone_part[1].strip().rstrip(string.punctuation)

                # Validate tone
                valid_tones = list(TONE_TO_STYLE.keys())
                if tone_candidate in valid_tones:
                    tone = tone_candidate
                else:
                    logger.warning(f"[WARN] Invalid tone received: {repr(tone_candidate)}")
                    tone = None

                analysis = analysis_part

            except Exception as parse_err:
                logger.warning("Failed to parse analysis/summary/tone from AI response", exc_info=True)
                analysis = content  # fallback
        else:
            logger.warning("[WARN] AI response format missing expected tags — using fallback")
            analysis = content  # fallback

        dream.analysis = analysis
        dream.summary = summary
        dream.tone = tone
        db.session.commit()
        logger.info("Dream analysis saved to database.")

        return jsonify({
            "analysis": analysis,
            "summary": summary,
            "tone": tone,
            "dream_id": dream.id
        })

    except Exception as e:
        db.session.rollback()
        logger.error("Exception occurred during dream processing:", exc_info=True)
        return jsonify({"error": str(e)}), 500


# save dream for later analysis
# @app.route("/api/draft", methods=["POST"])
# @login_required
# def draft():
#     logger.info(" /api/draft called")
#     data = request.get_json()
#     logger.debug(f"Received JSON: {data}")

#     message = data.get("message")
#     if not message or not message.strip():
#         return jsonify({"error": "Empty draft message."}), 400
#         logger.debug("[WARN] Empty draft message.")

#     try:
#         # Step 1: Save dream
#         logger.info("Saving draft to database...")
#         dream = Dream(
#             user_id=current_user.id,
#             text=message,
#             created_at=datetime.utcnow(),
#             is_draft=True
#         )
#         db.session.add(dream)
#         db.session.commit()
#         logger.debug(f"Dream saved in with ID: {dream.id}")
#         return jsonify({"status": "ok", "dream_id": dream.id}), 200

#     except Exception as e:
#         db.session.rollback()
#         logger.error("Exception occurred saving draft:", exc_info=True)
#         return jsonify({"error": str(e)}), 500


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


@app.route("/api/image_generate", methods=["POST"])
@login_required
def generate_dream_image():
    logger.info(" /api/image_generate called")
    data = request.get_json()
    dream_id = data.get("dream_id")

    if not dream_id:
        logger.debug("[WARN] Missing dream ID.")
        return jsonify({"error": "Missing dream ID."}), 400

    dream = Dream.query.get(dream_id)

    if not dream or dream.user_id != current_user.id:
        return jsonify({"error": "Dream not found or unauthorized"}), 404

    message = dream.text
    tone = dream.tone

    try:
        logger.info("Converting dream to image prompt...")
        image_prompt = convert_dream_to_image_prompt(message, tone)
        logger.debug(f"Image prompt: {image_prompt}")
        logger.info("Sending image generation request...")

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

  
@app.route("/api/dreams", methods=["GET"])
@login_required
def get_dreams():
    user_tz = ZoneInfo(current_user.timezone or "UTC") 

    dreams = Dream.query.filter(
        Dream.user_id == current_user.id,
        or_(Dream.hidden == False, Dream.hidden.is_(None))
        # or_(Dream.is_draft == False, Dream.is_draft.is_(None))
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
            "created_at": convert_created_at(d.created_at) if d.created_at else None
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

