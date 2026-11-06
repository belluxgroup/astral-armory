"""Turn a white-on-black AI texture into a white RGBA texture whose alpha is the luminance.

Usage: python tools/prep_hero.py <src.png> <dst.png> [size]
Roblox tints white textures through Color, so only the alpha carries the shape.
"""
import sys
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
size = int(sys.argv[3]) if len(sys.argv) > 3 else 512
lum = Image.open(src).convert("L").resize((size, size), Image.LANCZOS)
lum = lum.point(lambda v: 0 if v < 10 else v)  # kill JPEG-ish noise in the black
out = Image.new("RGBA", lum.size, (255, 255, 255, 0))
out.putalpha(lum)
out.save(dst, optimize=True)
print(dst, out.size)
