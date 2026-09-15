#!/usr/bin/env python3
"""Write LaunchHead.imageset from a raw AvatarView render.

Takes the sRGB PNG produced by render-launch-head.swift, applies the same
Display P3 re-encoding as make-app-icon-dog.py (the launch snapshot displays
sRGB values as if they were P3; see LAUNCH_COMPENSATE_SNAPSHOT_GAMUT there),
and writes DogHouse/Assets.xcassets/LaunchHead.imageset.

    python3 Design/compensate-launch-head.py <raw.png>
"""
import pathlib
import sys

from PIL import Image, ImageCms

HERE = pathlib.Path(__file__).resolve().parent
SRGB = pathlib.Path("/System/Library/ColorSync/Profiles/sRGB Profile.icc").read_bytes()


def snapshot_compensated(image):
    """Re-encode an sRGB image's colours as Display P3 numbers (alpha kept)."""
    p3 = ImageCms.getOpenProfile("/System/Library/ColorSync/Profiles/Display P3.icc")
    tf = ImageCms.buildTransform(ImageCms.createProfile("sRGB"), p3, "RGB", "RGB")
    if image.mode == "RGBA":
        rgb = ImageCms.applyTransform(image.convert("RGB"), tf)
        rgb.putalpha(image.getchannel("A"))
        return rgb
    return ImageCms.applyTransform(image.convert("RGB"), tf)


raw = Image.open(sys.argv[1])
assert raw.size == (1280, 1120), f"unexpected size {raw.size}"
d = HERE.parent / "DogHouse" / "Assets.xcassets" / "LaunchHead.imageset"
for old in d.glob("*.png"):
    old.unlink()
snapshot_compensated(raw).save(d / "LaunchHead.png", optimize=True, icc_profile=SRGB)
print("wrote", d / "LaunchHead.png")
