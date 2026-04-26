"""
One-off source generator for flutter_launcher_icons: full-bleed 1024 icon + EKG-only foreground.
Run: python tool/generate_app_icon_sources.py
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
# Top-left #0066CC, bottom-right #00B4D8
C_TOP_LEFT = (0, 102, 204)
C_BOTTOM_RIGHT = (0, 180, 216)


def diagonal_gradient() -> Image.Image:
    img = Image.new("RGB", (SIZE, SIZE))
    px = img.load()
    w1 = SIZE - 1
    h1 = SIZE - 1
    for y in range(SIZE):
        for x in range(SIZE):
            t = 0.5 * (x / w1 + y / h1)
            t = max(0.0, min(1.0, t))
            r = int(C_TOP_LEFT[0] + t * (C_BOTTOM_RIGHT[0] - C_TOP_LEFT[0]))
            g = int(C_TOP_LEFT[1] + t * (C_BOTTOM_RIGHT[1] - C_TOP_LEFT[1]))
            b = int(C_TOP_LEFT[2] + t * (C_BOTTOM_RIGHT[2] - C_TOP_LEFT[2]))
            px[x, y] = (r, g, b)
    return img


def ekg_norm_points() -> list[tuple[float, float]]:
    """Classic ECG: flat baseline, QRS (small dip, tall R, S), return to flat."""
    return [
        (0.10, 0.50),
        (0.28, 0.50),
        (0.30, 0.50),  # Q: slight down
        (0.32, 0.47),
        (0.35, 0.28),  # R: sharp up
        (0.39, 0.56),  # S: down
        (0.42, 0.50),  # back to line
        (0.90, 0.50),  # flat
    ]


def draw_ekg(
    target: Image.Image,
    color: tuple[int, ...],
    line_px: int,
) -> None:
    pts = ekg_norm_points()
    w, h = target.size
    pixel_pts = [
        (int(x * w), int(y * h)) for x, y in pts
    ]
    draw = ImageDraw.Draw(target)
    draw.line(
        pixel_pts,
        fill=color,
        width=line_px,
        joint="curve",  # type: ignore[arg-type]
    )


def make_full_icon() -> Image.Image:
    # Full-bleed square; iOS/Android apply platform rounding. RGB (no alpha) for App Store rules.
    out = diagonal_gradient()
    draw_ekg(out, (255, 255, 255), line_px=24)
    return out


def make_adaptive_foreground() -> Image.Image:
    # Transparent; white EKG only. Same geometry as full icon.
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw_ekg(out, (255, 255, 255, 255), line_px=24)
    return out


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    assets = root / "assets" / "icons"
    assets.mkdir(parents=True, exist_ok=True)
    full = make_full_icon()
    full_path = assets / "app_icon.png"
    full.save(full_path, "PNG")
    fg = make_adaptive_foreground()
    fg_path = assets / "app_icon_foreground.png"
    fg.save(fg_path, "PNG")
    print(f"Wrote {full_path}")
    print(f"Wrote {fg_path}")


if __name__ == "__main__":
    main()
