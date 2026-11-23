"""Draws the Two Degrees app icon and writes every size the apps use.

The mark: two degree rings, a cream one (the larger unit) and a smaller coral-to-pink one (the other), on a
diagonal dusk-blue sky that is light at the top left, in the same build as the Cowdrey One family: one flat,
bold mark with generous margins, one soft shadow, light from the top. The pair fills about 67% of the canvas
and is optically centred. Run from the repository root: python3 scripts/make-icon.py  (needs Pillow and
numpy). Writes:
  Resources/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png  1024, full-bleed, opaque RGB, square corners
                                                                 (iPhone, iPad; the OS masks the corners)
  Resources/AppIcon.png, docs/icon.png                           1024, macOS tile: 824 body, 185 radius, shadow
  Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png        the macOS tile at all 10 Mac sizes, 16 to 1024
  android/app/src/main/res/mipmap-*/ic_launcher(_round).png      legacy launcher sizes
  android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png, ic_launcher_background.png, app_mark.png
"""
import os
import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
S = 4  # supersampling

# The sky: three stops along the 135-degree diagonal, top left to bottom right.
SKY = ((0.00, (0x6A, 0x9E, 0xE6)), (0.55, (0x3A, 0x5F, 0xC0)), (1.00, (0x1F, 0x2E, 0x78)))
TOP_LIGHT = 0.07                                     # white at y=0, gone by 45% of the height
CREAM = ((0xFF, 0xF4, 0xEA), (0xFF, 0xEE, 0xDF))     # top to bottom of the big ring (effectively flat)
CORAL = ((0xFF, 0x8A, 0x78), (0xF2, 0x60, 0x7A))     # top to bottom of the small ring
SHADOW = ((0x0B, 0x14, 0x40), 0.22, 0.008, 0.014)    # colour, opacity, y offset, blur (fractions of size)

# Rings as (centre x, centre y, outer radius, stroke), fractions of the canvas before optical centring.
BIG = (0.405, 0.405, 0.235, 0.094)
SMALL = (0.700, 0.700, 0.145, 0.067)
OPTICAL_PULL = 0.35  # move the bounding-box centre this far toward the ink centroid


def _srgb_to_linear(c):
    c = c / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _linear_to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055) * 255.0


def _to_image(rgb):
    """Float sRGB (0..255) to 8-bit, with a little noise so the gradients do not band."""
    noise = np.random.default_rng(2).uniform(-0.5, 0.5, rgb.shape[:2])[..., None]
    return Image.fromarray(np.clip(np.round(rgb + noise), 0, 255).astype(np.uint8), "RGB")


def sky(size):
    """The dusk sky: a diagonal three-stop gradient mixed in linear light, plus a faint top light."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64) / max(size - 1, 1)
    t = (xx + yy) / 2
    stops = [(p, _srgb_to_linear(np.array(c, float))) for p, c in SKY]
    lin = np.zeros((size, size, 3))
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        sel = (t >= p0) & (t <= p1)
        u = (t[sel] - p0) / (p1 - p0)
        u = u * u * (3 - 2 * u)  # smoothstep between stops
        lin[sel] = c0 + (c1 - c0) * u[:, None]
    rgb = _linear_to_srgb(lin)
    a = (np.clip(1 - yy / 0.45, 0, 1) * TOP_LIGHT)[..., None]
    rgb = rgb * (1 - a) + 255.0 * a
    return _to_image(rgb).convert("RGBA")


def layout():
    """The two rings, shifted together so the pair is optically centred on the canvas."""
    (bx, by, br, bw), (sx, sy, sr, sw) = BIG, SMALL
    x0, x1 = min(bx - br, sx - sr), max(bx + br, sx + sr)
    y0, y1 = min(by - br, sy - sr), max(by + br, sy + sr)
    a1, a2 = br ** 2 - (br - bw) ** 2, sr ** 2 - (sr - sw) ** 2
    cx, cy = (bx * a1 + sx * a2) / (a1 + a2), (by * a1 + sy * a2) / (a1 + a2)
    ox = (x0 + x1) / 2 + (cx - (x0 + x1) / 2) * OPTICAL_PULL
    oy = (y0 + y1) / 2 + (cy - (y0 + y1) / 2) * OPTICAL_PULL
    dx, dy = 0.5 - ox, 0.5 - oy
    return (bx + dx, by + dy, br, bw), (sx + dx, sy + dy, sr, sw)


def ring_mask(size, cx, cy, outer, width):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.ellipse([cx - outer, cy - outer, cx + outer, cy + outer], fill=255)
    inner = outer - width
    d.ellipse([cx - inner, cy - inner, cx + inner, cy + inner], fill=0)
    return m


def vertical(size, c1, c2, top, bottom):
    """A fill that runs from c1 at y=top to c2 at y=bottom (pixels)."""
    y = np.clip((np.arange(size) - top) / max(bottom - top, 1), 0, 1)[:, None, None]
    col = np.array(c1, float) + (np.array(c2, float) - np.array(c1, float)) * y
    return _to_image(np.broadcast_to(col, (size, size, 3)).copy()).convert("RGBA")


def mark(size, scale=1.0, offset=(0.0, 0.0)):
    """The two rings on transparency, at `scale` of the tile, centred plus an offset (fractions of size)."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rings = []
    for cx, cy, r, w in layout():
        rings.append((size * (0.5 + (cx - 0.5) * scale + offset[0]), size * (0.5 + (cy - 0.5) * scale + offset[1]),
                      size * r * scale, size * w * scale))
    ink = Image.new("L", (size, size), 0)
    for ring in rings:
        ink = ImageChops.lighter(ink, ring_mask(size, *ring))
    # One soft, cool shadow under both rings.
    colour, alpha, dy, blur = SHADOW
    sa = ImageChops.offset(ink, 0, int(round(size * dy * scale))).filter(ImageFilter.GaussianBlur(size * blur * scale))
    shadow = Image.new("RGBA", (size, size), colour + (0,))
    shadow.putalpha(sa.point(lambda v: int(v * alpha)))
    layer.alpha_composite(shadow)
    for (cx, cy, r, w), (c1, c2) in zip(rings, (CREAM, CORAL)):
        layer.paste(vertical(size, c1, c2, cy - r, cy + r), (0, 0), ring_mask(size, cx, cy, r, w))
    return layer


def art(size):
    img = sky(size)
    img.alpha_composite(mark(size))
    return img


def full_bleed(size):
    return art(size * S).resize((size, size), Image.LANCZOS).convert("RGB")


def rounded_tile(size, inset=100 / 1024, radius=185 / 824, shadow=True):
    """A rounded tile with margins, a soft shadow and a faint top edge, per Apple's macOS icon template."""
    big = size * S
    x = int(round(big * inset))
    tile = big - 2 * x
    face = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    body = art(tile)
    r = int(round(tile * radius))
    m = Image.new("L", (tile, tile), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, tile - 1, tile - 1], radius=r, fill=255)
    if shadow:
        # Black at 30%, 12 px down and 28 px of blur at 1024.
        sm = Image.new("L", (big, big), 0)
        dy = int(round(big * 12 / 1024))
        ImageDraw.Draw(sm).rounded_rectangle([x, x + dy, x + tile, x + tile + dy], radius=r, fill=int(255 * 0.30))
        sh = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        sh.putalpha(sm.filter(ImageFilter.GaussianBlur(big * 14 / 1024)))
        face.alpha_composite(sh)
        # 1 px white inner edge at 12%, top half only.
        edge = Image.new("L", (tile, tile), 0)
        ImageDraw.Draw(edge).rounded_rectangle([0, 0, tile - 1, tile - 1], radius=r, outline=int(255 * 0.12),
                                               width=max(1, int(round(big / 1024))))
        edge.paste(0, (0, tile // 2, tile, tile))
        body.alpha_composite(Image.merge("RGBA", (Image.new("L", body.size, 255),) * 3 + (edge,)))
    face.paste(body, (x, x), m)
    return face.resize((size, size), Image.LANCZOS)


def circle_tile(size):
    big = size * S
    body = art(big)
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
    # Mac asset catalog: each size drawn from the vector at its own size, so small ones stay sharp.
    for pt in (16, 32, 128, 256, 512):
        save(rounded_tile(pt), "Resources", "Assets.xcassets", "AppIcon.appiconset", "icon_%dx%d.png" % (pt, pt))
        save(mac if pt == 512 else rounded_tile(pt * 2), "Resources", "Assets.xcassets", "AppIcon.appiconset",
             "icon_%dx%d@2x.png" % (pt, pt))
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
