#!/usr/bin/env python3
import sys
from pathlib import Path

# Add project root to PYTHONPATH
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import json
import argparse
from pathlib import Path

# Import your single-file Flask app globals
from app import app, db  # app.py at repo root

# Interpreter must be importable; simplest is defining it in app.py initially.
from app import Interpreter


def upsert(interp_item: dict):
    slug = interp_item["id"]  # stable key

    row = Interpreter.query.filter_by(slug=slug).one_or_none()
    if row is None:
        row = Interpreter(slug=slug)
        db.session.add(row)

    # Core
    row.name = interp_item["name"]
    row.category = interp_item.get("category", "grounded")
    row.sort_order = int(interp_item.get("sort_order", 100))
    row.is_enabled = bool(interp_item.get("is_enabled", True))

    # Access control
    row.access_tier = interp_item.get("access_tier", "pro")  # free|pro
    row.unlock_rule = interp_item.get("unlock_rule")  # optional JSON

    # Persona prompt fields
    row.core_voice = interp_item["core_voice"]
    row.interpretive_lens = interp_item["interpretive_lens"]
    row.emotional_stance = interp_item["emotional_stance"]
    row.prompt_extra = interp_item.get("prompt_extra")

    # UI card fields
    row.card_blurb = interp_item.get("card_blurb", "")
    row.card_bullets = interp_item.get("card_bullets", [])
    row.tone_examples = interp_item.get("tone_examples", [])

    # Icon metadata (icon generation script will fill icon_file/icon_tile_file/icon_prompt)
    row.icon_key = interp_item.get("icon_key", slug)
    row.icon_subject = interp_item.get("icon_subject")  # strongly recommended


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", default="scripts/interpreters.v1.json", help="Seed JSON path")
    args = parser.parse_args()

    seed_path = Path(args.file)
    if not seed_path.exists():
        raise SystemExit(f"Seed file not found: {seed_path}")

    data = json.loads(seed_path.read_text(encoding="utf-8"))
    items = data.get("items", [])
    if not items:
        raise SystemExit("No items found in seed JSON under key: items")

    with app.app_context():
        for item in items:
            upsert(item)
        db.session.commit()

    print(f"Seeded/updated {len(items)} interpreters from {seed_path}")


if __name__ == "__main__":
    main()
