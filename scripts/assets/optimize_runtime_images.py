"""Convert bundled UI raster assets to real WebP files (requires Pillow).

Run from any directory: python scripts/assets/optimize_runtime_images.py --apply
Original artwork remains available in Git history; platform/email assets are excluded.
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[2]
APPS = ("frontend/user-web", "frontend/admin-web", "mobile/user-app", "frontend/shared")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    summary = []
    for app in APPS:
        base = ROOT / app
        assets = base / ("assets" if app.startswith("mobile/") or app == "frontend/shared" else "public/assets")
        sources = sorted(p for p in assets.rglob("*") if p.suffix.lower() in (".png", ".jpg", ".jpeg", ".ico"))
        before = sum(p.stat().st_size for p in assets.rglob("*") if p.is_file())
        changes = []
        replacements = {}
        for source in sources:
            relative = source.relative_to(assets).as_posix()
            target = source.with_suffix(".webp")
            # Small PNG favicon remains for browser/bookmark compatibility.
            if relative == "logo-mark.png" and not app.startswith("mobile/") and source.stat().st_size < 15000:
                continue
            if args.apply:
                if not target.exists():
                    with Image.open(source) as original:
                        image = ImageOps.exif_transpose(original).convert("RGBA")
                        icon = "icons/" in relative or relative == "logo-mark.png"
                        image.thumbnail((384, 384) if relative == "logo-mark.png" else (192, 192) if icon else (1200, 1200), Image.Resampling.LANCZOS)
                        if icon:
                            image.save(target, "WEBP", lossless=True, method=6)
                        else:
                            image.save(target, "WEBP", quality=82, method=6)
                if relative == "logo-mark.png" and not app.startswith("mobile/"):
                    with Image.open(source) as original:
                        image = original.convert("RGBA")
                        image.thumbnail((64, 64), Image.Resampling.LANCZOS)
                        image.save(source, "PNG", optimize=True)
                else:
                    source.unlink()
            replacements["assets/" + relative] = "assets/" + target.relative_to(assets).as_posix()
            changes.append({"source": relative, "target": target.relative_to(assets).as_posix()})
        if args.apply:
            folders = (ROOT / "frontend/user-web/src", ROOT / "frontend/admin-web/src") if app == "frontend/shared" else (base / "src", base / "lib", base / "test")
            for folder in folders:
                if not folder.exists():
                    continue
                for path in folder.rglob("*"):
                    if path.suffix not in (".ts", ".html", ".scss", ".dart"):
                        continue
                    text = path.read_text(encoding="utf-8-sig")
                    result = text
                    for old, new in replacements.items():
                        if path.name == "index.html" and old == "assets/logo-mark.png":
                            continue
                        result = result.replace(old, new)
                        if path.name == "app_icons.dart":
                            result = result.replace("}" + Path(old).name + "'", "}" + Path(new).name + "'")
                    if result != text:
                        path.write_text(result, encoding="utf-8")
        after = sum(p.stat().st_size for p in assets.rglob("*") if p.is_file())
        summary.append({"app": app, "before_bytes": before, "after_bytes": after, "assets": changes})
    output = json.dumps(summary, indent=2, ensure_ascii=False)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(output, encoding="utf-8")
    print(json.dumps([{k: v for k, v in row.items() if k != "assets"} | {"converted": len(row["assets"])} for row in summary], indent=2))


if __name__ == "__main__":
    main()
