#!/usr/bin/env python3
"""Placeholder art for the living village (LIVING_WORLD L1, 2026-09-26).

Stand-ins, per CLAUDE.md's graphics rules: they live in assets/placeholder/generated/
and are deleted in the commit that wires the commissioned replacement.

  python3 tools/make_village_sprites.py <repo root>

Villagers are recolours of assets/official/characters/Human_Outcast.png (so they share
its silhouette, scale and outline); the field and the body are drawn here in the same
flat pixel style as the other generated site sprites (128x128, dark outline, snow base).
"""
import colorsys, random, sys
from PIL import Image, ImageDraw

root = sys.argv[1] if len(sys.argv) > 1 else "."
OUT = root + "/assets/placeholder/generated/"
SRC = root + "/assets/official/characters/Human_Outcast.png"
OUTLINE = (40, 30, 30, 255)

def recolour(im, hue, sat_mul, val_mul):
    """Shift the cloth (the brown, low-saturation mid tones) to a new hue; skin and
    outline are left alone."""
    out = im.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            skin = 0.02 < h < 0.11 and s > 0.35 and v > 0.45
            if skin or v < 0.18:
                continue
            nr, ng, nb = colorsys.hsv_to_rgb(hue, min(1.0, max(s, 0.25) * sat_mul), min(1.0, v * val_mul))
            px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)
    return out

def snow_base(d, cx, cy, w, h):
    d.polygon([(cx - w, cy), (cx, cy - h), (cx + w, cy), (cx, cy + h)], fill=(232, 238, 246, 255), outline=(150, 160, 175, 255))
    d.polygon([(cx - w, cy), (cx, cy + h), (cx, cy + h + 5), (cx - w, cy + 5)], fill=(120, 90, 70, 255))
    d.polygon([(cx + w, cy), (cx, cy + h), (cx, cy + h + 5), (cx + w, cy + 5)], fill=(95, 70, 55, 255))

def field(cut):
    im = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy, w, h = 64, 88, 56, 26
    snow_base(d, cx, cy, w, h)
    def iso(a, b):
        return (cx + (a + b) * w / 2, cy + (b - a) * h / 2)
    rnd = random.Random(7)
    rows = [-0.75, -0.45, -0.15, 0.15, 0.45, 0.75]
    for b in rows:
        d.line([iso(-0.85, b), iso(0.85, b)], fill=(150, 120, 90, 255), width=3)
    # back rows first, so nearer stalks overlap farther ones
    stalks = []
    for b in rows:
        a = -0.8
        while a <= 0.8:
            stalks.append(iso(a, b))
            a += 0.2
    stalks.sort(key=lambda p: p[1])
    for bx, by in stalks:
        if cut:
            d.line([(bx, by), (bx, by - 3)], fill=(190, 160, 90, 255), width=2)
        else:
            hgt = rnd.randint(12, 18)
            top = bx + rnd.randint(-1, 1)
            d.line([(bx, by), (top, by - hgt)], fill=(120, 95, 40, 255), width=2)
            d.ellipse([top - 2, by - hgt - 5, top + 2, by - hgt + 1], fill=(222, 186, 88, 255), outline=(150, 115, 40, 255))
    return im

def body(src, gone):
    im = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([18, 70, 110, 108], fill=(226, 232, 240, 255), outline=(170, 178, 190, 255))
    d.ellipse([46, 82, 78, 98], fill=(150, 30, 30, 255) if not gone else (170, 120, 120, 255))
    if not gone:
        fig = recolour(src, 0.08, 0.6, 0.55).rotate(90, expand=True)
        bbox = fig.getbbox()
        fig = fig.crop(bbox)
        fig = fig.resize((int(fig.width * 0.62), int(fig.height * 0.62)), Image.NEAREST)
        im.alpha_composite(fig, (64 - fig.width // 2, 90 - fig.height // 2 - 4))
    else:
        for x in range(30, 100, 9):
            d.line([(x, 84), (x + 6, 92)], fill=(185, 190, 200, 255), width=2)
    return im

def spear(im):
    d = ImageDraw.Draw(im)
    d.line([(96, 20), (96, 118)], fill=OUTLINE, width=4)
    d.line([(96, 22), (96, 116)], fill=(130, 100, 70, 255), width=2)
    d.polygon([(96, 6), (91, 22), (101, 22)], fill=(200, 205, 215, 255), outline=OUTLINE)
    return im

def guild():
    """The Adventurers' Guild: a long timber hall, a board by the door, a hanging
    shield. Bigger than a house on purpose -- it is the one building on the road."""
    im = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([10, 108, 118, 124], fill=(226, 232, 240, 255))
    # walls
    d.rectangle([18, 62, 110, 114], fill=(150, 108, 70, 255), outline=OUTLINE, width=2)
    for x in range(26, 110, 14):
        d.line([(x, 64), (x, 112)], fill=(110, 78, 50, 255), width=2)
    d.line([(20, 88), (108, 88)], fill=(110, 78, 50, 255), width=3)
    # roof
    d.polygon([(10, 64), (64, 26), (118, 64)], fill=(120, 48, 40, 255), outline=OUTLINE)
    d.polygon([(22, 58), (64, 32), (106, 58)], fill=(150, 62, 50, 255))
    d.polygon([(30, 60), (64, 38), (98, 60), (64, 44)], fill=(236, 240, 246, 255))  # snow on the ridge
    # door
    d.rectangle([56, 90, 72, 114], fill=(70, 46, 30, 255), outline=OUTLINE)
    # the board
    d.rectangle([80, 94, 100, 110], fill=(190, 150, 100, 255), outline=OUTLINE)
    for y in (98, 102, 106):
        d.line([(83, y), (97, y)], fill=(245, 240, 225, 255), width=2)
    # the shield over the door
    d.polygon([(56, 70), (72, 70), (72, 78), (64, 86), (56, 78)], fill=(60, 90, 160, 255), outline=OUTLINE)
    d.line([(64, 71), (64, 84)], fill=(230, 200, 90, 255), width=2)
    return im

src = Image.open(SRC).convert("RGBA")
guild().save(OUT + "guild_hall.png")
recolour(src, 0.58, 0.9, 1.05).save(OUT + "villager_peasant.png")
spear(recolour(src, 0.99, 1.4, 1.0)).save(OUT + "villager_guard.png")
field(False).save(OUT + "crop_field.png")
field(True).save(OUT + "crop_field_cut.png")
body(src, False).save(OUT + "villager_body.png")
body(src, True).save(OUT + "villager_body_gone.png")
print("wrote 7 sprites to", OUT)
