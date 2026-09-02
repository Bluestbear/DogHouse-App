#!/usr/bin/env python3
"""Regenerates the app icon as a close-up of the app's own Golden dog.

Same palette and proportions as AvatarView draws in the app, cropped tight so
the face fills the tile: fur ground, big eyes, cream muzzle, dark nose, smile,
and the collar with its tag running off the bottom edge.

Drawn at 4x and downsampled. Needs Pillow:  python3 -m pip install Pillow

    python3 Design/make-app-icon-dog.py

The alternative dog-house design lives in make-app-icon.py; both write the
same file, so run whichever one you want installed.
"""
import pathlib
from PIL import Image, ImageDraw, ImageFilter

OUT = pathlib.Path(__file__).resolve().parent.parent / "DogHouse" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
K = 4; W = 1024 * K
def p(v): return int(round(v * K))

# Palette lifted from DogAvatar "Golden" + AvatarView's fixed colours.
FUR       = (209, 161, 64)
FUR_LIT   = (224, 178, 82)
FUR_DARK  = (173, 128, 41)
MUZZLE    = (242, 214, 153)
DARK      = (31, 20, 20)
COLLAR    = (107, 61, 18)
TAG       = (245, 209, 46)
TAG_DARK  = (214, 176, 30)

img = Image.new("RGB", (W, W), FUR)
d = ImageDraw.Draw(img)

# Fur ground: light falls from the top left, so the face has some roundness.
grad = Image.new("RGB", (W, W)); dg = ImageDraw.Draw(grad)
for y in range(W):
    t = y / W
    dg.line([(0, y), (W, y)], fill=tuple(int(FUR_LIT[i] + (FUR[i] - FUR_LIT[i]) * t) for i in range(3)))
img.paste(grad, (0, 0))
d = ImageDraw.Draw(img)

def ellipse(cx, cy, w, h, fill):
    d.ellipse([p(cx - w / 2), p(cy - h / 2), p(cx + w / 2), p(cy + h / 2)], fill=fill)

def qcurve(a, c, b, steps=160):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        pts.append((p(u * u * a[0] + 2 * u * t * c[0] + t * t * b[0]),
                    p(u * u * a[1] + 2 * u * t * c[1] + t * t * b[1])))
    return pts

def stroke(pts, width, fill):
    d.line(pts, fill=fill, width=p(width), joint="curve")
    r = p(width) // 2                      # round caps
    for x, y in (pts[0], pts[-1]):
        d.ellipse([x - r, y - r, x + r, y + r], fill=fill)

# Ears: cut by the top corners, a touch darker so they read against the head.
for sign in (-1, 1):
    ear = Image.new("RGBA", (p(560), p(560)), (0, 0, 0, 0))
    ImageDraw.Draw(ear).ellipse([p(165), p(120), p(395), p(455)], fill=FUR_DARK + (255,))
    ear = ear.rotate(-18 * sign, resample=Image.BICUBIC, center=(p(280), p(280)))
    img.paste(ear, (p(512 + sign * 455 - 280), p(-205)), ear)
d = ImageDraw.Draw(img)

# Muzzle behind the nose and mouth.
ellipse(512, 690, 610, 470, MUZZLE)

# Eyes.
for cx in (302, 722):
    ellipse(cx, 322, 268, 268, (255, 255, 255))
    ellipse(cx, 330, 150, 150, DARK)
    ellipse(cx + 34, 298, 52, 52, (255, 255, 255))

# Nose, sitting on the top of the muzzle.
ellipse(512, 520, 250, 165, DARK)
ellipse(486, 486, 70, 40, (72, 52, 52))          # faint sheen

# Smile: one smooth curve, matching the avatar's happy mouth.
stroke(qcurve((338, 686), (512, 896), (686, 686)), 30, DARK)

# Collar across the bottom, dipping to a tag that runs off the edge.
stroke(qcurve((40, 890), (512, 1046), (984, 890)), 62, COLLAR)
ellipse(512, 1000, 172, 172, TAG_DARK)
ellipse(512, 994, 140, 140, TAG)

img.resize((1024, 1024), Image.LANCZOS).save(OUT, optimize=True)
print("wrote", OUT)
