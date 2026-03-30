#!/usr/bin/env python3
import sys
from pathlib import Path
import hashlib
import base64

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from app import app, db, client, generate_resized_image
from app import Interpreter

OUT_DIR  = ROOT / "static" / "images" / "interpreters_hq"
OUT_DIR.mkdir(parents=True, exist_ok=True)

MODEL = "gpt-image-1"
SIZE  = "1024x1024"
TILE_SIZE = (256, 256)

#STYLE = (
#    "16-bit pixel art icon. Dreamy, soft, muted pastel palette. "
#    "No neon, no harsh contrast. Simple shapes. Friendly cartoon look. "
#    "Centered, square framing. Subtle soft background gradient. "
#    "No text, no logos, not a realistic likeness."
#)

STYLE = (
    #"High quality life-like illustrtion portrait. Dreamy purple and blue background and color palette. "
    "16 bit pixel art illustrtion portrait. Dreamy soft color palette. "
    "No neon, no harsh contrast. "
    "Centered, square framing. Subtle soft background gradient. "
    "No text, no logos."
)

ICON_SUBJECTS = {
  "psychoanalyst": "A classic psychoanalyst character portrait: think Freud, tidy hair, round spectacles, subtle blazer and tie, calm thoughtful expression, soft notebook or clipboard hint.",
  "wry": "A wry, amused character portrait: Think Jack Black, slight smirk, raised eyebrow, relaxed posture, simple casual jacket, playful but kind vibe.",
  "storyteller": "A warm storyteller character portrait: think Morgan Freeman, elderly male, black skin, gentle smile, soft scarf or cardigan, cozy book tucked under arm, reassuring and grounded.",
  "sage": "An ancient reflective sage portrait: Think Confucius, serene face, simple robe, small wooden staff or beads, quiet wisdom, minimal detail.",
  "anchor": "A folksy moral anchor portrait: Think Uncle Jesse, warm friendly face, denim/utility shirt hint, steady eyes, subtle badge/heart pin suggesting values and loyalty.",
  "optimist": "A wide-eyed optimist portrait: Think Elf, bright gentle smile, open expression, simple star or sun motif, uplifting and tender.",
  "humanist": "A curious analytical humanist portrait: Think Data (star trek), thoughtful gaze, sci-fi uniform, warm intelligence.",
  "philosopher": "A disciplined rational philosopher portrait: Think Spock, A calm logical sci-fi thinker with pointed ears and raised eyebrow, simplified and non-realistic. restraint.",
  "therapist": "A gentle practical therapist portrait: woman, kind face, simple sweater, small clipboard or tea mug, supportive and approachable.",
  "bard": "A mythic bard portrait: inspired eyes, simple cloak, small lute/harp hint, heroic-story vibe without magic.",
  "detective": "A noir detective portrait: fedora silhouette, trench coat, subtle magnifying glass or streetlamp motif, cool but empathetic.",
  "skeptic": "A compassionate skeptic portrait: neutral calm face, simple hoodie/jacket, small checklist icon, grounded and realistic.",
  "stoic": "A stoic mentor portrait: steady eyes, minimal expression, simple laurel or column motif, calm strength.",
  "surreal": "A playful surrealist portrait:  Think Mystic / Psychic, quirky hair/hat, abstract shapes floating behind, curious grin, whimsical but kind.",
  "coach": "A protective coach portrait: confident smile, athletic jacket, subtle whistle or shield motif, encouraging and no-nonsense.",
  "seer": "A symbolic seer portrait: Think Tara Parker, bright red curly hair, calm mysterious eyes, scarf and crystal-orb silhouette, swirling symbol shapes—mystique without prophecy.",
  "rogue": "A charming rogue portrait: Think Charming pirate, playful grin, red bandana on head under a pirate hat, long dreadlocks, colorful feathery beaded earrings, mischievous but insightful.",
  "relativist": "A friendly relativist scientist portrait: wild, fluffy white hair, thoughtful eyes, warm mischievous smile. Wears a simple sweater or tweed jacket. Slightly whimsical, intellectual vibe. Chalkboard-style abstract equations and symbols faintly in the background. Not a real person. No text. Soft lighting, painterly illustration style.",
  "inner_guide": "A compassionate inner guide portrait: kind, reassuring woman with soft eyes and a gentle smile, cozy sweater or shawl, warm ambient light, subtle dreamy background gradient, calm and nurturing vibe. Not a real person. No text, no logos. Painterly illustration style.",
    "pattern_seer": "An intuitive pattern seer portrait: Perceptive woman with serene expression, subtle freckles or unique facial detail, simple elegant clothing, faint geometric motifs and flowing symbolic shapes in the background, quiet and insightful mood. Not a real person. No text. Painterly illustration style.",
    "truth_teller": "A sharp-tongued truth teller portrait: confident woman with a wry half-smile, direct gaze, modern minimalist outfit (dark jacket or blazer), slightly dramatic lighting, clean background with subtle edgy texture. Not a real person. No text. Painterly illustration style.",
    "somatic": "A somatic listener portrait: grounded woman with calm presence, relaxed posture, natural look, earth-tone clothing, soft daylight, subtle abstract shapes suggesting breath and body sensation in the background. Not a real person. No text. Painterly illustration style.",
    "mythic": "A myth-weaving storyteller portrait: expressive woman with warm, luminous eyes, slightly dramatic but gentle presence, flowing hair or scarf, soft star-like bokeh and faint mythic symbols in the background, cinematic yet grounded mood. Not a real person. No text. Painterly illustration style.",
    "skeptic": "A rational skeptic portrait: practical, friendly woman with an intelligent, reassuring expression, simple shirt and blazer, clean background with faint diagram-like lines or subtle chalkboard texture (no readable text). Not a real person. No text. Painterly illustration style.",
    "muse": "A playful creative muse portrait: bright, upbeat woman with a joyful smile, colorful but soft outfit, whimsical dreamy background with gentle shapes and sparkles (no text), light and imaginative mood. Not a real person. No text. Painterly illustration style.",
    "default": "A softly lit silhouette, gender neutral"
}


# Optional: custom per-icon subject overrides by slug/icon_key
SUBJECT_OVERRIDES = {
    # "spock_like": "A calm logical sci-fi thinker with pointed ears and raised eyebrow, simplified and non-realistic.",
}

def parse_list(s: str | None):
    if not s:
        return None
    return {x.strip() for x in s.split(",") if x.strip()}


def icon_subject(it: Interpreter) -> str:
    key = (it.icon_key or "").strip()
    if key and key in SUBJECT_OVERRIDES:
        return SUBJECT_OVERRIDES[key]
    if it.slug in SUBJECT_OVERRIDES:
        return SUBJECT_OVERRIDES[it.slug]
    if key in ICON_SUBJECTS:
        return ICON_SUBJECTS[key]
    return f"A friendly character portrait representing: {it.name}. Calm, approachable expression."



def main(force=False, slugs=None, keys=None):
    with app.app_context():
        rows = (Interpreter.query
                .filter_by(is_enabled=True)
                .order_by(Interpreter.sort_order.asc(), Interpreter.id.asc())
                .all())

        slugs = set(slugs or [])
        keys = set(keys or [])
        
        for it in rows:
            if slugs and it.slug not in slugs:
                continue
            if keys and (it.icon_key or "").strip() not in keys:
                continue
        
        # for it in rows:
            subject = icon_subject(it)

            prompt = f"{STYLE}\n\nSubject: {subject}\n"

            # Small hash to change filename when prompt changes
            h = hashlib.sha256(prompt.encode("utf-8")).hexdigest()[:10]
            filename = f"{it.slug}-{h}.png"

            out_path  = OUT_DIR / filename

            # if not force and it.icon_file and out_path.exists():
            #     print(f"SKIP {it.slug}: already has icon_file={it.icon_file}")
            #     continue

            if not force and it.icon_file:
                print(f"SKIP {it.slug}: already has icon_file={it.icon_file}")
                continue


            resp = client.images.generate(
                model=MODEL,
                prompt=prompt,
                n=1,
                size=SIZE,
            )

            img_bytes = base64.b64decode(resp.data[0].b64_json)
            out_path.write_bytes(img_bytes)

            # tile

            # DB update (matches your columns)
            #it.icon_file = filename
            #it.icon_tile_file = filename
            #it.icon_prompt = prompt
            #db.session.commit()

            print(f"OK   {it.slug}: {filename}")

if __name__ == "__main__":
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("--force", action="store_true", help="regenerate even if icon exists")
    p.add_argument("--slugs", help="comma-separated slugs, e.g. warm_storyteller,noir_detective")
    p.add_argument("--keys", help="comma-separated icon_keys, e.g. detective,sage")
    args = p.parse_args()

    main(
        force=args.force,
        slugs=parse_list(args.slugs),
        keys=parse_list(args.keys),
    )

