"""Crop the wordmark logo's transparent/white padding so it fills its
asset bounds. Run once after saving a fresh source image to
assets/images/arl_logo.png; output is written to
assets/images/arl_logo_wordmark.png and used by ArlAppBar.
"""

import os
import sys

try:
    from PIL import Image
    import numpy as np
except ImportError:
    print("install deps: py -m pip install pillow numpy", file=sys.stderr)
    sys.exit(1)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "images", "arl_logo.png")
OUT = os.path.join(ROOT, "assets", "images", "arl_logo_wordmark.png")

img = Image.open(SRC).convert("RGBA")
arr = np.array(img)
r, g, b, a = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2], arr[:, :, 3]
is_background = ((r > 240) & (g > 240) & (b > 240)) | (a < 16)
is_content = ~is_background
ys, xs = np.where(is_content)
if len(xs) == 0:
    raise SystemExit("no content found in source image")
left, right = int(xs.min()), int(xs.max())
top, bottom = int(ys.min()), int(ys.max())

pad_h = int((right - left) * 0.04)
pad_v = int((bottom - top) * 0.10)
left = max(0, left - pad_h)
right = min(img.width - 1, right + pad_h)
top = max(0, top - pad_v)
bottom = min(img.height - 1, bottom + pad_v)

cropped = img.crop((left, top, right + 1, bottom + 1))
cropped.save(OUT, "PNG", optimize=True)
print(f"wrote {OUT} {cropped.size}")
