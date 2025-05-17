### File: app.py

from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager, login_user, login_required, logout_user, current_user, UserMixin
from flask_cors import CORS
from openai import OpenAI
import openai
import os
import bcrypt
from datetime import datetime


client = OpenAI()

openai.api_key = os.environ.get("OPENAI_API_KEY")

app = Flask(__name__)
app.config.from_pyfile('config.py')
# app.config.from_object("config.Config")
CORS(app, supports_credentials=True)

db = SQLAlchemy(app)
login_manager = LoginManager(app)

# Models
class User(db.Model, UserMixin):
    __tablename__ = 'users'

    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password = db.Column(db.String(128), nullable=False)

    first_name = db.Column(db.String(50), nullable=True)
    birthdate = db.Column(db.Date, nullable=True)
    gender = db.Column(db.String(20), nullable=True)  # e.g., "male", "female", "nonbinary", "prefer not to say"
    signup_date = db.Column(db.DateTime, default=db.func.now())
    timezone = db.Column(db.String(50), nullable=True)  # e.g., "America/Los_Angeles"


from datetime import datetime

class Dream(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    text = db.Column(db.Text)                      # user's dream text
    analysis = db.Column(db.Text)                  # AI's response
    image_url = db.Column(db.Text)                 # original OpenAI URL (optional)
    image_file = db.Column(db.String(255))         # saved filename (e.g., 'dream_123.png')
    created_at = db.Column(db.DateTime, default=datetime.utcnow)


@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))

@app.route("/api/register", methods=["POST"])
def register():
    data = request.get_json()
    first_name = data.get("first_name")
    email = data.get("email")
    gender = data.get("gender")
    birthdate = data.get("birthdate")
    timezone = data.get("timezone")
    password = data.get("password")
    if User.query.filter_by(email=email).first():
        return jsonify({"error": "User already exists"}), 400
    hashed = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
    #hashed = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt(rounds=4))
    #hashed = "testhash"
    user = User(
        email=email,
        password=hashed,
        first_name=first_name,
        gender=gender,
        timezone=timezone,
        birthdate=birthdate  # SQLAlchemy will auto-convert string to date if formatted correctly
    )
    db.session.add(user)
    db.session.commit()
    return jsonify({"message": "User registered"})

@app.route("/api/login", methods=["POST"])
def login():
    data = request.get_json()
    email = data.get("email")
    password = data.get("password")
    user = User.query.filter_by(email=email).first()
    # if not user or not bcrypt.checkpw(password.encode('utf-8'), user.password)):
    if not user or not bcrypt.checkpw(password.encode('utf-8'), user.password.encode('utf-8')):
        return jsonify({"error": "Invalid credentials"}), 401
    login_user(user)
    return jsonify({"message": "Logged in"})

@app.route("/api/logout", methods=["POST"])
@login_required
def logout():
    logout_user()
    return jsonify({"message": "Logged out"})

@app.route("/api/chat", methods=["POST"])
@login_required
def chat():
    data = request.get_json()
    user_id = current_user.id
    category = data.get("category", "dream")
    message = data.get("message")

    if not message or not category:
        return jsonify({"error": "Missing message or category"}), 400

    try:
        # Start session with system prompt if needed
        session = get_session(user_id)
        if not session:
            add_to_session(user_id, "system", CATEGORY_PROMPTS.get(category, "You are a professional dream analyst. Do not answer questions outside of dream interpretation."))

        add_to_session(user_id, "user", message)

        chat_response = client.chat.completions.create(
            model="gpt-4o",
            messages=get_session(user_id)
        )

        reply = chat_response.choices[0].message.content.strip()
        add_to_session(user_id, "assistant", reply)

        # Optional image generation
        image_prompt = f"Surreal dream art: {message}"
        image_response = client.images.generate(
            prompt=image_prompt,
            n=1,
            size="512x512"
        )
        image_url = image_response.data[0].url

        # Save to DB
        dream = Dream(user_id=user_id, text=message, image_url=image_url)
        db.session.add(dream)
        db.session.commit()

        return jsonify({
            "reply": reply,
            "image_url": image_url
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/dreams", methods=["GET"])
@login_required
def get_dreams():
    dreams = Dream.query.filter_by(user_id=current_user.id).all()
    return jsonify([
        {
            "id": d.id,
            "text": d.text,
            "image_url": d.image_url,
            "created_at": d.created_at.isoformat() if d.created_at else None
        } for d in dreams
    ])
    
@app.route("/api/check_auth", methods=["GET"])
def check_auth():
    if current_user.is_authenticated:
        return jsonify({"authenticated": True})
    return jsonify({"authenticated": False}), 401


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

