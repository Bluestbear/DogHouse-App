#!/usr/bin/env python3
"""Regenerates the app icon as an extreme close-up of the app's own Golden dog.

Same palette AvatarView uses, cropped so tight that only the inner half of
each eye sits inside the frame, the nose falls just below centre, and the
ears, collar and tag are all outside the tile.

Writes two files:
  * the icon itself - square and full-bleed, because iOS applies its own mask
  * Design/icon-preview.png - the same art behind the iOS squircle, large and
    at Home Screen size, so the shape can be judged before building

Drawn at 4x and downsampled. Needs Pillow:  python3 -m pip install Pillow

    python3 Design/make-app-icon-dog.py

The alternative dog-house design lives in make-app-icon.py; both write the
same icon file, so run whichever one should be installed.
"""
import pathlib
from PIL import Image, ImageDraw, ImageFilter

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent / "DogHouse" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
PREVIEW = HERE / "icon-preview.png"

K = 4; W = 1024 * K
def p(v): return int(round(v * K))

# Palette lifted from DogAvatar "Golden" + AvatarView's fixed colours.
FUR      = (209, 161, 64)
FUR_LIT  = (226, 180, 84)
MUZZLE   = (242, 214, 153)
DARK     = (31, 20, 20)
SHEEN    = (74, 54, 54)

img = Image.new("RGB", (W, W), FUR)
dg = ImageDraw.Draw(img)
for y in range(W):                                  # light falls from above
    t = y / W
    dg.line([(0, y), (W, y)], fill=tuple(int(FUR_LIT[i] + (FUR[i] - FUR_LIT[i]) * t) for i in range(3)))
d = ImageDraw.Draw(img)

def ellipse(cx, cy, w, h, fill):
    d.ellipse([p(cx - w / 2), p(cy - h / 2), p(cx + w / 2), p(cy + h / 2)], fill=fill)

def qcurve(a, c, b, steps=200):
    out = []
    for i in range(steps + 1):
        t = i / steps; u = 1 - t
        out.append((p(u * u * a[0] + 2 * u * t * c[0] + t * t * b[0]),
                    p(u * u * a[1] + 2 * u * t * c[1] + t * t * b[1])))
    return out

def stroke(pts, width, fill):
    d.line(pts, fill=fill, width=p(width), joint="curve")
    r = p(width) // 2
    for x, y in (pts[0], pts[-1]):
        d.ellipse([x - r, y - r, x + r, y + r], fill=fill)

# Muzzle: so close now that it runs off the bottom and both sides.
ellipse(512, 880, 1180, 900, MUZZLE)

# Eyes: centred exactly on the side edges, so each shows its inner half.
# The highlight is mirrored on the right eye to keep it inside the frame.
for cx, shine in ((0, 46), (1024, -46)):
    ellipse(cx, 332, 430, 430, (255, 255, 255))
    ellipse(cx, 345, 240, 240, DARK)
    ellipse(cx + shine, 300, 84, 84, (255, 255, 255))

# Nose, just below centre.
ellipse(512, 612, 430, 290, DARK)
ellipse(468, 552, 120, 66, SHEEN)                   # faint sheen

# Smile, sitting clear of the corner curve so the mask cannot clip it.
stroke(qcurve((228, 820), (512, 1140), (796, 820)), 48, DARK)

icon = img.resize((1024, 1024), Image.LANCZOS)
icon.save(OUT, optimize=True)
print("wrote", OUT)

# ---- Preview: the same art behind the iOS squircle -------------------------

def squircle_mask(size, n=5.0, ss=4):
    """Superellipse mask; n=5 is a close match for the iOS icon shape."""
    S = size * ss
    m = Image.new("L", (S, S), 0)
    px = m.load()
    half = S / 2
    for y in range(S):
        v = abs((y + 0.5 - half) / half) ** n
        if v > 1:
            continue
        # solve |u|^n <= 1 - v for the row's half-width
        u = (1 - v) ** (1 / n)
        x0 = int(round(half - u * half)); x1 = int(round(half + u * half))
        for x in range(max(x0, 0), min(x1, S)):
            px[x, y] = 255
    return m.resize((size, size), Image.LANCZOS)

def masked(size):
    art = icon.resize((size, size), Image.LANCZOS).convert("RGBA")
    art.putalpha(squircle_mask(size))
    return art

BG = (238, 236, 233)
pv = Image.new("RGB", (1180, 760), BG)
big, small = masked(560), masked(132)

for art, xy in ((big, (90, 100)), (small, (860, 262))):
    shadow = Image.new("RGBA", pv.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 70), (xy[0], xy[1] + max(6, art.width // 40)), art.split()[3])
    pv = Image.alpha_composite(pv.convert("RGBA"),
                               shadow.filter(ImageFilter.GaussianBlur(art.width // 28))).convert("RGB")
    pv.paste(art, xy, art)

dp = ImageDraw.Draw(pv)
dp.text((92, 690), "1024 px", fill=(120, 116, 110))
dp.text((862, 430), "Home Screen size", fill=(120, 116, 110))
pv.save(PREVIEW, optimize=True)
print("wrote", PREVIEW)
