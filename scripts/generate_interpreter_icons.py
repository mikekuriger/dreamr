import base64
import os
import uuid
from pathlib import Path

from app import create_app, db
from app.models import Interpreter
from app.image_utils import generate_resized_image  # your function
from app.openai_client import client  # however you instantiate it

ICON_STYLE_PROMPT = """Style: 16-bit pixel art icon with a dreamy, soft aesthetic.
Simple shapes, limited color palette, gentle gradients.
Muted pastel colors (lavender, soft blues, warm creams).
No neon, no harsh contrast, no sharp edges.
Cartoon-like, friendly, calming.
Soft lighting, slightly whimsical.
Centered composition.
Flat background with subtle texture or gradient.
No text, no logos, no realistic facial likeness.
Same character style and proportions as other Dreamr interpreter icons.
"""

# If you keep icon subject prompts in JSON, store them in the DB as prompt_extra or add icon_subject field.
# For now you can hardcode a dict, or add "icon_subject" to the DB and seed it too.

ICON_SUBJECTS = {
  "seer": "A mysterious but kind figure with scarf or shawl, holding a softly glowing crystal orb, swirling mist shapes, evocative but calm expression.",
  "rogue": "A playful trickster character with tilted hat, holding a compass or coin, smirking but friendly expression, sense of motion and freedom.",
  # ... fill in all icon_keys
}

OUT_DIR = Path("static/images/interpreters")
TILE_DIR = Path("static/images/interpreters_tiles")
OUT_DIR.mkdir(parents=True, exist_ok=True)
TILE_DIR.mkdir(parents=True, exist_ok=True)

def main(force=False):
    app = create_app()
    with app.app_context():
        q = Interpreter.query.filter_by(is_enabled=True).order_by(Interpreter.sort_order.asc()).all()
        for interp in q:
            if interp.icon_file and not force:
                continue

            subject = ICON_SUBJECTS.get(interp.icon_key or interp.slug)
            if not subject:
                print(f"SKIP {interp.slug}: missing ICON_SUBJECTS entry for icon_key={interp.icon_key}")
                continue

            icon_prompt = f"{ICON_STYLE_PROMPT}\n\nSubject:\n{subject}\n"
            resp = client.images.generate(
                model="gpt-image-1",
                prompt=icon_prompt,
                n=1,
                size="1024x1024"
            )
            img_bytes = base64.b64decode(resp.data[0].b64_json)

            filename = f"{uuid.uuid4().hex}.png"
            icon_path = OUT_DIR / filename
            tile_path = TILE_DIR / filename

            icon_path.write_bytes(img_bytes)
            generate_resized_image(str(icon_path), str(tile_path), size=(256, 256))

            interp.icon_file = filename
            interp.icon_tile_file = filename
            interp.icon_prompt = icon_prompt
            db.session.commit()

            print(f"OK {interp.slug}: {filename}")

if __name__ == "__main__":
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("--force", action="store_true")
    args = p.parse_args()
    main(force=args.force)

