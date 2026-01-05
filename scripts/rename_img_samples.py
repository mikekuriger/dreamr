#!/usr/bin/env python3
import argparse
import re
import shutil
from pathlib import Path
from typing import Dict, List, Tuple, Optional

# sample_017_ancient-fresco-inspired-painting-earthy-tones.png
SAMPLE_RE = re.compile(r"^sample_\d{3}_(?P<style>.+)\.(?P<ext>png|jpg|jpeg|webp)$", re.I)

def norm_key(s: str) -> str:
    """
    Normalize so folder names like:
      ancient-fresco-inspired-painting_earthy-tones
    match filenames like:
      ancient-fresco-inspired-painting-earthy-tones

    We treat '_' and '-' as equivalent separators by converting both to spaces,
    then collapsing whitespace, then joining with a single '-'.
    """
    s = s.strip().lower()
    s = s.replace("_", " ").replace("-", " ")
    s = re.sub(r"\s+", " ", s).strip()
    return s.replace(" ", "-")

def build_style_dir_index(root: Path, style_dirs: List[str]) -> Dict[str, Path]:
    """
    Map normalized style key -> absolute destination directory Path
    """
    idx: Dict[str, Path] = {}
    for rel in style_dirs:
        d = (root / rel).resolve()
        if not d.is_dir():
            raise SystemExit(f"Missing directory: {d}")
        key = norm_key(d.name)
        # For nested style dir (e.g. Whimsical_surreal/whimsical-children-s-book/whimsical-children-s-book-art-dreamy-proportions),
        # the style is the last component, so d.name is correct.
        idx[key] = d
    return idx

def best_match(style_key: str, idx: Dict[str, Path]) -> Optional[Path]:
    """
    Best-effort match:
    - exact normalized key
    - prefix match either direction (handles truncations like gentle-distortio vs gentle-distortion)
    """
    if style_key in idx:
        return idx[style_key]

    # prefix matches
    candidates: List[Tuple[int, Path]] = []
    for k, p in idx.items():
        if k.startswith(style_key) or style_key.startswith(k):
            score = min(len(k), len(style_key))  # longer shared prefix wins
            candidates.append((score, p))

    if not candidates:
        return None

    candidates.sort(key=lambda t: t[0], reverse=True)
    return candidates[0][1]

def main() -> int:
    ap = argparse.ArgumentParser(
        description="Move sample_XXX_<style>.png into style folders and rename to <subject>.png"
    )
    ap.add_argument("--root", default=".", help="Root directory that contains your tone folders")
    ap.add_argument("--samples", default=".", help="Directory containing sample_*.png files")
    ap.add_argument("--subject", default="sample", help="Output filename stem (default: sample -> sample.png)")
    ap.add_argument("--dry-run", action="store_true", help="Print actions, do not move/rename")
    ap.add_argument("--overwrite", action="store_true", help="Overwrite existing <subject>.png if present")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    samples_dir = Path(args.samples).resolve()
    subject_name = args.subject.strip()
    if not subject_name:
        raise SystemExit("--subject cannot be empty")

    # Your canonical destination folders (as provided)
    STYLE_DIRS = [
        "Ancient_mythic/mythological-fantasy",
        "Ancient_mythic/ancient-fresco-inspired-painting_earthy-tones",
        "Ancient_mythic/epic-mythic-oil-painting_timeless-atmosphere",
        "Ancient_mythic/mythological-fantasy-illustration_classical-composition",
        "Elegant_ornate/art-nouveau-or-oil-painting",
        "Elegant_ornate/art-nouveau-inspired-illustration_flowing-lines",
        "Elegant_ornate/decorative-fantasy-illustration_intricate-detail",
        "Elegant_ornate/ornate-oil-painting_rich-textures_classical-elegance",
        "Epic_heroic/cinematic-fantasy-concept-art_dramatic-lighting_painterly",
        "Epic_heroic/illustrated-epic-fantasy-poster_dynamic-composition",
        "Epic_heroic/mythic-oil-painting_heroic-scale_rich-color-depth",
        "Futuristic_uncanny/cyberdream-retrofuturism",
        "Futuristic_uncanny/cyberdream-illustration_neon-accents_soft-focus",
        "Futuristic_uncanny/retrofuturistic-concept-art_uncanny-atmosphere",
        "Futuristic_uncanny/surreal-sci-fi-painting_liminal-spaces",
        "Nightmarish_dark/dark-fairytale",
        "Nightmarish_dark/dark-fairytale-illustration_shadow-heavy_painterly",
        "Nightmarish_dark/moody-cinematic-illustration_dream-horror-atmosphere",
        "Nightmarish_dark/surreal-nightmare-art_distorted-forms_low-light",
        "Peaceful_Gentle/watercolor-fantasy",
        "Peaceful_Gentle/soft-watercolor-illustration_pastel-tones_gentle-lighting",
        "Peaceful_Gentle/dreamlike-oil-painting_muted-colors_smooth-brush-strokes",
        "Peaceful_Gentle/minimalist-fantasy-illustration_airy-composition_warm-glow",
        "Romantic_nostalgic/impressionist-art",
        "Romantic_nostalgic/impressionist-painting_warm-light_nostalgic-mood",
        "Romantic_nostalgic/soft-focus-oil-painting_romantic-atmosphere",
        "Romantic_nostalgic/vintage-storybook-illustration_faded-tones",
        "Whimsical_surreal/artistic-vivid-style",
        "Whimsical_surreal/whimsical-children-s-book",
        "Whimsical_surreal/whimsical-children-s-book/whimsical-children-s-book-art-dreamy-proportions",
        "Whimsical_surreal/painterly-surreal-fantasy_floating-elements_gentle-distortion",
        "Whimsical_surreal/surreal-storybook-illustration_imaginative-shapes_soft-color",
        "Just_For_Fun/concept-art",
        "Just_For_Fun/steampunk",
        "Just_For_Fun/photo-realistic",
    ]

    idx = build_style_dir_index(root, STYLE_DIRS)

    moved = 0
    missing = 0

    for p in sorted(samples_dir.iterdir()):
        if not p.is_file():
            continue

        m = SAMPLE_RE.match(p.name)
        if not m:
            continue

        style_from_file = m.group("style")
        ext = m.group("ext").lower()

        style_key = norm_key(style_from_file)
        dest_dir = best_match(style_key, idx)

        if dest_dir is None:
            print(f"NO MATCH: {p.name} (style={style_from_file})")
            missing += 1
            continue

        dest_path = dest_dir / f"{subject_name}.{ext}"

        if dest_path.exists() and not args.overwrite:
            print(f"SKIP (exists): {dest_path}")
            continue

        action = f"{p} -> {dest_path}"
        if args.dry_run:
            print(f"DRYRUN: {action}")
        else:
            dest_dir.mkdir(parents=True, exist_ok=True)
            if args.overwrite and dest_path.exists():
                dest_path.unlink()
            shutil.move(str(p), str(dest_path))
            print(f"MOVED: {action}")
        moved += 1

    print(f"Done. moved={moved} no_match={missing}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

