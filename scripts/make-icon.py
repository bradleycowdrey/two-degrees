"""Draws the Two Degrees app icon and writes every size the apps use.

The mark: two degree rings, cream (the larger unit) and a sunset coral-to-pink (the other), on the app's
dusk sky, with a soft sunset glow along the horizon, matching the city pages since 2.1. Run from the
repository root: python3 scripts/make-icon.py  (needs Pillow). Writes:
  Resources/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png  1024, full-bleed, no alpha (iPhone, iPad)
  Resources/AppIcon.png, docs/icon.png                           1024, macOS-style rounded tile with shadow
  android/app/src/main/res/mipmap-*/ic_launcher(_round).png      legacy launcher sizes
  android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png, ic_launcher_background.png, app_mark.png
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
S = 4  # supersampling


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def sky(size):
    """The dusk sky: slate blue at the top to deep navy, with a warm glow at the horizon."""
    top, mid, bottom = (98, 122, 152), (44, 54, 74), (22, 25, 34)
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        c = lerp(top, mid, t / 0.62) if t < 0.62 else lerp(mid, bottom, (t - 0.62) / 0.38)
        for x in range(size):
            px[x, y] = c
    # Sunset glow low on the horizon: coral fading up into the sky.
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    cx, cy, r = size * 0.5, size * 1.16, size * 0.42
    g.ellipse([cx - r * 1.6, cy - r, cx + r * 1.6, cy + r], fill=(255, 136, 92, 88))
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.09))
    img = img.convert("RGBA")
    img.alpha_composite(glow)
    return img


def ring_mask(size, cx, cy, outer, width):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.ellipse([cx - outer, cy - outer, cx + outer, cy + outer], fill=255)
    inner = outer - width
    d.ellipse([cx - inner, cy - inner, cx + inner, cy + inner], fill=0)
    return m


def gradient(size, c1, c2):
    """A diagonal gradient from top-left (c1) to bottom-right (c2)."""
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            px[x, y] = lerp(c1, c2, (x + y) / (2 * (size - 1))) + (255,)
    return img


def mark(size, scale=1.0, offset=(0.0, 0.0)):
    """The two rings on transparency, at `scale` of the tile, centred plus an offset (fractions of size)."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ox, oy = size * offset[0], size * offset[1]
    big = (size * (0.5 - 0.125 * scale) + ox, size * (0.5 - 0.075 * scale) + oy, size * 0.205 * scale, size * 0.086 * scale)
    small = (size * (0.5 + 0.164 * scale) + ox, size * (0.5 + 0.12 * scale) + oy, size * 0.15 * scale, size * 0.075 * scale)
    # Soft shadow under both rings for a little depth.
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for cx, cy, outer, width in (big, small):
        m = ring_mask(size, cx, cy + size * 0.012 * scale, outer, width)
        shadow.paste((10, 14, 22, 150), (0, 0), m)
    layer.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(size * 0.018 * scale)))
    cream = Image.new("RGBA", (size, size), (255, 241, 229, 255))
    layer.paste(cream, (0, 0), ring_mask(size, *big))
    coral = gradient(size, (247, 168, 112), (226, 74, 122))   # sunset coral to the app's pink
    layer.paste(coral, (0, 0), ring_mask(size, *small))
    return layer


def full_bleed(size):
    img = sky(size * S)
    img.alpha_composite(mark(size * S))
    return img.resize((size, size), Image.LANCZOS).convert("RGB")


def rounded_tile(size, inset=0.098, radius=0.225, shadow=True):
    """A rounded tile with margins and a soft shadow, as macOS draws app icons."""
    big = size * S
    tile = big - 2 * int(big * inset)
    face = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    body = sky(tile)
    body.alpha_composite(mark(tile))
    m = Image.new("L", (tile, tile), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, tile - 1, tile - 1], radius=int(tile * radius), fill=255)
    x = int(big * inset)
    if shadow:
        sh = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        sm = Image.new("L", (big, big), 0)
        ImageDraw.Draw(sm).rounded_rectangle([x, x + int(big * 0.012), x + tile, x + tile + int(big * 0.012)], radius=int(tile * radius), fill=110)
        sh.putalpha(sm.filter(ImageFilter.GaussianBlur(big * 0.014)))
        face.alpha_composite(sh)
    face.paste(body, (x, x), m)
    return face.resize((size, size), Image.LANCZOS)


def circle_tile(size):
    big = size * S
    body = sky(big)
    body.alpha_composite(mark(big))
    m = Image.new("L", (big, big), 0)
    ImageDraw.Draw(m).ellipse([0, 0, big - 1, big - 1], fill=255)
    out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    out.paste(body, (0, 0), m)
    return out.resize((size, size), Image.LANCZOS)


def save(img, *path):
    p = os.path.join(ROOT, *path)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p, optimize=True)
    print("wrote", os.path.relpath(p, ROOT), img.size)


def main():
    save(full_bleed(1024), "Resources", "iOS", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
    mac = rounded_tile(1024)
    save(mac, "Resources", "AppIcon.png")
    save(mac, "docs", "icon.png")
    res = ("android", "app", "src", "main", "res")
    for folder, px in (("mipmap-mdpi", 48), ("mipmap-hdpi", 72), ("mipmap-xhdpi", 96), ("mipmap-xxhdpi", 144), ("mipmap-xxxhdpi", 192)):
        save(rounded_tile(px, inset=0.0, radius=0.2, shadow=False), *res, folder, "ic_launcher.png")
        save(circle_tile(px), *res, folder, "ic_launcher_round.png")
    # Adaptive icon (Android 8+): the rings inside the 66% safe zone, over the sky.
    fg = Image.new("RGBA", (432 * S, 432 * S), (0, 0, 0, 0))
    fg.alpha_composite(mark(432 * S, scale=0.66))
    save(fg.resize((432, 432), Image.LANCZOS), *res, "drawable-nodpi", "ic_launcher_foreground.png")
    save(sky(432 * S).resize((432, 432), Image.LANCZOS).convert("RGB"), *res, "drawable-nodpi", "ic_launcher_background.png")
    save(rounded_tile(256, inset=0.0, radius=0.26, shadow=False), *res, "drawable-nodpi", "app_mark.png")


if __name__ == "__main__":
    main()
