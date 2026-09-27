"""Cut the commissioned UI kit into the runtime pieces `scripts/ui/UiKit.gd` uses.

    python tools/make_ui_kit.py

Reads the masters in assets/official/_originals/UI/ (never edited) and writes
downscaled, ready-to-draw PNGs to assets/official/ui/. Re-run it after the
masters change, then re-open Godot so it re-imports them.

The masters were generated on a red key and cleaned by tools/clean_red_chroma.py
(the four source_*.png beside them are the raw generations).

Why pieces are composited, not just cropped: the button and popup art carry a
crest in the middle of their top edge. A plain nine-slice stretches that crest
with the edge, so the edges here are rebuilt from a plain stretch of border and
the popup's crest is kept as its own image, drawn on top by UiKit. The numbers
printed at the end are the margins UiKit.gd's constants must match.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/official/_originals/UI"
OUT = ROOT / "assets/official/ui"

# The panel's inside colour: HudStyle.BG at 96% so the world shows a little.
FILL = (13, 11, 18, 245)


def load(name: str) -> Image.Image:
    return Image.open(SRC / name).convert("RGBA")


def scale(im: Image.Image, s: float) -> Image.Image:
    return im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)


def hstack(*parts: Image.Image) -> Image.Image:
    h = max(p.height for p in parts)
    out = Image.new("RGBA", (sum(p.width for p in parts), h), (0, 0, 0, 0))
    x = 0
    for p in parts:
        out.alpha_composite(p, (x, 0))
        x += p.width
    return out


def vstack(*parts: Image.Image) -> Image.Image:
    w = max(p.width for p in parts)
    out = Image.new("RGBA", (w, sum(p.height for p in parts)), (0, 0, 0, 0))
    y = 0
    for p in parts:
        out.alpha_composite(p, (0, y))
        y += p.height
    return out


def tile_h(strip: Image.Image, times: int) -> Image.Image:
    return hstack(*([strip] * times))


def fill_inside(im: Image.Image, seed: tuple[int, int]) -> Image.Image:
    """Paint the transparent hole a frame encloses (the region connected to `seed`)."""
    a = np.array(im)
    hole = a[..., 3] < 40
    lab, _ = ndimage.label(hole)
    region = lab == lab[seed[1], seed[0]]
    # Grow one pixel under the frame's soft inner edge so no seam shows.
    region = ndimage.binary_dilation(region, iterations=2) & (a[..., 3] < 250)
    under = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ua = np.array(under)
    ua[region] = FILL
    under = Image.fromarray(ua, "RGBA")
    under.alpha_composite(im)
    return under


def darken(im: Image.Image, k: float, desat: float = 0.0) -> Image.Image:
    a = np.array(im).astype(np.float32)
    rgb = a[..., :3]
    if desat > 0:
        grey = rgb.mean(axis=2, keepdims=True)
        rgb = rgb * (1 - desat) + grey * desat
    a[..., :3] = np.clip(rgb * k, 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def save(im: Image.Image, name: str) -> None:
    im.save(OUT / name)
    print(f"  {name:28s} {im.width}x{im.height}")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    controls = load("Necromancer_UI_Controls_4x4.png")
    print("Wrote:")

    # ---- Buttons: the gem-crested plate (normal) and the violet plate (hover).
    # Left cap + a plain stretch of top/bottom border + right cap; the crest is dropped.
    def plate(box, cap, strip, rows, height):
        x, y, w, h = box
        p = controls.crop((x, y, x + w, y + h))
        left = p.crop((0, rows[0], cap, rows[1]))
        right = p.crop((w - cap, rows[0], w, rows[1]))
        mid = tile_h(p.crop((strip[0], rows[0], strip[1], rows[1])), 4)
        out = hstack(left, mid, right)
        return scale(out, height / out.height), height / out.height

    normal, s0 = plate((43, 116, 351, 177), 82, (82, 97), (28, 177), 40)
    hover, s1 = plate((430, 127, 343, 166), 70, (70, 100), (25, 166), 40)
    save(normal, "UI_Button.png")
    save(hover, "UI_Button_Hover.png")
    save(darken(hover, 0.8), "UI_Button_Pressed.png")
    save(darken(normal, 0.6, 0.6), "UI_Button_Disabled.png")
    print(f"    button caps {round(82 * s0)} / {round(70 * s1)} px, height 40")

    # ---- The popup frame, as a nine-slice with a filled inside, plus its crest.
    popup = load("Necromancer_UI_Popup_Frame.png")
    s = 0.2
    rows_top = (120, 310)
    rows_bottom = (870, 1060)
    cols_corner = (30, 290)
    cols_strip = (350, 500)
    rows_side = (372, 398)
    tl = popup.crop((cols_corner[0], rows_top[0], cols_corner[1], rows_top[1]))
    top = popup.crop((cols_strip[0], rows_top[0], cols_strip[1], rows_top[1]))
    bl = popup.crop((cols_corner[0], rows_bottom[0], cols_corner[1], rows_bottom[1]))
    bottom = popup.crop((cols_strip[0], rows_bottom[0], cols_strip[1], rows_bottom[1]))
    side = popup.crop((cols_corner[0], rows_side[0], cols_corner[1], rows_side[1]))
    mirror = Image.FLIP_LEFT_RIGHT
    band_top = hstack(tl, top, tl.transpose(mirror))
    band_mid = hstack(side, Image.new("RGBA", (top.width, side.height), (0, 0, 0, 0)), side.transpose(mirror))
    band_bottom = hstack(bl, bottom, bl.transpose(mirror))
    frame = vstack(band_top, band_mid, band_bottom)
    frame = fill_inside(frame, (frame.width // 2, band_top.height + side.height // 2))
    save(scale(frame, s), "UI_Panel.png")
    corner = cols_corner[1] - cols_corner[0]
    print(f"    panel margins: sides {round(corner * s)}, top {round(band_top.height * s)}, "
          f"bottom {round(band_bottom.height * s)}; inside starts {round((172 - 30) * s)} in, "
          f"{round((258 - 120) * s)} down, {round((1060 - 925) * s)} up")
    crest_box = (520, 20, 930, 280)
    crest = popup.crop(crest_box)
    save(scale(crest, s), "UI_Panel_Crest.png")
    print(f"    crest sits {round((crest_box[1] - rows_top[0]) * s)} px from the panel's top")

    # ---- The title frame: the whole main-menu frame, inside filled.
    title = load("Necromancer_UI_Main_Menu_Frame.png")
    title = fill_inside(title, (title.width // 2, title.height // 2))
    save(scale(title, 1400 / title.width), "UI_Title_Frame.png")

    # ---- Divider, bar, checkboxes.
    def piece(box):
        x, y, w, h = box
        return controls.crop((x, y, x + w, y + h))

    save(scale(piece((720, 778, 239, 46)), 0.5), "UI_Divider.png")
    back = piece((34, 764, 301, 84))
    fill = piece((385, 767, 290, 81)).crop((39, 24, 251, 56))
    sb = 24 / back.height
    save(scale(back, sb), "UI_Bar_Back.png")
    save(scale(fill, sb), "UI_Bar_Fill.png")
    print(f"    bar: caps {round(70 * sb)} px; inside x {round(37 * sb)}..{round(262 * sb)}, "
          f"y {round(22 * sb)}..{round(60 * sb)} of {round(back.width * sb)}x24")
    off = piece((104, 991, 153, 155))
    on = piece((406, 991, 154, 155)).resize(off.size, Image.LANCZOS)
    save(scale(off, 22 / off.height), "UI_Check_Off.png")
    save(scale(on, 22 / off.height), "UI_Check_On.png")
    save(darken(scale(off, 22 / off.height), 0.55, 0.6), "UI_Check_Off_Disabled.png")
    save(darken(scale(on, 22 / off.height), 0.55, 0.6), "UI_Check_On_Disabled.png")


if __name__ == "__main__":
    main()
