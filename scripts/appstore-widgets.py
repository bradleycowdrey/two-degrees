"""The App Store's widgets picture: a Home Screen with the app's real widget renders, at the device's own size, as
the fifth screen of the iPhone and iPad sets (the Simulator can't place widgets on its Home Screen). The
pictures are then framed like every other screen by scripts/app-store-screens.mjs, on the Cowdrey family
template (bradleycowdrey/cowdrey-one design/app-store/README.md).

  iphone-5.png: an iPhone 16 Pro Max Home Screen (440 x 956 pt at 3x, 1320 x 2868) with the status bar of
                iphone-1.png: the first city's large widget, the second city's medium, then the first city's
                small widget beside the app's icon, at their real point sizes and margins, and the page dots.
  ipad-5.png:   an iPad Home Screen at its 2x (2064 x 2752) with large icons on, where iPadOS draws widgets
                larger (1.25x their 2x render), with the status bar of ipad-1.png.

The widgets are the 2x renders from the iPhone self-test (widget-<n><city>-<size>.png, the store cities in
order). They are shown as rendered; only the status bar's charging battery becomes a full one.

Usage: python3 scripts/appstore-widgets.py <shots dir>      (writes iphone-5.png, and ipad-5.png when there is
                                                              an ipad-1.png, into that folder)
Needs Pillow and numpy."""
import glob
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
FONTS = os.path.join(ROOT, "Resources", "Fonts")
ICON = os.path.join(ROOT, "Resources", "iOS", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")


# ---------- colour fields ----------

def to_image(arr, seed=7):
    """Float RGB array -> 8-bit image, with triangular dither so smooth gradients never band."""
    rng = np.random.default_rng(seed)
    noise = rng.random(arr.shape[:2], np.float32) - rng.random(arr.shape[:2], np.float32)
    arr = arr.copy()
    arr[..., :3] += noise[..., None]
    return Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8), "RGB")


def ramp(t, stops):
    """Smooth multi-stop colour ramp, t in 0..1 (any shape) -> (..., 3)."""
    out = np.zeros(t.shape + (3,), np.float32)
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        m = (t >= t0) & (t <= t1)
        k = np.clip((t - t0) / (t1 - t0), 0, 1)
        k = k * k * (3 - 2 * k)
        seg = np.array(c0, np.float32) + (np.array(c1, np.float32) - np.array(c0, np.float32)) * k[..., None]
        out = np.where(m[..., None], seg, out)
    return out


def glow(img, xx, yy, cx, cy, rx, ry, colour, strength):
    d2 = ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2
    a = (np.exp(-d2 * 2.2) * strength)[..., None]
    return img * (1 - a) + np.array(colour, np.float32) * a


def home_wallpaper(w, h, seed=41):
    """A wallpaper in the app's own sky: deep blue under the status bar, opening to a lighter blue and a soft
    coral horizon (the icon's degree ring), so the widgets' blue cards stand clear."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = np.clip(yy / h * 0.9 + xx / w * 0.1, 0, 1)
    img = ramp(t, [(0.0, (14, 30, 84)), (0.40, (40, 74, 160)), (0.75, (112, 120, 196)), (1.0, (240, 150, 140))])
    img = glow(img, xx, yy, w * 0.85, h * 0.22, w * 0.6, h * 0.3, (90, 150, 240), 0.35)
    img = glow(img, xx, yy, w * 0.15, h * 0.85, w * 0.7, h * 0.3, (255, 160, 140), 0.30)
    return to_image(img, seed).convert("RGBA")


# ---------- shapes ----------

def squircle_mask(w, h, box, R, n=5.0):
    """Anti-aliased mask of a rectangle with continuous (superellipse) corners. R is how far along each edge the
    corner curve starts; n sets its shape."""
    x0, y0, x1, y1 = box
    cx, cy, hw, hh = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2
    R = min(R, hw, hh)
    xs = np.arange(w, dtype=np.float64) + 0.5
    ys = np.arange(h, dtype=np.float64) + 0.5
    cov_x = np.clip(hw - np.abs(xs - cx) + 0.5, 0, 1)
    cov_y = np.clip(hh - np.abs(ys - cy) + 0.5, 0, 1)
    a = np.minimum.outer(cov_y, cov_x)
    for sx in (-1, 1):
        for sy in (-1, 1):
            px = sorted((cx + sx * (hw - R), cx + sx * (hw + 1)))
            py = sorted((cy + sy * (hh - R), cy + sy * (hh + 1)))
            i0, i1 = max(0, int(np.floor(px[0]))), min(w, int(np.ceil(px[1])) + 1)
            j0, j1 = max(0, int(np.floor(py[0]))), min(h, int(np.ceil(py[1])) + 1)
            if i0 >= i1 or j0 >= j1:
                continue
            X, Y = np.meshgrid(xs[i0:i1], ys[j0:j1])
            qx = np.maximum(np.abs(X - cx) - (hw - R), 0) / R
            qy = np.maximum(np.abs(Y - cy) - (hh - R), 0) / R
            f = qx ** n + qy ** n
            g = (n / R) * np.sqrt(qx ** (2 * n - 2) + qy ** (2 * n - 2))
            d = np.where((np.abs(f - 1) < 0.5) & (g > 0), (f - 1) / np.maximum(g, 1e-9), (f ** (1 / n) - 1) * R)
            inside = (qx > 0) & (qy > 0)
            patch = a[j0:j1, i0:i1]
            a[j0:j1, i0:i1] = np.where(inside, np.minimum(patch, np.clip(0.5 - d, 0, 1)), patch)
    return Image.fromarray((a * 255 + 0.5).astype(np.uint8), "L")


def solid(size, colour, mask):
    im = Image.new("RGBA", size, colour)
    a = np.asarray(mask, np.float32) * (colour[3] / 255 if len(colour) == 4 else 1)
    im.putalpha(Image.fromarray(a.astype(np.uint8), "L"))
    return im


def paste(canvas, im, x, y):
    """alpha_composite that allows the picture to run off any edge of the canvas."""
    x, y = int(round(x)), int(round(y))
    l, t = max(0, -x), max(0, -y)
    r, b = min(im.width, canvas.width - x), min(im.height, canvas.height - y)
    if r <= l or b <= t:
        return
    canvas.alpha_composite(im.crop((l, t, r, b)), (x + l, y + t))


def shadowed(canvas, im, x, y, layers, colour):
    """Puts a picture down with a soft shadow under it, lit from the top."""
    pad = max(b for b, _, _ in layers) * 3
    a = Image.new("L", (im.width + pad * 2, im.height + pad * 2), 0)
    a.paste(im.getchannel("A"), (pad, pad))
    for blur, drop, opacity in layers:
        s = a.filter(ImageFilter.GaussianBlur(blur)).point(lambda v, o=opacity: int(v * o + 0.5))
        layer = Image.new("RGBA", s.size, colour + (0,))
        layer.putalpha(s)
        paste(canvas, layer, x - pad, y - pad + drop)
    paste(canvas, im, x, y)


# ---------- the status bar, icon and widgets ----------

def battery_full(a, band, x_from):
    """The status bar's battery full and not charging (a white body inside a translucent outline, and the
    translucent cap), drawn 4x over the capture's charging glyph. The glyph is found as the rightmost mark in
    band (rows) right of x_from; the page's colour is read right of it."""
    y0, y1 = band
    ref = np.median(a[y0:y1, -24:-8], 1)
    m = np.abs(a[y0:y1, x_from:] - ref[:, None, :]).sum(-1) > 30
    xs = np.where(m.any(0))[0]
    ys = np.where(m.any(1))[0]
    if not len(xs):
        return
    bx0, bx1 = x_from + xs[0], x_from + xs[-1] + 1
    by0, by1 = y0 + ys[0], y0 + ys[-1] + 1
    a[by0 - 3:by1 + 3, bx0 - 3:bx1 + 3] = ref[by0 - 3 - y0:by1 + 3 - y0][:, None, :]
    h = by1 - by0
    nub = max(3, round(h * 0.12))
    bw = bx1 - bx0 - nub - max(1, round(h * 0.05))
    k = 4
    W, H = (bx1 - bx0 + 4) * k, (h + 4) * k
    g = Image.new("L", (W, H), 0)
    body = Image.new("L", (W, H), 0)
    d, db = ImageDraw.Draw(g), ImageDraw.Draw(body)
    o = 2 * k
    sw = h * 0.085 * k
    r = h * 0.30 * k
    d.rounded_rectangle([o, o, o + bw * k, o + h * k], r, fill=255)
    d.rounded_rectangle([o + sw, o + sw, o + bw * k - sw, o + h * k - sw], r - sw, fill=0)
    nx = o + bw * k + h * 0.07 * k
    d.rounded_rectangle([nx, o + h * 0.32 * k, nx + nub * k, o + h * 0.68 * k], nub * k * 0.5, fill=255)
    ins = sw + h * 0.075 * k
    db.rounded_rectangle([o + ins, o + ins, o + bw * k - ins, o + h * k - ins], r - ins, fill=255)
    al = (np.asarray(g.resize((W // k, H // k), Image.LANCZOS), np.float32) / 255 * 0.40
          + np.asarray(body.resize((W // k, H // k), Image.LANCZOS), np.float32) / 255)
    al = np.clip(al, 0, 1)[..., None]
    X0, Y0 = bx0 - 2, by0 - 2
    reg = a[Y0:Y0 + al.shape[0], X0:X0 + al.shape[1]]
    a[Y0:Y0 + al.shape[0], X0:X0 + al.shape[1]] = reg * (1 - al) + 255 * al


def glyph_layer(a, y0, y1):
    """The status bar of a capture as a transparent layer: what is lighter than the row's background becomes
    white, what is darker (the Dynamic Island) black, each with its own coverage."""
    r = a[y0:y1]
    bg = np.median(r, 1)[:, None, :]
    lw = np.clip((r - bg).mean(-1) / np.maximum(255 - bg.mean(-1), 1), 0, 1)
    lb = np.clip((bg - r).mean(-1) / np.maximum(bg.mean(-1), 1), 0, 1)
    out = np.zeros(r.shape[:2] + (4,), np.float32)
    out[..., :3] = np.where((lw >= lb)[..., None], 255.0, 0.0)
    out[..., 3] = np.maximum(lw, lb) * 255
    return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), "RGBA")


def status_bar(path, band, x_from, rows):
    a = np.asarray(Image.open(path).convert("RGB"), np.float32).copy()
    battery_full(a, band, x_from)
    return glyph_layer(a, 0, rows)


def app_icon(px):
    """The app's icon at px across, masked to the iOS icon shape."""
    im = Image.open(ICON).convert("RGBA")
    tile = im.resize((px, px), Image.LANCZOS) if px != im.width else im.copy()
    tile.putalpha(squircle_mask(px, px, (0, 0, px, px), px * 0.40, 4.0))
    return tile


def icon_cell(panel, x, y, label="Two Degrees", size=128):
    """The app's icon on a Home Screen grid with its label under it."""
    shadowed(panel, app_icon(size), x, y, ((22, 10, 0.22), (4, 2, 0.12)), (10, 26, 70))
    f = ImageFont.truetype(os.path.join(FONTS, "Inter-Medium.ttf"), round(size * 0.19))
    lay = Image.new("RGBA", panel.size, (0, 0, 0, 0))
    ImageDraw.Draw(lay).text((x + size / 2, y + size + round(size * 0.27)), label, font=f, fill=(255, 255, 255, 255),
                             anchor="ms")
    sh = lay.getchannel("A").filter(ImageFilter.GaussianBlur(3)).point(lambda v: int(v * 0.45))
    shl = Image.new("RGBA", panel.size, (10, 20, 60, 0))
    shl.putalpha(sh)
    panel.alpha_composite(shl)
    panel.alpha_composite(lay)


def page_dots(p, cx, cy, d, n=2):
    """The Home Screen's page dots in their frosted pill: the first page white, the others dimmed."""
    gap = d * 1.6
    w = round(n * d + (n - 1) * gap + d * 2.4)
    h = round(d * 2.6)
    x0, y0 = round(cx - w / 2), round(cy - h / 2)
    p.alpha_composite(solid((w, h), (255, 255, 255, 46), squircle_mask(w, h, (0, 0, w, h), h * 0.5, 2)), (x0, y0))
    k = 4
    g = Image.new("RGBA", (w * k, h * k), (0, 0, 0, 0))
    dr = ImageDraw.Draw(g)
    for i in range(n):
        x = (d * 1.2 + i * (d + gap)) * k
        dr.ellipse([x, (h - d) / 2 * k, x + d * k, (h + d) / 2 * k], fill=(255, 255, 255, 255 if i == 0 else 110))
    p.alpha_composite(g.resize((w, h), Image.LANCZOS), (x0, y0))


def widgets(shots):
    """The first two store cities' widgets (widget-0<city>-*, widget-1<city>-*), as rendered."""
    def find(n, kind):
        hits = sorted(glob.glob(os.path.join(shots, f"widget-{n}*-{kind}.png")))
        if not hits:
            raise FileNotFoundError(f"no widget-{n}*-{kind}.png in {shots}")
        return Image.open(hits[0]).convert("RGBA")
    return dict(L=find(0, "large"), M=find(0, "medium"), S=find(0, "small"),
                mL=find(1, "large"), mM=find(1, "medium"), mS=find(1, "small"))


def up(im, k):
    """Widgets are rendered at 2x; the iPhone screen is 3x, and iPad's large-icon Home Screen draws them larger,
    so a widget is enlarged by k <= 1.5 (LANCZOS, then a light sharpen) to keep its true size on the screen."""
    assert k <= 1.5
    out = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    return out.filter(ImageFilter.UnsharpMask(radius=1.2, percent=40, threshold=2))


def home_shadow(p, im, x, y, s):
    shadowed(p, im, x, y, ((round(14 * s), round(6 * s), 0.30), (round(3 * s), round(1 * s), 0.16)), (16, 12, 50))


# ---------- the two Home Screens ----------

def phone_home(shots):
    pt = 3
    W, H = 1320, 2868
    p = home_wallpaper(W, H)
    p.alpha_composite(status_bar(os.path.join(shots, "iphone-1.png"), (60, 135), 1090, 190))
    w = widgets(shots)
    L, M, S = (up(w[k], 1.5) for k in ("L", "mM", "S"))
    x0, g = 38 * pt, 22 * pt
    y = 66 * pt
    home_shadow(p, L, x0, y, 1)
    y += L.height + g
    home_shadow(p, M, x0, y, 1)
    y += M.height + g
    home_shadow(p, S, x0, y, 1)
    # the icon grid's first cell beside the small widget (a 2 x 2 block of 85 pt cells as wide as it)
    icon_cell(p, round(W - x0 - 170 * pt + (85 - 64) / 2 * pt), y + 4 * pt, size=64 * pt)
    page_dots(p, W / 2, y + S.height + 28 * pt, 7 * pt)
    return p


def tablet_home(shots):
    W, H = 2064, 2752
    p = home_wallpaper(W, H, 42)
    p.alpha_composite(status_bar(os.path.join(shots, "ipad-1.png"), (10, 54), 1950, 60))
    w = widgets(shots)
    k = 1.25
    L, M, S, mL, mM, mS = (up(w[n], k) for n in ("L", "M", "S", "mL", "mM", "mS"))
    g = 70
    x0 = (W - L.width - g - M.width) // 2
    x1 = x0 + L.width + g
    y0 = 150
    home_shadow(p, L, x0, y0, 1.2)
    home_shadow(p, mM, x0, y0 + L.height + g, 1.2)
    home_shadow(p, M, x1, y0, 1.2)
    sy = y0 + M.height + g
    home_shadow(p, mS, x1, sy, 1.2)
    home_shadow(p, S, x1 + M.width - S.width, sy, 1.2)
    home_shadow(p, mL, x1, sy + S.height + g, 1.2)
    iy = y0 + L.height + g + mM.height + g
    icon_cell(p, x0 + 24, iy + 10, size=150)
    page_dots(p, W / 2, sy + S.height + g + mL.height + 60, 16)
    return p


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    shots = sys.argv[1]
    phone_home(shots).convert("RGB").save(os.path.join(shots, "iphone-5.png"))
    print("wrote", os.path.join(shots, "iphone-5.png"))
    if os.path.exists(os.path.join(shots, "ipad-1.png")):
        tablet_home(shots).convert("RGB").save(os.path.join(shots, "ipad-5.png"))
        print("wrote", os.path.join(shots, "ipad-5.png"))


if __name__ == "__main__":
    main()
