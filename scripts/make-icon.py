"""Draws the Two Degrees app icon and writes every size the apps use.

The mark: "C°", the Cowdrey family's white C (open on the right, round caps) with a coral degree ring in
its opening, on a diagonal sky-blue gradient (#72AAE9 top left to #204294 bottom right), with one faint
shadow under the C and the ring. Same build as Cowdrey One, Cowdrey.MD and Cowdrey.PDF. All geometry is in
fractions of the icon width. Run from the repository root: python3 scripts/make-icon.py  (needs Pillow and
numpy). Writes:
  Resources/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png  1024, full-bleed, opaque RGB, square corners
                                                                 (iPhone, iPad; the OS masks the corners)
  Resources/AppIcon.png, docs/icon.png                           1024, macOS tile: 824 body, 185 radius, shadow
  Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png        the macOS tile at all 10 Mac sizes, 16 to 1024
  android/app/src/main/res/mipmap-*/ic_launcher(_round).png      legacy launcher sizes
  android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png  the mark, optically centred in the
                                                                 adaptive safe zone, on transparency
  android/app/src/main/res/drawable-nodpi/ic_launcher_background.png, app_mark.png
  android/app/src/main/res/drawable/ic_launcher_monochrome.xml   the same mark as a one-colour vector, for
                                                                 Android 13 themed icons
"""
import math
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
S = 4  # supersampling

# The C, as in the Cowdrey family icons.
C_CX, C_CY = 0.440, 0.500
C_RO = 0.313       # outer radius
C_T = 0.096        # stroke
C_END = 39.0       # the arc ends +/-39 degrees from 3 o'clock, with round caps
# The degree ring in the C's opening (about 22 px clear of the upper cap at 1024).
D_CX, D_CY = 0.775, 0.465
D_RO = 0.115       # outer radius
D_T = 0.060        # stroke; the hole stays open down to 58 px

SKY = ((0x72, 0xAA, 0xE9), (0x20, 0x42, 0x94))       # top left, bottom right
WHITE = (255, 255, 255)
CORAL = ((0xF0, 0x7A, 0x6E), (0xE8, 0x5F, 0x84))     # top left, bottom right of the ring
SHADOW = ((14, 30, 80), 0.28, 0.008, 0.012)          # colour, opacity, y offset, blur (fractions of size)
OPTICAL_PULL = 0.35  # Android: move the bounding-box centre this far toward the ink centroid


def diagonal(w, h, a, b, noise=True):
    """A top-left to bottom-right gradient, with a little noise so it does not band."""
    t = np.add.outer(np.arange(h), np.arange(w)) / max(w + h - 2, 1)
    rgb = np.array(a, float) + (np.array(b, float) - np.array(a, float)) * t[..., None]
    if noise:
        rgb += np.random.default_rng(2).uniform(-0.5, 0.5, (h, w))[..., None]
    return Image.fromarray(np.clip(np.round(rgb), 0, 255).astype(np.uint8), "RGB")


def c_mask(n, scale=1.0, off=(0.0, 0.0)):
    """The C. scale and off place the mark (scale about the centre, offset in fractions of n)."""
    m = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(m)
    cx = n * (0.5 + (C_CX - 0.5) * scale + off[0])
    cy = n * (0.5 + (C_CY - 0.5) * scale + off[1])
    ro, t = n * C_RO * scale, n * C_T * scale
    d.arc([cx - ro, cy - ro, cx + ro, cy + ro], C_END, 360 - C_END, fill=255, width=max(1, int(round(t))))
    rm = ro - t / 2
    for ang in (C_END, -C_END):
        a = math.radians(ang)
        x, y = cx + rm * math.cos(a), cy + rm * math.sin(a)
        d.ellipse([x - t / 2, y - t / 2, x + t / 2, y + t / 2], fill=255)
    return m


def ring_box(n, scale=1.0, off=(0.0, 0.0)):
    cx = n * (0.5 + (D_CX - 0.5) * scale + off[0])
    cy = n * (0.5 + (D_CY - 0.5) * scale + off[1])
    r = n * D_RO * scale
    return cx, cy, r


def ring_mask(n, scale=1.0, off=(0.0, 0.0)):
    m = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(m)
    cx, cy, ro = ring_box(n, scale, off)
    ri = ro - n * D_T * scale
    d.ellipse([cx - ro, cy - ro, cx + ro, cy + ro], fill=255)
    d.ellipse([cx - ri, cy - ri, cx + ri, cy + ri], fill=0)
    return m


def mark(n, scale=1.0, off=(0.0, 0.0)):
    """The white C, the coral ring and their shadow, on transparency."""
    layer = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    cm, dm = c_mask(n, scale, off), ring_mask(n, scale, off)
    ink = Image.fromarray(np.maximum(np.asarray(cm), np.asarray(dm)))
    colour, alpha, dy, blur = SHADOW
    sa = ink.filter(ImageFilter.GaussianBlur(blur * n * scale))
    sa = Image.fromarray((np.asarray(sa, np.float32) * alpha).astype(np.uint8))
    sm = Image.new("L", (n, n), 0)
    sm.paste(sa, (0, int(round(dy * n * scale))))
    layer = Image.new("RGBA", (n, n), colour + (255,))
    layer.putalpha(sm)
    white = Image.new("RGBA", (n, n), WHITE + (255,))
    layer.paste(white, (0, 0), cm)
    # The coral runs corner to corner across the ring itself.
    cx, cy, r = ring_box(n, scale, off)
    box = int(math.ceil(2 * r)) + 2
    coral = diagonal(box, box, *CORAL, noise=False).convert("RGBA")
    full = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    full.paste(coral, (int(round(cx - r)) - 1, int(round(cy - r)) - 1))
    layer.paste(full, (0, 0), dm)
    return layer


def art(n):
    img = diagonal(n, n, *SKY).convert("RGBA")
    img.alpha_composite(mark(n))
    return img


def full_bleed(size):
    return art(size * S).resize((size, size), Image.LANCZOS).convert("RGB")


def squircle_mask(n, size_frac=1.0, radius_frac=0.2237):
    """Continuous-corner rounded square (superellipse corners), centred."""
    s = size_frac * n
    x0 = y0 = (n - s) / 2
    r = radius_frac * s
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) + 0.5
    dx = np.maximum(np.maximum(x0 + r - xx, xx - (x0 + s - r)), 0) / r
    dy = np.maximum(np.maximum(y0 + r - yy, yy - (y0 + s - r)), 0) / r
    inside = (xx >= x0) & (xx <= x0 + s) & (yy >= y0) & (yy <= y0 + s) & (dx ** 4 + dy ** 4 <= 1.0)
    return Image.fromarray((inside * 255).astype(np.uint8))


def mac_tile(size):
    """The macOS tile: 824 body in 1024, radius 185, soft drop shadow."""
    n = max(size * S, 512)
    body = 824 / 1024
    bm = squircle_mask(n, body, 185 / 824)
    sh = bm.filter(ImageFilter.GaussianBlur(0.014 * n))
    sh = Image.fromarray((np.asarray(sh, np.float32) * 0.45).astype(np.uint8))
    shl = Image.new("L", (n, n), 0)
    shl.paste(sh, (0, int(0.010 * n)))
    tile = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    tile.putalpha(shl)
    sb = int(round(body * n))
    o = (n - sb) // 2
    layer = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    layer.paste(art(sb), (o, o))
    layer.putalpha(bm)
    tile = Image.alpha_composite(tile, layer)
    return tile.resize((size, size), Image.LANCZOS)


def masked(size, shape, radius=0.0):
    """The full-bleed art cut to a circle or a plain rounded square (Android)."""
    big = size * S
    m = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(m)
    if shape == "circle":
        d.ellipse([0, 0, big - 1, big - 1], fill=255)
    else:
        d.rounded_rectangle([0, 0, big - 1, big - 1], radius=int(round(big * radius)), fill=255)
    out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    out.paste(art(big), (0, 0), m)
    return out.resize((size, size), Image.LANCZOS)


def optical_offset(scale):
    """Offset that puts the mark's optical centre (bbox centre pulled toward the ink centroid) at 0.5."""
    n = 1024
    ink = np.maximum(np.asarray(c_mask(n, scale)), np.asarray(ring_mask(n, scale))).astype(float)
    ys, xs = np.nonzero(ink)
    bx, by = (xs.min() + xs.max() + 1) / 2 / n, (ys.min() + ys.max() + 1) / 2 / n
    w = ink.sum()
    yy, xx = np.mgrid[0:n, 0:n]
    gx, gy = (ink * (xx + 0.5)).sum() / w / n, (ink * (yy + 0.5)).sum() / w / n
    ox, oy = bx + (gx - bx) * OPTICAL_PULL, by + (gy - by) * OPTICAL_PULL
    return 0.5 - ox, 0.5 - oy


def monochrome_xml(scale, off):
    """The mark as a 108 dp vector, placed exactly like the adaptive foreground (themed icons)."""
    u = 108
    f = lambda v: ("%.2f" % v).rstrip("0").rstrip(".")
    cx, cy = u * (0.5 + (C_CX - 0.5) * scale + off[0]), u * (0.5 + (C_CY - 0.5) * scale + off[1])
    rm, t = u * (C_RO - C_T / 2) * scale, u * C_T * scale
    a = math.radians(C_END)
    x, dy = cx + rm * math.cos(a), rm * math.sin(a)
    c = "M%s,%s A%s,%s 0 1,0 %s,%s" % (f(x), f(cy - dy), f(rm), f(rm), f(x), f(cy + dy))
    rx, ry, ro = ring_box(u, scale, off)
    ri = ro - u * D_T * scale
    ring = " ".join("M%s,%s a%s,%s 0 1,%d %s,0 a%s,%s 0 1,%d %s,0z" % (f(rx - r), f(ry), f(r), f(r), sw, f(2 * r), f(r), f(r), sw, f(-2 * r))
                    for r, sw in ((ro, 0), (ri, 1)))
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<!-- Written by scripts/make-icon.py: the C and degree ring for Android 13 themed icons. -->\n'
            '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">\n'
            '    <path android:strokeColor="#FFFFFFFF" android:strokeWidth="%s" android:strokeLineCap="round"\n'
            '        android:pathData="%s" />\n'
            '    <path android:fillColor="#FFFFFFFF" android:fillType="evenOdd"\n'
            '        android:pathData="%s" />\n'
            '</vector>\n') % (f(t), c, ring)


def save(img, *path):
    p = os.path.join(ROOT, *path)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p, optimize=True)
    print("wrote", os.path.relpath(p, ROOT), img.size, img.mode)


def main():
    save(full_bleed(1024), "Resources", "iOS", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
    mac = mac_tile(1024)
    save(mac, "Resources", "AppIcon.png")
    save(mac, "docs", "icon.png")
    # Mac asset catalog: each size drawn at its own size, so small ones stay sharp.
    for pt in (16, 32, 128, 256, 512):
        save(mac_tile(pt), "Resources", "Assets.xcassets", "AppIcon.appiconset", "icon_%dx%d.png" % (pt, pt))
        save(mac if pt == 512 else mac_tile(pt * 2), "Resources", "Assets.xcassets", "AppIcon.appiconset",
             "icon_%dx%d@2x.png" % (pt, pt))
    res = ("android", "app", "src", "main", "res")
    for folder, px in (("mipmap-mdpi", 48), ("mipmap-hdpi", 72), ("mipmap-xhdpi", 96), ("mipmap-xxhdpi", 144), ("mipmap-xxxhdpi", 192)):
        save(masked(px, "square", 0.2), *res, folder, "ic_launcher.png")
        save(masked(px, "circle"), *res, folder, "ic_launcher_round.png")
    # Adaptive icon (Android 8+): the mark at 66% (the visible 72 of 108 dp), optically centred, so it sits
    # well inside the 66 dp safe circle.
    scale = 0.66
    off = optical_offset(scale)
    fg = mark(432 * S, scale, off)
    save(fg.resize((432, 432), Image.LANCZOS), *res, "drawable-nodpi", "ic_launcher_foreground.png")
    save(diagonal(432 * S, 432 * S, *SKY).resize((432, 432), Image.LANCZOS), *res, "drawable-nodpi", "ic_launcher_background.png")
    save(masked(256, "square", 0.26), *res, "drawable-nodpi", "app_mark.png")
    p = os.path.join(ROOT, *res, "drawable", "ic_launcher_monochrome.xml")
    with open(p, "w") as fh:
        fh.write(monochrome_xml(scale, off))
    print("wrote", os.path.relpath(p, ROOT))


if __name__ == "__main__":
    main()
