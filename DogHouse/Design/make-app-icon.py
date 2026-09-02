#!/usr/bin/env python3
"""Regenerates DogHouse/Assets.xcassets/AppIcon.appiconset/AppIcon.png.

Orange plate with a darker rim, tan dog house, red chevron roof, dark arched
door. Drawn at 4x and downsampled. Needs Pillow:  python3 -m pip install Pillow

    python3 Design/make-app-icon.py
"""
import pathlib
from PIL import Image, ImageDraw, ImageFilter

OUT = pathlib.Path(__file__).resolve().parent.parent / "DogHouse" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
K = 4; W = 1024 * K
def p(v): return int(round(v * K))

img = Image.new("RGB", (W, W), (226, 130, 30))                      # rim
inner = Image.new("RGB", (W, W)); di = ImageDraw.Draw(inner)
top, bot = (248, 168, 52), (240, 146, 36)                           # plate gradient
for y in range(W):
    t = y / W
    di.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(mask).rounded_rectangle([p(30), p(30), W - p(30), W - p(30)], radius=p(200), fill=255)
img.paste(inner, (0, 0), mask)

cx, cy = 512, 540
def sc(x, y, s=1.12): return (cx + (x - cx) * s, cy + (y - cy) * s)
sh = Image.new("L", (W, W), 0)
ImageDraw.Draw(sh).ellipse([p(235), p(815), p(789), p(905)], fill=110)
img.paste((190, 105, 25), (0, 0), sh.filter(ImageFilter.GaussianBlur(p(22))))
d = ImageDraw.Draw(img)

bx0, by0 = sc(300, 430); bx1, by1 = sc(724, 830)                    # body
d.rectangle([p(bx0), p(by0), p(bx1), p(by1)], fill=(201, 143, 78))
d.rectangle([p(512), p(by0), p(bx1), p(by1)], fill=(186, 128, 66))
d.rectangle([p(bx0), p(by0), p(bx1), p(sc(0, 500)[1])], fill=(178, 122, 62))
d.rectangle([p(512), p(by0), p(bx1), p(sc(0, 500)[1])], fill=(164, 112, 56))
# Gable: the body's top follows the roof's underside, so no plate shows through
# the chevron. Split at the ridge to keep the left/right shading.
gx, gy = sc(512, 336)
d.polygon([(p(bx0), p(by0)), (p(gx), p(gy)), (p(gx), p(by0))], fill=(178, 122, 62))
d.polygon([(p(gx), p(gy)), (p(bx1), p(by0)), (p(gx), p(by0))], fill=(164, 112, 56))

def poly(pts, fill):
    d.polygon([(p(x), p(y)) for x, y in (sc(*q) for q in pts)], fill=fill)
apex = (512, 215); l, r = 150, 874; eave, thick = 510, 95           # roof
poly([(l, eave), apex, (r, eave), (r - 40, eave + 55), (512, apex[1] + thick), (l + 40, eave + 55)], (224, 72, 62))
poly([(l + 40, eave + 55), (512, apex[1] + thick), (r - 40, eave + 55),
      (r - 58, eave + 78), (512, apex[1] + thick + 28), (l + 58, eave + 78)], (196, 56, 50))
poly([(l + 6, eave - 2), apex, (r - 6, eave - 2), (r - 14, eave + 8), (512, apex[1] + 14), (l + 14, eave + 8)], (232, 92, 80))

dx0, dtop = sc(428, 560); dx1, _ = sc(596, 560); rad = (dx1 - dx0) / 2   # door
d.ellipse([p(dx0), p(dtop), p(dx1), p(dtop + 2 * rad)], fill=(58, 34, 20))
d.rectangle([p(dx0), p(dtop + rad), p(dx1), p(by1)], fill=(58, 34, 20))
d.arc([p(dx0), p(dtop), p(dx1), p(dtop + 2 * rad)], start=180, end=300, fill=(40, 22, 12), width=p(6))

img.resize((1024, 1024), Image.LANCZOS).save(OUT, optimize=True)
print("wrote", OUT)
