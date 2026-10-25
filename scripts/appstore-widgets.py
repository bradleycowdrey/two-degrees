"""App Store picture of the widgets: the rendered Home Screen and Lock Screen widgets (from the iPhone
self-test) laid out on a sky at the 6.9-inch iPhone size, 1320 x 2868.
Usage: python3 scripts/appstore-widgets.py <dir with widget-*.png> <out.png>"""
import sys, glob, os
from PIL import Image, ImageDraw, ImageFont

src, out = sys.argv[1], sys.argv[2]
W, H = 1320, 2868
img = Image.new("RGB", (W, H))
d = ImageDraw.Draw(img)
top, bottom = (61, 116, 176), (28, 58, 94)
for y in range(H):
    t = y / H
    d.line([(0, y), (W, y)], fill=tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3)))

def font(size):
    for f in ["/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]:
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()

def centred(text, y, size, fill=(255, 255, 255)):
    f = font(size); w = d.textlength(text, font=f); d.text(((W - w) / 2, y), text, font=f, fill=fill)

centred("Widgets in °F and °C", 170, 92)
centred("Home Screen and Lock Screen", 290, 56, (225, 232, 240))

def pick(name):
    files = sorted(glob.glob(os.path.join(src, f"widget-*-{name}.png")))
    return Image.open(files[0]).convert("RGBA") if files else None

def rounded(im, r):
    mask = Image.new("L", im.size, 0); ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.size[0], im.size[1]], r, fill=255)
    im.putalpha(mask); return im

def place(im, x, y, scale, r):
    im = im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS)
    img.paste(rounded(im, r), (int(x), int(y)), rounded(im.copy(), r))
    return im.height

y = 460
large = pick("large")
if large:
    s = (W - 160) / large.width
    y += place(large, 80, y, s, int(44 * s)) + 60
small, medium = pick("small"), pick("medium")
if small:
    s = (W - 160) / medium.width if medium else 2
    h = place(small, 80, y, s, int(44 * s))
    y += h + 60
rect, circ, inline = pick("lock-rectangular"), pick("lock-circular"), pick("lock-inline")
if rect:
    s = 2.2
    place(rect, 80, y, s, 20)
    if circ:
        place(circ, 80 + rect.width * s + 50, y, s, int(circ.width * s / 2))
    y += rect.height * s + 50
if inline:
    place(inline, 80, y, 2.2, 20)
img.save(out)
print("wrote", out)
