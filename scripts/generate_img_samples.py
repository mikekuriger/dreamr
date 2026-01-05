#!/usr/bin/env python3
import argparse
import base64
import json
import re
import time
import logging
import os

from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

from openai import OpenAI
from prompts import IMG_STYLE, CATEGORY_PROMPTS

logger = logging.getLogger("image_sample")
logger.setLevel(logging.INFO)
logger.handlers.clear()

log_dir = "/home/mk7193/dreamr"
os.makedirs(log_dir, exist_ok=True)
file_handler = logging.FileHandler(os.path.join(log_dir, "image_sample.log"))
file_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s"))
logger.addHandler(file_handler)


def slugify(s: str, max_len: int = 60) -> str:
    s = s.lower().strip()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    s = re.sub(r"-{2,}", "-", s).strip("-")
    return (s[:max_len].strip("-")) or "style"


def generate_image_prompt(
    client: OpenAI,
    dream: str,
    style: str,
    quality: str,
    model: str,
    retries: int = 3,
) -> str:
    base_prompt = CATEGORY_PROMPTS["image_free"] if quality == "low" else CATEGORY_PROMPTS["image"]

    full_prompt = (
        f"{base_prompt}\n\n"
        f"Render the image in this style: {style}\n\n"
        f"Dream:\n{dream}\n"
    )

    last_err = None
    for attempt in range(retries + 1):
        try:
            resp = client.chat.completions.create(
                model=model,
                messages=[{"role": "user", "content": full_prompt}],
            )
            return resp.choices[0].message.content.strip()
        except Exception as e:
            last_err = e
            if attempt >= retries:
                raise
            time.sleep(2 ** attempt)
    raise last_err  # pragma: no cover


def generate_image_bytes(
    client: OpenAI,
    image_prompt: str,
    model: str,
    size: str,
    retries: int = 3,
) -> bytes:
    last_err = None
    for attempt in range(retries + 1):
        try:
            resp = client.images.generate(
                model=model,
                prompt=image_prompt,
                n=1,
                size=size,
            )
            # GPT image models always return base64-encoded images. :contentReference[oaicite:1]{index=1}
            b64 = resp.data[0].b64_json
            return base64.b64decode(b64)
        except Exception as e:
            last_err = e
            if attempt >= retries:
                raise
            time.sleep(2 ** attempt)
    raise last_err  # pragma: no cover


def run_one_style(index: int, style: str, args) -> dict:
    client = OpenAI()  # create per-thread client

    style_tag = slugify(style)
    base_name = f"{args.prefix}_{index:03d}_{style_tag}"

    print(f"[{index}] style={style_tag} generating prompt...", flush=True)

    image_prompt = generate_image_prompt(
        client=client,
        dream=args.dream,
        style=style,
        quality=args.quality,
        model=args.prompt_model,
    )

    print(f"[{index}] generating image...", flush=True)

    img_bytes = generate_image_bytes(
        client=client,
        image_prompt=image_prompt,
        model=args.image_model,
        size=args.size,
    )

    png_path = Path(args.outdir) / f"{base_name}.png"
    txt_path = Path(args.outdir) / f"{base_name}.prompt.txt"

    png_path.write_bytes(img_bytes)
    txt_path.write_text(image_prompt + "\n", encoding="utf-8")

    print(f"[{index}] wrote {png_path}", flush=True)

    return {
        "index": index,
        "style": style,
        "quality": args.quality,
        "prompt_model": args.prompt_model,
        "image_model": args.image_model,
        "size": args.size,
        "prompt_file": str(txt_path),
        "image_file": str(png_path),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate image samples across styles (dream -> image prompt -> image).")
    ap.add_argument("--dream", required=True, help="Dream text input.")
    ap.add_argument("--workers", type=int, default=4, help="Parallel jobs (API calls).")
    ap.add_argument("--quality", choices=["low", "high"], default="high")
    ap.add_argument("--outdir", default="image_samples")
    ap.add_argument("--prefix", default="sample")
    ap.add_argument("--size", default="1024x1024")
    ap.add_argument("--prompt-model", default="gpt-4o", help="Text model used to generate the image prompt.")
    ap.add_argument("--image-model", default="gpt-image-1.5", help="Image model.")
    args = ap.parse_args()

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    
    styles = list(IMG_STYLE)
    if not isinstance(IMG_STYLE, list):
        styles = sorted(styles)
    
    manifest = []
    failures = []
    
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futures = []
        for i, style in enumerate(styles, start=1):
            futures.append(ex.submit(run_one_style, i, style, args))
    
        for fut in as_completed(futures):
            try:
                manifest.append(fut.result())
            except Exception as e:
                failures.append(str(e))
                print(f"ERROR: {e}", flush=True)
    
    manifest.sort(key=lambda x: x["index"])
    
    (outdir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    
    if failures:
        (outdir / "errors.txt").write_text("\n".join(failures) + "\n", encoding="utf-8")
        return 1
    
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
