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
# Tag every PNG as sRGB. Without a profile the launch-screen renderer treats
# the launch images as wide-gamut and draws them more saturated than the
# SwiftUI redraw of the same colours, so the splash hand-off frame shifts.
SRGB = pathlib.Path("/System/Library/ColorSync/Profiles/sRGB Profile.icc").read_bytes()
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
icon.save(OUT, optimize=True, icc_profile=SRGB)
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
pv.save(PREVIEW, optimize=True, icc_profile=SRGB)
print("wrote", PREVIEW)

# ---- Launch screen art, for LaunchScreen.storyboard ------------------------
# The launch screen is Duolingo-style: the Welcome screen's gradient, the
# avatar's head (ears, face, collar and tag, drawn exactly as AvatarView draws
# the "Golden" dog) at about half the screen width in the centre, and the
# DogHouse wordmark near the bottom (rendered by render-launch-wordmark.swift).
# LaunchSplashView then shows the same head via AvatarView, blinks, and slides
# up. Two assets from here:
#   * LaunchFur   - 1px-wide vertical gradient, stretched full screen: the
#                   Welcome gradient (cozyOrange at 80% over white -> brown)
#   * LaunchHead  - transparent image of the head, spanning HEAD_BOX in the
#                   avatar's 80-unit space (its centre is at avatar (0, -7))
# Storyboard: head width = HEAD_WIDTH_FRACTION of the screen width, centred;
# LaunchSplashView derives the AvatarView size from the same numbers.
# The launch snapshot (everything the storyboard shows) is displayed with its
# sRGB values read as Display P3, i.e. more saturated than the same colours
# drawn by SwiftUI a frame later (measured on the iOS 26 simulator: fur
# (226,180,84) showed as (233,176,57)). So the launch PNGs are written with
# the Display P3 *encoding* of each colour, which then displays as the true
# sRGB colour and the hand-off frame no longer shifts. Verified on the
# simulator only; if a real device shows the launch screen washed out, set
# this False and compare on the device again.
LAUNCH_COMPENSATE_SNAPSHOT_GAMUT = True
GRAD_TOP    = (255, 163, 51)        # cozyOrange (255,140,0) at 0.8 over white
GRAD_BOTTOM = (139, 69, 19)         # dogHouseBrown
HEAD_BOX = (-32, -35, 32, 21)       # x0, y0, x1, y1 in avatar units
HEAD_PX_PER_UNIT = 20
HEAD_WIDTH_FRACTION = 0.545
# AvatarView "Golden" + its fixed colours
A_FUR    = (209, 161, 64)
A_MUZZLE = (242, 214, 153)
A_DARK   = (31, 20, 20)
A_BAND   = (107, 61, 18)
A_GEM    = (245, 209, 46)
A_GEM_EDGE = (56, 33, 5)

def snapshot_compensated(image):
    """Re-encode an sRGB image's colours as Display P3 numbers (alpha kept)."""
    from PIL import ImageCms
    p3 = ImageCms.getOpenProfile("/System/Library/ColorSync/Profiles/Display P3.icc")
    tf = ImageCms.buildTransform(ImageCms.createProfile("sRGB"), p3, "RGB", "RGB")
    if image.mode == "RGBA":
        rgb = ImageCms.applyTransform(image.convert("RGB"), tf)
        rgb.putalpha(image.getchannel("A"))
        return rgb
    return ImageCms.applyTransform(image.convert("RGB"), tf)

def write_imageset(name, image, scale=None):
    d = HERE.parent / "DogHouse" / "Assets.xcassets" / f"{name}.imageset"
    d.mkdir(exist_ok=True)
    fname = f"{name}@{scale}.png" if scale else f"{name}.png"
    for old in d.glob("*.png"):
        old.unlink()
    if LAUNCH_COMPENSATE_SNAPSHOT_GAMUT:
        image = snapshot_compensated(image)
    image.save(d / fname, optimize=True, icc_profile=SRGB)
    entry = '      "filename" : "%s",\n      "idiom" : "universal"' % fname
    if scale:
        entry += ',\n      "scale" : "%s"' % scale
    (d / "Contents.json").write_text(
        '{\n  "images" : [\n    {\n' + entry + '\n    }\n  ],\n'
        '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')
    print("wrote", d)

fur = Image.new("RGB", (1, 512))
for y in range(512):
    t = y / 511
    fur.putpixel((0, y), tuple(int(GRAD_TOP[i] + (GRAD_BOTTOM[i] - GRAD_TOP[i]) * t) for i in range(3)))
write_imageset("LaunchFur", fur)

# LaunchHead is no longer written here: the hand-drawn head had slightly
# different pupils/smile/tag than AvatarView and the face popped at the launch
# hand-off. It is now rendered from AvatarView itself — see
# render-launch-head.swift + compensate-launch-head.py. The drawing below is
# kept only because the app icon (drawn above) shares its helpers.
WRITE_LAUNCH_HEAD = False

import math
X0, Y0, X1, Y1 = HEAD_BOX
SS = 4                                          # supersample
HU = HEAD_PX_PER_UNIT * SS
head = Image.new("RGBA", ((X1 - X0) * HU, (Y1 - Y0) * HU), (0, 0, 0, 0))
hd = ImageDraw.Draw(head)
def hp(x, y): return ((x - X0) * HU, (y - Y0) * HU)
def hellipse(cx, cy, w, h, fill, outline=None, width=0):
    global head, hd
    box = [*hp(cx - w / 2, cy - h / 2), *hp(cx + w / 2, cy + h / 2)]
    if len(fill) == 4 and fill[3] < 255:          # translucent: composite a layer
        layer = Image.new("RGBA", head.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).ellipse(box, fill=fill)
        head = Image.alpha_composite(head, layer); hd = ImageDraw.Draw(head)
        return
    hd.ellipse(box, fill=fill, outline=outline, width=int(width * HU))
def hrot_ellipse(cx, cy, w, h, deg, fill):
    th = math.radians(deg); pts = []
    for i in range(180):
        a = 2 * math.pi * i / 180
        x, y = w / 2 * math.cos(a), h / 2 * math.sin(a)
        pts.append(hp(cx + x * math.cos(th) - y * math.sin(th), cy + x * math.sin(th) + y * math.cos(th)))
    hd.polygon(pts, fill=fill)
def hstroke(pts, width, fill):
    P = [hp(x, y) for x, y in pts]
    hd.line(P, fill=fill, width=int(width * HU), joint="curve")
    r = width * HU / 2
    for x, y in (P[0], P[-1]):
        hd.ellipse([x - r, y - r, x + r, y + r], fill=fill)
# Mirrors AvatarView (80-unit space, avatar centre at 0,0): ears, head, face, collar
hrot_ellipse(-21, -21, 20, 26, -6, A_FUR)
hrot_ellipse(21, -21, 20, 26, 6, A_FUR)
hellipse(0, -8, 50, 50, A_FUR)
hellipse(0, 2, 26, 20, A_MUZZLE)
for ex in (-16, 16):
    hellipse(ex, -15, 14, 14, (255, 255, 255))
    hellipse(ex, -15, 7, 7, A_DARK)
    hellipse(ex + 3, -18, 4, 4, (255, 255, 255, 191))
hellipse(0, -6, 9, 6, A_DARK)
mouth = [(8 * math.cos(math.radians(a)), 8 * math.sin(math.radians(a))) for a in range(0, 181, 4)]
hstroke(mouth, 1.5, A_DARK)
hstroke(qcurve((-17, 7), (0, 23), (17, 7)) and
        [((1 - t) ** 2 * -17 + t ** 2 * 17, (1 - t) ** 2 * 7 + 2 * (1 - t) * t * 23 + t ** 2 * 7)
         for t in [i / 100 for i in range(101)]], 3.5, A_BAND)
hellipse(0, 15, 9, 9, A_GEM, outline=A_GEM_EDGE, width=1.5)
hellipse(-1, 14, 3, 3, (255, 255, 255, 89))
head = head.resize(((X1 - X0) * HEAD_PX_PER_UNIT, (Y1 - Y0) * HEAD_PX_PER_UNIT), Image.LANCZOS)
if WRITE_LAUNCH_HEAD:
    write_imageset("LaunchHead", head)
    print(f"LaunchHead is {head.width}x{head.height}; storyboard width multiplier = "
          f"{HEAD_WIDTH_FRACTION}, aspect = {head.height}:{head.width}")
else:
    print("LaunchHead not written (rendered from AvatarView; see render-launch-head.swift)")
