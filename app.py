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
import uuid
import requests
import traceback
import logging
import base64



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


class Dream(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    text = db.Column(db.Text)                      # user's dream text
    analysis = db.Column(db.Text)                  # AI's response
    image_url = db.Column(db.Text)                 # original OpenAI URL (optional)
    image_file = db.Column(db.String(255))         # saved filename (e.g., 'dream_123.png')
    created_at = db.Column(db.DateTime, default=datetime.utcnow)


def convert_dream_to_image_prompt(message):
    prompt = (
        "Rewrite the following dream description into a vivid, detailed visual prompt suitable for AI image generation. "
        "Focus on visual elements, scenery, atmosphere, and objects. Avoid dialogue, violence, or banned words. "
        "Use visual metaphor and artistic style to capture emotion. "
        "Convert harsh elements into metaphor, symbolism, or stylized visuals. Max 2000 characters.\n\n"
        f"Dream: {message}"
    )
    # prompt = (
    #     "Rewrite the following dream description into a vivid, detailed visual prompt suitable for an AI image generator. "
    #     "Focus on the visual elements, scenery, atmosphere, and objects. "
    #     "Do not include dialogue or analysis. Use visual metaphor and artistic style to capture emotion. "
    #     "Convert harsh elements into metaphor, symbolism, or stylized visuals and do not use prohibited words. "
    #     "Keep the response 500 characters or below.\n\n"
    #     f"Dream: {message}"
    # )
    response = client.chat.completions.create(
        model="gpt-4o",
        messages=[{"role": "user", "content": prompt}]
    )
    return response.choices[0].message.content.strip()


@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))


@app.route("/api/images", methods=["GET"])
def get_images():
    IMAGE_DIR = "/data/dreamr-frontend/static/images/dreams"
    files = os.listdir(IMAGE_DIR)
    return jsonify([f for f in files if f.endswith(".png")])
    
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
    login_user(user)
    return jsonify({
      "message": "Registration successful",
      "first_name": user.first_name 
    })

    
@app.route("/api/login", methods=["POST"])
def login():
    data = request.get_json()
    email = data.get("email")
    password = data.get("password")
    user = User.query.filter_by(email=email).first()
    if not user or not bcrypt.checkpw(password.encode('utf-8'), user.password.encode('utf-8')):
        return jsonify({"error": "Invalid credentials"}), 401
    # login_user(user)
    login_user(user, remember=True)
    return jsonify({"message": "Logged in"})

@app.route("/api/logout", methods=["POST"])
@login_required
def logout():
    logout_user()
    return jsonify({"message": "Logged out"})



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
        # Step 1: Save dream text immediately
        logger.info("Saving dream to database...")
        dream = Dream(
            user_id=current_user.id,
            text=message,
            created_at=datetime.utcnow()
        )
        db.session.add(dream)
        db.session.commit()
        logger.debug(f"Dream saved with ID: {dream.id}")

        # Step 2: AI Analysis
        dream_prompt = (
            "You are a professional dream analyst. Do not answer questions outside of dream interpretation. "
            "Keep response clear and thoughtful. Politely decline unrelated questions. "
        )
        prompt = f"{dream_prompt}\n\n{message}"
        logger.info("Sending prompt to OpenAI:")
        logger.debug(f"Prompt: {prompt}")

        response = openai.chat.completions.create(
            model="gpt-4o",
            messages=[{"role": "user", "content": prompt}]
        )

        if not response.choices or not response.choices[0].message:
            logger.debug("[ERROR] AI response was empty.")
            return jsonify({"error": "AI response was empty"}), 500

        analysis = response.choices[0].message.content.strip()
        dream.analysis = analysis
        db.session.commit()

        logger.debug(f"Analysis: {analysis}")

        # Step 3: Try image generation (optional) model="dall-e-3"
        try:
           logger.info("Converting dream to image prompt...")
           image_prompt = convert_dream_to_image_prompt(message)
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
           logger.debug(f"Image URL received: {image_url}")

           filename = f"{uuid.uuid4().hex}.png"
           image_path = os.path.join("static", "images", "dreams", filename)
           os.makedirs(os.path.dirname(image_path), exist_ok=True)

           # Save the image to a file

           img_data = requests.get(image_url).content
           with open(image_path, "wb") as f:
               f.write(img_data)

           dream.image_url = image_url
           dream.image_file = filename
           logger.info(f"Image saved to {image_path}")

        # # Step 3: Try image generation (optional) model="gpt-image-1"
        # try:
        #     logger.info("Converting dream to image prompt...")
        #     image_prompt = convert_dream_to_image_prompt(message)
        #     logger.debug(f"Image prompt: {image_prompt}")
        #     logger.info("Sending image generation request...")
        
        #     image_response = client.images.generate(
        #         model="gpt-image-1",
        #         size="1024x1024",
        #         prompt=image_prompt
        #     )
        #     image_base64 = image_response.data[0].b64_json
        #     image_bytes = base64.b64decode(image_base64)
        
        #     filename = f"{uuid.uuid4().hex}.png"
        #     STATIC_IMAGE_DIR = "/data/dreamr-frontend/static/images/dreams"
        #     image_path = os.path.join(STATIC_IMAGE_DIR, filename)
        #     os.makedirs(STATIC_IMAGE_DIR, exist_ok=True)
        
        #     with open(image_path, "wb") as f:
        #         f.write(image_bytes)
        
        #     dream.image_file = filename
        #     logger.info(f"Image saved to {image_path}")


        
        except openai.OpenAIError as e:
            logger.error(f"[ERROR] OpenAI image generation failed: {e}")
            
        except requests.RequestException as e:
            logger.error(f"[ERROR] Failed to fetch image from URL: {e}")

        except Exception as img_error:
            logger.warning("Image generation failed", exc_info=True)

        db.session.commit()
        logger.info("Dream successfully saved to database.")

        return jsonify({
            "analysis": dream.analysis,
            "image": f"/static/images/dreams/{dream.image_file}" if dream.image_file else None
        })

    except Exception as e:
        db.session.rollback()
        logger.debug("Exception occurred during dream processing:")
        logger.exception("Exception occurred during dream processing")
        return jsonify({"error": str(e)}), 500



@app.route("/api/dreams", methods=["GET"])
@login_required
def get_dreams():
    dreams = Dream.query.filter_by(user_id=current_user.id) \
                        .order_by(Dream.created_at.desc()) \
                        .all()
    #dreams = Dream.query.filter_by(user_id=current_user.id).all()
    return jsonify([
        {
            "id": d.id,
            "text": d.text,
            "analysis": d.analysis,
            "image_file": f"/static/images/dreams/{d.image_file}" if d.image_file else None,
            "created_at": d.created_at.isoformat() if d.created_at else None
        } for d in dreams
    ])
    
@app.route("/api/check_auth", methods=["GET"])
def check_auth():
    if current_user.is_authenticated:
        return jsonify({
            "authenticated": True,
            "first_name": current_user.first_name
        })
    return jsonify({"authenticated": False}), 401


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

