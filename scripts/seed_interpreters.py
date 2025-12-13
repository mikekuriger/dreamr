import json
from pathlib import Path
from yourapp import create_app, db
from yourapp.models import Interpreter

SEED_PATH = Path("interpreters.v1.json")

def upsert_interpreter(item: dict):
    slug = item["id"]
    interp = Interpreter.query.filter_by(slug=slug).one_or_none()
    if not interp:
        interp = Interpreter(slug=slug)
        db.session.add(interp)

    interp.name = item["name"]
    interp.category = item.get("category", "grounded")
    interp.sort_order = int(item.get("sort_order", 100))
    interp.is_enabled = bool(item.get("is_enabled", True))
    interp.access_tier = item.get("access_tier", "pro")
    interp.unlock_rule = item.get("unlock_rule")

    interp.core_voice = item["core_voice"]
    interp.interpretive_lens = item["interpretive_lens"]
    interp.emotional_stance = item["emotional_stance"]
    interp.prompt_extra = item.get("prompt_extra")

    interp.card_blurb = item.get("card_blurb", "")
    interp.card_bullets = item.get("card_bullets", [])
    interp.tone_examples = item.get("tone_examples", [])

    interp.icon_key = item.get("icon_key", slug)

def main():
    app = create_app()
    with app.app_context():
        data = json.loads(SEED_PATH.read_text(encoding="utf-8"))
        items = data["items"]

        for item in items:
            upsert_interpreter(item)

        db.session.commit()
        print(f"Seeded {len(items)} interpreters from {SEED_PATH}")

if __name__ == "__main__":
    main()
