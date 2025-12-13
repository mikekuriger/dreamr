#!/usr/bin/env python3
import argparse
import base64
import uuid
from pathlib import Path

from app import app, db, client, generate_resized_image
from app import Interpreter


ICON_STYLE_PROMPT = """
Style: 16-bit pixel art icon with a dreamy, soft aesthetic.
Simple shapes, limited color palette, gentle gradients.
Muted pastel colors (lavender, soft blues, warm creams).
No neon, no harsh contrast, no sharp edges.
Cartoon-like, friendly, calming.
Soft lighting, slightly whimsical.
Centered composition.
Flat background with subtle texture or gradient.
No text, no logos, no realistic facial likeness.
Same character style and proportions as other Dreamr interpreter icons.
""".strip()


OUT_DIR = Path("static/images/interpreters")
TILE_DIR = Path("static/images/interpreters_tiles")


def generate_one(interp: "Interpreter", size="1024x1024", tile_size=256, force=False):
    # Skip if already generated unless forced
    if interp.icon_file and interp.icon_tile_file and not force:
        return False, "skipped_existing"

    subject = getattr(interp, "icon_subject", None)
    if not subject:
        return False, "missing_icon_subject"

    prompt = f"{ICON_STYLE_PROMPT}\n\nSubject:\n{subject.strip()}\n"

    resp = client.images.generate(
        model="gpt-image-1",
        prompt=prompt,
        n=1,
        size=size,
    )

    b64 = resp.data[0].b64_json
    img_bytes = base64.b64decode(b64)

    filename = f"{uuid.uuid4().hex}.png"
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    TILE_DIR.mkdir(parents=True, exist_ok=True)

    icon_path = OUT_DIR / filename
    tile_path = TILE_DIR / filename

    icon_path.write_bytes(img_bytes)

    # Reuse your existing helper (PIL thumbnail)
    generate_resized_image(str(icon_path), str(tile_path), size=(tile_size, tile_size))

    interp.icon_file = filename
    interp.icon_tile_file = filename
    interp.icon_prompt = prompt

    db.session.commit()
    return True, filename


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true", help="Regenerate even if icon exists")
    parser.add_argument("--only", default=None, help="Generate only one interpreter by slug")
    parser.add_argument("--size", default="1024x1024", help="Image size passed to model")
    parser.add_argument("--tile", type=int, default=256, help="Tile size (px)")
    args = parser.parse_args()

    with app.app_context():
        q = Interpreter.query.filter_by(is_enabled=True).order_by(Interpreter.sort_order.asc())
        if args.only:
            q = q.filter_by(slug=args.only)

        rows = q.all()
        if not rows:
            print("No interpreters matched query.")
            return

        ok = 0
        skipped = 0
        missing = 0

        for interp in rows:
            changed, status = generate_one(interp, size=args.size, tile_size=args.tile, force=args.force)
            if changed:
                ok += 1
                print(f"OK   {interp.slug}: {status}")
            else:
                if status == "skipped_existing":
                    skipped += 1
                    print(f"SKIP {interp.slug}: already has icon")
                elif status == "missing_icon_subject":
                    missing += 1
                    print(f"SKIP {interp.slug}: missing icon_subject (add to seed + DB)")
                else:
                    print(f"SKIP {interp.slug}: {status}")

        print(f"\nDone. generated={ok} skipped_existing={skipped} missing_subject={missing}")


if __name__ == "__main__":
    main()
