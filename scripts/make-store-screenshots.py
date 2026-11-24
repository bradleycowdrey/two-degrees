"""Makes the App Store screenshots for iPhone (6.9", 1320x2868), iPad (13", 2064x2752) and Mac (2880x1800)
in one system: each page has its own sky from the same family (clear day, golden hour, dusk, lagoon, night),
dark at the top so the white headline reads, lighter behind the device so the device stands out. A small coral
degree ring from the approved icon sits above every headline (the icon itself on the hero). The real app is
shown in a device frame drawn here, large and running off the bottom edge.

Writes appstore/screenshots/iphone-1..5.png, ipad-1..5.png and (with --mac) mac-1..5.png.

Usage:
  python3 scripts/make-store-screenshots.py [RAW]                     iPhone and iPad sets from RAW
  python3 scripts/make-store-screenshots.py [RAW] --mac DIR           also the Mac set from DIR
  python3 scripts/make-store-screenshots.py --only mac --mac git:ci-shots
                                                                      the Mac set from origin/ci-shots

RAW holds iphone-1..4.png (1320x2868), ipad-1..4.png (2064x2752) and the 2x widget renders
widget-<n><city>-{small,medium,large,lock-circular,lock-rectangular,lock-inline}.png, all from ONE capture
session (the same frozen weather on every page of a set).
DIR holds the Mac captures: the store-*.png files from the ci-shots branch (make_mac_set / mac_store_page),
or the older panel-*.png snapshots (mac_pages). "--mac git:ci-shots" reads them from origin/ci-shots.

The captures are tidied before framing, in the app's own pixels (see the "screen preparation" section):
  - the scroll seam under the condensed header is closed (iphone-2/ipad-2 get the 10-day card's real top
    from capture 1; iphone-3 gets its first tile row's top edge back; ipad-3 drops the half-scrolled Wind/Rain
    fragment and the Averages row, which has no data on iPad, and starts on whole tiles);
  - the iPad hourly strip ends on a whole column instead of a clipped "11 PM"; the iPad status bar keeps
    "9:41 AM" and drops the capture's date;
  - the city list sits on the app's own clear-day sky instead of black, without its footer
    (sources, "Updated ..." and the credit line).
Every capture and widget render is only ever scaled down (LANCZOS); all text is drawn at the final size.
Needs Pillow and numpy.
"""
import argparse
import glob
import importlib.util
import io
import os
import re
import subprocess

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "appstore", "screenshots")
FONTS = os.path.join(ROOT, "Resources", "Fonts")
ICON = os.path.join(ROOT, "Resources", "iOS", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
DEFAULT_RAW = "/tmp/claude-0/-home-user/d6b2fce6-87e9-5a4e-8aa5-26a3546d263b/scratchpad/raw3"
WHITE = (255, 255, 255)
SUB = (255, 255, 255, 224)   # subhead: white at 88%
CORAL = (255, 111, 97)       # the icon's degree ring, #FF6F61
INK = (18, 40, 96)           # dark text on the light callout card
HEAD_WEIGHT = "SemiBold"     # the heaviest Inter in Resources/Fonts (there is no Inter Bold here)
SUB_WEIGHT = "Medium"


# ---------- copy: ONE list shared by iPhone and iPad (US English; one idea per page) ----------
# Captions avoid "color/colour" since the app's own en strings use UK spelling ("Some colour possible").

COPY = [
    ("Every temperature\nin °F and °C", "Both units, always. No switching."),
    ("Ten days.\nBoth scales.", "Every high and low on one bar."),
    ("Every detail\nin both units", "Sunset, air quality, UV and more."),
    ("Your cities,\nside by side", "Up to 20 places, both units."),
    ("Both units on\nyour Home Screen", "Every widget size, and Lock Screen."),
]
IPHONE = COPY
IPAD = COPY

MAC = [
    ("Every temperature in °F and °C", "Press F or C to choose which unit is large"),
    ("Ten days on one scale", "Every low and high on one bar, beside the large widget"),
    ("Every detail, in both units", "Visibility, precipitation, cloud at each height, the moon and more"),
    ("Widgets on your desktop", "Small, medium and large. Each can show a city of its own."),
    ("In your menu bar and Dock", "The temperature in both units, always a glance away"),
]

# Which widget city goes with the app captures: the one whose reading matches the iPhone city list
# (Sydney 72°F / 22°C, H 77 L 64). The Honolulu widget renders show 78°F, a later reading than the
# iPhone pages' 79°F, so they are not used.
WIDGET_CITY = "sydney"

# ---------- sources ----------

def loader(source):
    """A function name -> RGBA image, reading from a folder or, for "git:<branch>", from origin/<branch>."""
    def load(name):
        if source.startswith("git:"):
            data = subprocess.run(["git", "-C", ROOT, "show", f"origin/{source[4:]}:{name}"],
                                  check=True, capture_output=True).stdout
            return Image.open(io.BytesIO(data)).convert("RGBA")
        return Image.open(os.path.join(source, name)).convert("RGBA")
    load.source = source
    return load


def names_in(source, pattern):
    if source.startswith("git:"):
        out = subprocess.run(["git", "-C", ROOT, "ls-tree", "--name-only", f"origin/{source[4:]}"],
                             check=True, capture_output=True, text=True).stdout.split()
        return sorted(n for n in out if re.fullmatch(pattern, n))
    return sorted(os.path.basename(p) for p in glob.glob(os.path.join(source, "*"))
                  if re.fullmatch(pattern, os.path.basename(p)))


def font(weight, size):
    return ImageFont.truetype(os.path.join(FONTS, f"Inter-{weight}.ttf"), size)


def down(im, w):
    """Scales a capture to width w. Never up: a capture is only ever made smaller, with LANCZOS."""
    if w > im.width:
        raise ValueError(f"would upscale a {im.width}px capture to {w}px")
    if w == im.width:
        return im.copy()
    return im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)


# ---------- colour fields (float, dithered once at the end) ----------

def to_image(arr, seed=7):
    """Float RGB(A) array -> 8-bit image, with triangular dither so smooth gradients never band."""
    rng = np.random.default_rng(seed)
    noise = rng.random(arr.shape[:2], np.float32) - rng.random(arr.shape[:2], np.float32)
    arr = arr.copy()
    arr[..., :3] += noise[..., None]
    mode = "RGBA" if arr.shape[2] == 4 else "RGB"
    return Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8), mode)


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



# One sky per page, all from the same family, in page order. Each is dark at the top, where the white headline
# sits (white on the top stop is at least 4.5:1), and lighter towards the bottom, behind the device, so the
# dark bezel and the app's blue screen stand clear of the page. In the App Store's thumbnail row the five
# pages read as five different moments of one day.
SKIES = [
    ("clear day",   [(0.0, (22, 80, 196)), (0.24, (34, 100, 216)), (0.62, (84, 152, 240)), (1.0, (156, 204, 252))],
     (178, 220, 255)),
    ("golden hour", [(0.0, (142, 40, 92)), (0.24, (186, 62, 100)), (0.62, (234, 108, 104)), (1.0, (255, 186, 120))],
     (255, 214, 160)),
    ("dusk",        [(0.0, (26, 24, 92)), (0.24, (42, 40, 134)), (0.62, (90, 88, 204)), (1.0, (156, 146, 238))],
     (200, 182, 255)),
    ("lagoon",      [(0.0, (4, 66, 100)), (0.24, (10, 94, 130)), (0.62, (32, 152, 176)), (1.0, (112, 214, 208))],
     (176, 242, 230)),
    ("night",       [(0.0, (6, 10, 34)), (0.30, (14, 22, 66)), (0.70, (30, 46, 112)), (1.0, (52, 72, 152))],
     (96, 120, 210)),
]


def sky_stops(index):
    return SKIES[index % len(SKIES)]


def sky_array(w, h, index=0, count=1):
    """The page's sky: a vertical ramp with a touch of the icon's diagonal, a broad glow behind the device and
    a faint lift at the top left, all in float and dithered once."""
    _, stops, light = sky_stops(index)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = np.clip((yy / h) * 0.92 + (xx / w) * 0.08, 0, 1)
    img = ramp(t, stops)
    img = glow(img, xx, yy, w * 0.5, h * 0.80, w * 0.75, h * 0.34, light, 0.30)
    img = glow(img, xx, yy, w * 0.12, -h * 0.04, w * 0.6, h * 0.16, stops[2][1], 0.18)
    return img


def sky(w, h, index=0, count=1):
    return to_image(sky_array(w, h, index, count), 7 + index).convert("RGBA")


def shadow_colour(index):
    """The page's darkest stop, darker still: device shadows are tinted by the page, not grey."""
    c = sky_stops(index)[1][0][1]
    return tuple(int(v * 0.55) for v in c)

# ---------- shapes ----------

def squircle_mask(w, h, box, R, n=5.0):
    """Anti-aliased mask of a rectangle with continuous (superellipse) corners, computed analytically.
    R is how far along each edge the corner curve starts; n sets its shape (5 is close to Apple's).
    The straight edges are a separable coverage product; only the four corner patches are evaluated."""
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
            # the corner patch: from the corner's tangent points out to the box edge
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


def ring(w, h, box, R, width, n=5.0):
    outer = np.asarray(squircle_mask(w, h, box, R, n), np.int16)
    x0, y0, x1, y1 = box
    inner = np.asarray(squircle_mask(w, h, (x0 + width, y0 + width, x1 - width, y1 - width), R - width, n), np.int16)
    return Image.fromarray(np.clip(outer - inner, 0, 255).astype(np.uint8), "L")


# ---------- text ----------

def text_width(text, f, track):
    return f.getlength(text) + track * (len(text) - 1)


def draw_line(d, cx, y, text, f, fill, track):
    """One centred line on the baseline y, with tracking, keeping Inter's kerning."""
    x0 = cx - text_width(text, f, track) / 2
    for i, ch in enumerate(text):
        x = f.getlength(text[:i + 1]) - f.getlength(ch)
        d.text((x0 + x + track * i, y), ch, font=f, fill=fill, anchor="ls")


def wrap(text, f, track, max_w):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if cur and text_width(t, f, track) > max_w:
            lines.append(cur)
            cur = w
        else:
            cur = t
    return lines + [cur]


def paste(canvas, im, x, y):
    """alpha_composite that allows the picture to run off any edge of the canvas."""
    x, y = int(round(x)), int(round(y))
    l, t = max(0, -x), max(0, -y)
    r, b = min(im.width, canvas.width - x), min(im.height, canvas.height - y)
    if r <= l or b <= t:
        return
    canvas.alpha_composite(im.crop((l, t, r, b)), (x + l, y + t))


def shadowed(canvas, im, x, y, layers=((70, 50, 0.42), (18, 12, 0.28)), colour=(6, 14, 44)):
    """Puts a picture down with a soft shadow under it, lit from the top (it may run off the canvas)."""
    pad = max(b for b, _, _ in layers) * 3
    a = Image.new("L", (im.width + pad * 2, im.height + pad * 2), 0)
    a.paste(im.getchannel("A"), (pad, pad))
    for blur, drop, opacity in layers:
        s = a.filter(ImageFilter.GaussianBlur(blur)).point(lambda v, o=opacity: int(v * o + 0.5))
        layer = Image.new("RGBA", s.size, colour + (0,))
        layer.putalpha(s)
        paste(canvas, layer, x - pad, y - pad + drop)
    paste(canvas, im, x, y)


# ---------- text ----------

TRACK = -0.02   # headline tracking, -2%
LEAD = 1.05     # headline line height


def fit_size(heads, size, max_w):
    """The one headline size for a whole set: the largest, up to `size`, at which every line fits."""
    while size > 40:
        f = font(HEAD_WEIGHT, size)
        if all(text_width(l, f, TRACK * size) <= max_w for h in heads for l in h.split("\n")):
            return size
        size -= 2
    return size


def fit_sub(subs, size, max_w):
    """The one subhead size for a set: every subhead must fit on ONE line within max_w."""
    while size > 24:
        f = font(SUB_WEIGHT, size)
        if all(text_width(s, f, -0.005 * size) <= max_w for s in subs if s):
            return size
        size -= 2
    return size


def title(canvas, head, sub, top, size, sub_size, max_w, cx=None):
    """Headline (lines split at '\\n') and a one-line subhead, centred, the headline's cap top at `top`.
    The subhead sits 0.35 x the headline size below the headline's descenders.
    Returns the y of the bottom of the subhead's descenders."""
    cx = canvas.width / 2 if cx is None else cx
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    size = fit_size([head], size, max_w)
    f = font(HEAD_WEIGHT, size)
    track = TRACK * size
    lead = round(size * LEAD)
    y = top + size * 0.727              # Inter's cap height
    for line in head.split("\n"):
        draw_line(d, cx, y, line, f, WHITE, track)
        y += lead
    y -= lead
    bottom = y + size * 0.24
    if sub:
        fs = font(SUB_WEIGHT, sub_size)
        st = -0.005 * sub_size
        y = bottom + size * 0.35 + sub_size * 0.727
        for line in wrap(sub, fs, st, max_w):
            draw_line(d, cx, y, line, fs, SUB, st)
            y += round(sub_size * 1.28)
        y -= round(sub_size * 1.28)
        bottom = y + sub_size * 0.24
    canvas.alpha_composite(layer)
    return round(bottom)


def degree_ring(canvas, cx, top, d):
    """The icon's coral degree ring, d across, drawn 4x and scaled down for clean edges."""
    k = 4
    big = Image.new("RGBA", (d * k, d * k), (0, 0, 0, 0))
    g = ImageDraw.Draw(big)
    stroke = d * k * 0.22
    g.ellipse([0, 0, d * k - 1, d * k - 1], fill=CORAL + (255,))
    g.ellipse([stroke, stroke, d * k - 1 - stroke, d * k - 1 - stroke], fill=(0, 0, 0, 0))
    paste(canvas, big.resize((d, d), Image.LANCZOS), cx - d / 2, top)


# ---------- the app icon ----------

def app_icon(px, shadow=True):
    """The approved icon at px across, masked to the iOS icon shape."""
    tile = down(Image.open(ICON).convert("RGBA"), px)
    tile.putalpha(squircle_mask(px, px, (0, 0, px, px), px * 0.40, 4.0))
    return tile


def continuous(r):
    """The superellipse (n=4) corner length that looks like a circular corner of radius r (same 45-degree
    inset): what Apple's continuous corners are."""
    return r * 1.85
# ---------- screen preparation (works on the captures' own pixels, never adds content) ----------

def arr(im):
    return np.asarray(im.convert("RGB"), np.float32)


def from_arr(a):
    return Image.fromarray(np.clip(a + 0.5, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def sky_of(a, x, stop):
    """The app's background colour on each row, read from a margin column; rows from `stop` on (the bottom
    toolbar) keep the last colour above it. Lightly smoothed so it carries no noise."""
    col = a[:, x - 2:x + 3].mean(1)
    col[stop:] = col[stop - 1]
    k = np.ones(9, np.float32) / 9
    pad = np.pad(col, ((4, 4), (0, 0)), mode="edge")
    return np.stack([np.convolve(pad[:, c], k, mode="valid") for c in range(3)], -1)


def closing(c, size=13):
    p = size
    padded = np.pad(np.clip(c, 0, 1), p)          # zeros beyond the edges, so the closing never grows there
    im = Image.fromarray((padded * 255 + 0.5).astype(np.uint8), "L")
    im = im.filter(ImageFilter.MaxFilter(size)).filter(ImageFilter.MinFilter(size))
    return np.asarray(im, np.float32)[p:-p, p:-p] / 255


def coverage(piece, bg):
    """How much of each pixel is card or tile rather than the sky behind it: 0 on the sky, 1 inside cards
    (text included), fractional on anti-aliased edges."""
    d = np.abs(piece - bg[:, None, :]).sum(-1)
    m = d > 12
    if not m.any():
        return np.zeros(d.shape, np.float32)
    K = np.median(piece[m], 0)
    kd = np.abs(K[None, :] - bg).sum(-1)[:, None]
    return closing(np.clip(d / np.maximum(kd, 12), 0, 1))


def move(dst, Bd, src, Bs, sy0, sy1, dy, end, alpha=0.4):
    """Copies src rows sy0..sy1 to dst at dy (stopping at `end`), re-lit for where they land: the sky behind
    them changes from Bs to Bd, fully on the sky and by (1 - alpha) under the translucent cards."""
    h = min(sy1 - sy0, end - dy)
    if h <= 0:
        return dy
    piece = src[sy0:sy0 + h]
    c = coverage(piece, Bs[sy0:sy0 + h])
    shift = (Bd[dy:dy + h] - Bs[sy0:sy0 + h])[:, None, :]
    dst[dy:dy + h] = piece + shift * (1 - alpha * c)[..., None]
    return dy + h


def fill(dst, Bd, y0, y1):
    dst[y0:y1] = Bd[y0:y1][:, None, :]


def unfade(a, B, y0, y1, xref, yclean):
    """Undoes the condensed header's fade-out on rows y0..y1, measured on a clean column of a card."""
    a = a.copy()
    K = a[yclean, xref]
    for y in range(y0, y1):
        v = K - B[y]
        t = float(np.clip(np.dot(a[y, xref] - B[y], v) / max(np.dot(v, v), 1), 0.2, 1))
        a[y] = (a[y] - (1 - t) * B[y]) / t
    return a


# iPhone (1320x2868): the condensed header ends at 402 (its fade runs to ~432); the toolbar starts at 2625.
PH_HEADER, PH_TOOLBAR, PH_GAP = 402, 2625, 31
# iPad (2064x2752): header ends at 265 (fade to ~295); toolbar at 2610.
TH_HEADER, TH_TOOLBAR, TH_GAP = 265, 2610, 28


def phone_ten_days(i1, i2):
    """iphone-2: the 10-day card from its real top. Capture 1 has the card's title and Today row (rows
    1712..1979, down to the separator under Today); capture 2 carries on from that separator (row 447)."""
    a1, a2 = arr(i1), arr(i2)
    B1, B2 = sky_of(a1, 20, 2600), sky_of(a2, 20, 2600)
    out = a2.copy()
    top = PH_HEADER + PH_GAP - 6               # the card's top edge sits 31px under the header
    fill(out, B2, PH_HEADER, top)
    y = move(out, B2, a1, B1, 1712, 1979, top, PH_TOOLBAR)
    move(out, B2, a2, B2, 447, PH_TOOLBAR, y, PH_TOOLBAR)
    return from_arr(out)


def phone_tiles(i3):
    """iphone-3: the first tile row (Sunset, UV) runs up under the header. Its labels are whole; its top
    edge is put back (the shape taken from the tile row below, the colour from the tile itself) and the
    page moved down 75px so the row starts 31px under the header, like every other gap."""
    a = arr(i3)
    B = sky_of(a, 20, 2600)
    a = unfade(a, B, PH_HEADER, 436, 1100, 440)
    Ts, y0 = 358, 408                 # where the Sunset/UV tiles' top edge is, and the first row kept
    tA = 986                          # the top edge of the tile row below (Air quality, Averages)
    n = y0 - Ts
    top = PH_HEADER + PH_GAP
    out = a.copy()
    fill(out, B, PH_HEADER, top + n)
    for x0, x1 in ((44, 650), (671, 1276)):
        strip = a[tA:tA + n, x0:x1]
        bgA = B[tA:tA + n][:, None, :]
        K = np.median(a[tA + 40, x0 + 80:x1 - 80], 0)
        c = np.clip(np.abs(strip - bgA).sum(-1) / np.maximum(np.abs(K - bgA).sum(-1), 12), 0, 1)
        # the tile's own colour just under its label, smoothed across so no column stands out
        T = np.median(a[452:478, x0 + 30:x1 - 30], 0)
        k = np.ones(61, np.float32) / 61
        T = np.stack([np.convolve(np.pad(T[:, ch], 30, mode="edge"), k, mode="valid") for ch in range(3)], -1)
        T = np.pad(T, ((30, 30), (0, 0)), mode="edge")[None] + 1.5
        out[top:top + n, x0:x1] = c[..., None] * T + (1 - c[..., None]) * B[top:top + n][:, None, :]
    move(out, B, a, B, y0, PH_TOOLBAR, top + n, PH_TOOLBAR)
    return from_arr(out)


def tablet_hours(p1):
    """ipad-1: the hourly strip ends on '10 PM' rather than a clipped '11 PM' column."""
    a = arr(p1)
    clean = a[1120:1440, 1795:1816].mean(1)
    a[1120:1440, 1660:1827] = clean[:, None, :]
    return from_arr(a)


def tablet_ten_days(p1, p2):
    """ipad-2: as phone_ten_days. ipad-1's card top runs 1486..1737; ipad-2 carries on from row 309."""
    a1, a2 = arr(p1), arr(p2)
    B1, B2 = sky_of(a1, 30, 2600), sky_of(a2, 30, 2600)
    out = a2.copy()
    top = TH_HEADER + TH_GAP - 6
    fill(out, B2, TH_HEADER, top)
    y = move(out, B2, a1, B1, 1486, 1737, top, TH_TOOLBAR)
    move(out, B2, a2, B2, 309, TH_TOOLBAR, y, TH_TOOLBAR)
    return from_arr(out)


def tablet_tiles(p2, p3):
    """ipad-3: whole tile rows only, in the app's order: Feels like / Humidity (from ipad-2), Sunset / UV,
    Visibility / Precipitation, Cloud / Moon. Left out: the half-scrolled Wind / Rain fragment under the
    header, and the Air quality / Averages row, since Averages had no data in this capture."""
    a2, a3 = arr(p2), arr(p3)
    B2, B3 = sky_of(a2, 30, 2600), sky_of(a3, 30, 2600)
    out = a3.copy()
    top = TH_HEADER + TH_GAP - 6
    fill(out, B3, TH_HEADER, TH_TOOLBAR)
    y = move(out, B3, a2, B2, 1803, 2285, top, TH_TOOLBAR)
    y = move(out, B3, a3, B3, 520, 1118, y, TH_TOOLBAR)
    move(out, B3, a3, B3, 1588, TH_TOOLBAR, y, TH_TOOLBAR)
    return from_arr(out)


def list_on_sky(shot, sky_rows, footer_y):
    """The city list as it would sit on the app's clear-day sky instead of black: every pixel the black
    showed through (the background, anti-aliased edges, the white title) is re-composited over sky_rows;
    the search field becomes a light frosted field; everything from footer_y down (sources, 'Updated',
    credits) is left as plain sky."""
    a = arr(shot)
    B = sky_rows[:a.shape[0]]
    lum = a.mean(-1)
    near = np.asarray(Image.fromarray(((lum < 4) * 255).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(9))) > 0
    K = np.stack([np.asarray(Image.fromarray(a[..., c].astype(np.uint8), "L").filter(ImageFilter.MaxFilter(7)),
                             np.float32) for c in range(3)], -1)
    alpha = np.where(near, np.clip(lum / np.maximum(K.mean(-1), 1), 0, 1), 1.0)
    out = a + (1 - alpha)[..., None] * B[:, None, :]
    # the search field: opaque #1C1C1F on black in the capture; here white at 20% over the sky
    F = np.array([28, 28, 31], np.float32)
    fm = np.abs(a - F).sum(-1) < 5
    rows = np.where(fm.sum(1) > a.shape[1] * 0.3)[0]
    if len(rows):
        r0, r1 = rows[0] - 4, rows[-1] + 5
        cols = np.where(fm[r0:r1].any(0))[0]
        c0, c1 = cols[0] - 4, cols[-1] + 5
        Fn = B[r0:r1] * 0.8 + 255 * 0.2
        out[r0:r1, c0:c1] += alpha[r0:r1, c0:c1, None] * (Fn[:, None, :] - F)
    out[footer_y:] = B[footer_y:][:, None, :]
    return from_arr(out)

def find_widget(raw, city, kind):
    hits = sorted(glob.glob(os.path.join(raw, f"widget-*{city}-{kind}.png")))
    if not hits:
        raise FileNotFoundError(f"no widget-*{city}-{kind}.png in {raw}")
    return Image.open(hits[0]).convert("RGBA")


def lock_glass(widget, plate):
    """A Lock Screen widget as iOS shows it: its content in white vibrancy, on a frosted plate (circular
    ones) or straight on the wallpaper. The renders come on opaque #1F1F1F; that is taken out here."""
    a = np.asarray(widget, np.float32)
    lum = a[..., :3].mean(-1)
    content = np.clip((lum - 31) / (255 - 31), 0, 1) ** 0.85 * (a[..., 3] / 255)
    out = np.zeros(a.shape, np.float32)
    out[..., :3] = 255
    base = (a[..., 3] / 255) * (0.20 if plate else 0)
    out[..., 3] = (content + base * (1 - content)) * 255
    return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), "RGBA")


# ---------- devices ----------

def iphone(shot, sw):
    """An iPhone 16 Pro Max drawn around a 1320-wide capture shown sw wide: a thin dark-titanium band with a
    polished outer edge, a 20px #0E0E10 bezel with a 2px #3A3A3C highlight just inside the band, continuous
    (n=4) corners concentric with a 58pt display corner, and side buttons in #2C2C2E sitting nearly flush.
    The capture brings the Dynamic Island."""
    scr = down(shot, sw)
    sh = scr.height
    s = sw / 1320
    band = max(5, round(7 * s))
    border = max(14, round(23 * s))
    btn = max(2, round(4 * s))
    r = 58 * 3 * s                       # the display's corner radius, in px
    side = band + border
    W, H = sw + 2 * side + 2 * btn, sh + 2 * side
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))

    def button(left, a, b):
        y0, y1 = H * a, H * b
        x0 = 0 if left else W - btn * 3
        m = squircle_mask(W, H, (x0, y0, x0 + btn * 3, y1), btn * 1.4, 4)
        out.alpha_composite(solid((W, H), (44, 44, 46, 255), m))
    button(True, 0.178, 0.204)    # action button
    button(True, 0.243, 0.300)    # volume up
    button(True, 0.318, 0.375)    # volume down
    button(False, 0.270, 0.360)   # side button

    body = (btn, 0, W - btn, H)
    Rb = continuous(r + side)
    m = squircle_mask(W, H, body, Rb, 4)
    t = np.linspace(0, 1, H, dtype=np.float32)[:, None]
    u = np.linspace(0, 1, W, dtype=np.float32)[None, :]
    lum = 64 - 22 * t + 10 * np.cos((u - 0.5) * np.pi) - 6   # dark titanium, lit from above
    ti = np.stack([lum, lum, lum * 1.04 + 2, np.asarray(m, np.float32)], -1)
    out.alpha_composite(to_image(ti, 3))
    out.alpha_composite(solid((W, H), (210, 214, 222, 90), ring(W, H, body, Rb, 1.6, 4)))
    inner = (btn + band, band, W - btn - band, H - band)
    Ri = continuous(r + border)
    out.alpha_composite(solid((W, H), (14, 14, 16, 255), squircle_mask(W, H, inner, Ri, 4)))
    out.alpha_composite(solid((W, H), (58, 58, 60, 255), ring(W, H, inner, Ri, 2.0, 4)))
    scr.putalpha(squircle_mask(sw, sh, (0, 0, sw, sh), continuous(r), 4))
    out.alpha_composite(scr, (btn + side, side))
    return out


def ipad(shot, sw):
    """An iPad Pro 13" drawn around a capture shown sw wide: an even black border, a fine aluminium edge and
    continuous corners concentric with a 31pt display corner."""
    scr = down(shot, sw)
    sh = scr.height
    s = sw / 2064
    edge = max(4, round(5 * s))
    border = round(46 * s)
    r = 31 * 2 * s
    side = edge + border
    W, H = sw + 2 * side, sh + 2 * side
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    Rb = continuous(r + side)
    m = squircle_mask(W, H, (0, 0, W, H), Rb, 4)
    t = np.linspace(0, 1, H, dtype=np.float32)[:, None] * np.ones((1, W), np.float32)
    lum = 96 - 36 * t
    out.alpha_composite(to_image(np.stack([lum, lum, lum * 1.04 + 2, np.asarray(m, np.float32)], -1), 4))
    out.alpha_composite(solid((W, H), (214, 218, 226, 96), ring(W, H, (0, 0, W, H), Rb, 1.6, 4)))
    inner = (edge, edge, W - edge, H - edge)
    Ri = continuous(r + border)
    out.alpha_composite(solid((W, H), (12, 12, 14, 255), squircle_mask(W, H, inner, Ri, 4)))
    out.alpha_composite(solid((W, H), (58, 58, 60, 255), ring(W, H, inner, Ri, 2.0, 4)))
    scr.putalpha(squircle_mask(sw, sh, (0, 0, sw, sh), continuous(r), 4))
    out.alpha_composite(scr, (side, side))
    return out


def device_shadow(index, scale=1.0):
    """A broad ambient shadow tinted by the page, and a tight contact shadow."""
    return ((round(80 * scale), round(40 * scale), 0.38), (round(14 * scale), round(8 * scale), 0.20)), \
        shadow_colour(index)


# ---------- the hero's callout: both units at the same size ----------

def unit_callout(canvas, cx, top, values, size, labels=("FAHRENHEIT", "CELSIUS")):
    """A frosted white card over the device with the reading in both units side by side, equal in size, so
    the app's one idea reads even at thumbnail size. The values are the capture's own reading."""
    fv = font(HEAD_WEIGHT, size)
    fl = font(SUB_WEIGHT, round(size * 0.17))
    track = -0.03 * size
    col = max(text_width(v, fv, track) for v in values) + size * 0.55
    w = round(col * 2 + size * 0.2)
    h = round(size * 1.42)
    x0, y0 = round(cx - w / 2), round(top)
    R = continuous(size * 0.34)
    # frosted glass: the page under the card, blurred and whitened
    under = canvas.crop((x0, y0, x0 + w, y0 + h)).filter(ImageFilter.GaussianBlur(size * 0.25))
    glass = Image.blend(under, Image.new("RGBA", (w, h), (255, 255, 255, 255)), 0.86)
    glass.putalpha(squircle_mask(w, h, (0, 0, w, h), R, 4))
    shadowed(canvas, glass, x0, y0, ((round(size * 0.3), round(size * 0.16), 0.30), (10, 4, 0.12)), (6, 20, 60))
    d = ImageDraw.Draw(canvas)
    lt = round(size * 0.17 * 0.08)
    for k, (v, lab) in enumerate(zip(values, labels)):
        ccx = x0 + w / 2 + (k - 0.5) * col
        draw_line(d, ccx, y0 + h * 0.27, lab, fl, INK + (150,), lt)
        draw_line(d, ccx, y0 + h * 0.27 + size * 0.2 + size * 0.727, v, fv, INK + (255,), track)
    d.line([(x0 + w / 2, y0 + h * 0.2), (x0 + w / 2, y0 + h * 0.8)], fill=INK + (38,), width=max(2, round(size / 80)))
    return y0 + h


# ---------- widgets ----------

def wallpaper(w, h, seed=31, deep=False):
    """A soft daylight wallpaper for the Home and Lock Screen panels: the app's clear sky warming to a pale
    horizon, with broad blurred light; distinct from the widgets' own deeper blue."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = np.clip(yy / h * 0.85 + xx / w * 0.15, 0, 1)
    if deep:     # the Lock Screen: the same sky, deeper, so white vibrancy widgets read on it
        img = ramp(t, [(0.0, (24, 58, 150)), (0.5, (52, 98, 196)), (0.85, (128, 120, 196)), (1.0, (206, 140, 150))])
    else:
        img = ramp(t, [(0.0, (70, 132, 226)), (0.45, (128, 182, 244)), (0.8, (214, 206, 236)), (1.0, (250, 206, 176))])
    img = glow(img, xx, yy, w * 0.85, h * 0.18, w * 0.6, h * 0.35, (176, 220, 255), 0.45)
    img = glow(img, xx, yy, w * 0.1, h * 0.9, w * 0.6, h * 0.3, (255, 196, 160), 0.35)
    return to_image(img, seed).convert("RGBA")


def widget_shadow(panel, im, x, y):
    shadowed(panel, im, x, y, ((22, 10, 0.22), (4, 2, 0.12)), (10, 26, 70))


def icon_cell(panel, x, y, label="Two Degrees"):
    """The app's own icon on the Home Screen grid, at the widgets' 2x scale (64pt icon, 12pt label)."""
    ic = app_icon(128)
    widget_shadow(panel, ic, x, y)
    f = font("Medium", 24)
    lay = Image.new("RGBA", panel.size, (0, 0, 0, 0))
    draw_line(ImageDraw.Draw(lay), x + 64, y + 128 + 34, label, f, (255, 255, 255, 255), 0)
    sh = lay.getchannel("A").filter(ImageFilter.GaussianBlur(3)).point(lambda v: int(v * 0.35))
    shl = Image.new("RGBA", panel.size, (10, 30, 70, 0))
    shl.putalpha(sh)
    panel.alpha_composite(shl)
    panel.alpha_composite(lay)


def panel_frame(panel, r=56):
    panel.putalpha(squircle_mask(panel.width, panel.height, (0, 0, panel.width, panel.height), continuous(r), 4))
    return panel


def home_panel(raw, wide=False):
    """A piece of a Home Screen at the widgets' native 2x scale (never enlarged): the large, medium and small
    widgets at their real grid sizes and spacing, with the app's icon in the remaining slot."""
    L, M, S = (find_widget(raw, WIDGET_CITY, k) for k in ("large", "medium", "small"))
    pad, gap = 52, 46
    if not wide:     # iPhone: medium + small, then large + the app icon
        W, H = pad * 2 + M.width + gap + S.width, pad * 2 + M.height + gap + L.height
        p = wallpaper(W, H, 31)
        widget_shadow(p, M, pad, pad)
        widget_shadow(p, S, pad + M.width + gap, pad)
        widget_shadow(p, L, pad, pad + M.height + gap)
        icon_cell(p, pad + M.width + gap + (S.width / 2 - 128) / 2 + 2, pad + M.height + gap + 10)
    else:            # iPad: large, then medium over small + the app icon
        W, H = pad * 2 + L.width + gap + M.width, pad * 2 + L.height
        p = wallpaper(W, H, 32)
        widget_shadow(p, L, pad, pad)
        x = pad + L.width + gap
        widget_shadow(p, M, x, pad)
        widget_shadow(p, S, x, pad + M.height + gap)
        icon_cell(p, x + S.width + gap + (S.width / 2 - 128) / 2 + 2, pad + M.height + gap + 10)
    return panel_frame(p)


def lock_panel(raw, W):
    """The top of a Lock Screen at the same 2x scale: the inline widget over the clock, the circular and
    rectangular widgets under it, all in the Lock Screen's white vibrancy."""
    inline = lock_glass(find_widget(raw, WIDGET_CITY, "lock-inline"), False)
    row = [lock_glass(find_widget(raw, WIDGET_CITY, "lock-circular"), True),
           lock_glass(find_widget(raw, WIDGET_CITY, "lock-rectangular"), False)]
    cs = 236
    top = 44
    clock_base = top + inline.height + 26 + cs * 0.727
    row_y = clock_base + 52
    H = round(row_y + row[0].height + 52)
    p = wallpaper(W, H, 33, deep=True)
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    lay.alpha_composite(inline, ((W - inline.width) // 2, top))
    draw_line(ImageDraw.Draw(lay), W / 2, clock_base, "9:41", font("SemiBold", cs), (255, 255, 255, 235), -cs * 0.03)
    gap = 28
    rx = (W - sum(r.width for r in row) - gap * (len(row) - 1)) / 2
    for r in row:
        lay.alpha_composite(r, (round(rx), round(row_y)))
        rx += r.width + gap
    sh = lay.getchannel("A").filter(ImageFilter.GaussianBlur(6)).point(lambda v: int(v * 0.25))
    shl = Image.new("RGBA", (W, H), (10, 30, 80, 0))
    shl.putalpha(sh)
    p.alpha_composite(shl)
    p.alpha_composite(lay)
    return panel_frame(p)


def widgets_page(c, index, raw, top, wide):
    """Home Screen panel above a Lock Screen panel, centred together in the room under the text."""
    home = home_panel(raw, wide)
    lock = lock_panel(raw, home.width)
    gap = 64
    total = home.height + gap + lock.height
    y = top + (c.height - top - total) / 2
    x = (c.width - home.width) / 2
    layers = ((60, 30, 0.40), (12, 6, 0.22))
    shadowed(c, home, x, y, layers, shadow_colour(index))
    shadowed(c, lock, x, y + home.height + gap, layers, shadow_colour(index))
    return c


# ---------- page layout: one system for iPhone and iPad ----------

class Spec:
    """Sizes for one device's set. Every page of a set uses the same headline and subhead size."""
    def __init__(self, w, h, head, sub, max_w, sub_w, ring, ring_top, icon, gap, sw, zoom_sw, n):
        self.w, self.h, self.head, self.sub, self.max_w, self.sub_w = w, h, head, sub, max_w, sub_w
        self.ring, self.ring_top, self.icon, self.gap, self.sw, self.zoom_sw, self.n = \
            ring, ring_top, icon, gap, sw, zoom_sw, n


# iPhone 6.9": headline 120px, subhead up to 54px on one line, the screen 1140 wide (device ~1200, 91%).
PHONE = Spec(1320, 2868, head=120, sub=54, max_w=1160, sub_w=1056, ring=52, ring_top=64, icon=176,
             gap=112, sw=1140, zoom_sw=1320, n=5)
# iPad 13": headline 150px, subhead up to 64px, the screen 1800 wide (device ~1890, 92%).
TABLET = Spec(2064, 2752, head=150, sub=64, max_w=1700, sub_w=1500, ring=64, ring_top=64, icon=220,
              gap=120, sw=1800, zoom_sw=2064, n=5)


def text_block(c, spec, i, head, sub, size, sub_size, hero):
    """The page's mark (the icon on the hero, the coral degree ring elsewhere), headline and subhead.
    Returns the y of the bottom of the text."""
    if hero:
        ic = app_icon(spec.icon)
        shadowed(c, ic, (c.width - spec.icon) / 2, spec.ring_top,
                 ((28, 14, 0.30), (6, 3, 0.16)), shadow_colour(i))
        top = spec.ring_top + spec.icon + round(spec.head * 0.42)
    else:
        degree_ring(c, c.width / 2, spec.ring_top, spec.ring)
        top = spec.ring_top + spec.ring + round(spec.head * 0.42)
    return title(c, head, sub, top, size, sub_size, spec.max_w)


def device_page(spec, frame, i, shot, head, sub, size, sub_size, hero=False, zoom=False):
    """The page's sky, text, and the device under it running off the bottom edge. zoom shows the capture at
    its full width (1:1, never enlarged): the device is then wider than the page and runs off the sides too,
    a close crop used where the screen's content ends early (the city list)."""
    c = sky(spec.w, spec.h, i, spec.n)
    bottom = text_block(c, spec, i, head, sub, size, sub_size, hero)
    dev = frame(shot, spec.zoom_sw if zoom else spec.sw)
    layers, colour = device_shadow(i, spec.w / 1320)
    y = bottom + spec.gap
    shadowed(c, dev, (spec.w - dev.width) / 2, y, layers, colour)
    return c, y, dev


def screen_y(spec, y, dev, cw, ch, row):
    """Where row `row` of a cw x ch capture lands on the page, for a device put down at y."""
    sh = round(spec.sw * ch / cw)
    return y + (dev.height - sh) / 2 + row * spec.sw / cw


def set_sizes(spec, copy):
    return (fit_size([h for h, _ in copy], spec.head, spec.max_w),
            fit_sub([s for _, s in copy], spec.sub, spec.sub_w))


# ---------- iPhone ----------

# The reading on every iPhone page: Honolulu, from capture 1.
READING = ("79°F", "26°C")


def iphone_set(raw):
    shot = lambda n: Image.open(os.path.join(raw, n)).convert("RGBA")
    spec = PHONE
    size, sub_size = set_sizes(spec, IPHONE)
    i1, i2, i3, i4 = (shot(f"iphone-{k}.png") for k in range(1, 5))
    sky1 = sky_of(arr(i1), 20, 2600)
    pages = []

    c, y, dev = device_page(spec, iphone, 0, i1, *IPHONE[0], size, sub_size, hero=True)
    # the callout sits over the hourly and 10-day part of the hero screen (page 2 shows those)
    # over the 10-day card, just under the hourly card (which ends at row 1690 of the capture)
    unit_callout(c, spec.w / 2, screen_y(spec, y, dev, 1320, 2868, 1690) + 24, READING, 176)
    pages.append(c)
    pages.append(device_page(spec, iphone, 1, phone_ten_days(i1, i2), *IPHONE[1], size, sub_size)[0])
    pages.append(device_page(spec, iphone, 2, phone_tiles(i3), *IPHONE[2], size, sub_size)[0])
    pages.append(device_page(spec, iphone, 3, list_on_sky(i4, sky1, 1876 + 40), *IPHONE[3], size, sub_size,
                             zoom=True)[0])
    c = sky(spec.w, spec.h, 4, spec.n)
    bottom = text_block(c, spec, 4, *IPHONE[4], size, sub_size, False)
    pages.append(widgets_page(c, 4, raw, bottom + 40, wide=False))
    return pages


# ---------- iPad ----------

def tablet_status(im):
    """Keeps '9:41 AM' in the iPad status bar and takes out the capture's date beside it."""
    a = arr(im)
    B = sky_of(a, 6, 2600)
    a[8:62, 165:340] = B[8:62][:, None, :]
    return from_arr(a)


TABLET_READING = ("78°F", "26°C")   # the iPad captures' own reading (see the report: re-capture to match)


def ipad_set(raw):
    shot = lambda n: tablet_status(Image.open(os.path.join(raw, n)).convert("RGBA"))
    spec = TABLET
    size, sub_size = set_sizes(spec, IPAD)
    p1, p2, p3, p4 = (shot(f"ipad-{k}.png") for k in range(1, 5))
    sky1 = sky_of(arr(p1), 30, 2600)
    pages = []
    c, y, dev = device_page(spec, ipad, 0, tablet_hours(p1), *IPAD[0], size, sub_size, hero=True)
    # over the 10-day card, just under the hourly card (which ends at row 1462 of the capture)
    unit_callout(c, spec.w / 2, screen_y(spec, y, dev, 2064, 2752, 1462) + 30, TABLET_READING, 252)
    pages.append(c)
    pages.append(device_page(spec, ipad, 1, tablet_ten_days(p1, p2), *IPAD[1], size, sub_size)[0])
    pages.append(device_page(spec, ipad, 2, tablet_tiles(p2, p3), *IPAD[2], size, sub_size)[0])
    pages.append(device_page(spec, ipad, 3, list_on_sky(p4, sky1, 1552 + 40), *IPAD[3], size, sub_size,
                             zoom=True)[0])
    c = sky(spec.w, spec.h, 4, spec.n)
    bottom = text_block(c, spec, 4, *IPAD[4], size, sub_size, False)
    pages.append(widgets_page(c, 4, raw, bottom + 40, wide=True))
    return pages

# ---------- Mac pages ----------

MW, MH = 2880, 1800


def mac_page(i):
    c = sky(MW, MH, i, len(MAC))
    head, sub = MAC[i]
    bottom = title(c, head, sub, 150, fit_size([h for h, _ in MAC], 118, MW - 400), 52, MW - 400)
    return c, bottom


def mac_store_page(i, store_png):
    """ONE Mac page (2880x1800) from one ci-shots store-*.png capture (a path or an open image, a finished
    window or scene at 2x): the page's sky, MAC[i]'s headline and subhead, and the capture centred in the
    space below, scaled down only if it must be (never up)."""
    im = (Image.open(store_png) if isinstance(store_png, str) else store_png).convert("RGBA")
    c, top = mac_page(i)
    room_w, room_h = MW - 320, MH - top - 120
    k = min(1.0, room_w / im.width, room_h / im.height)
    if k < 1:
        im = down(im, round(im.width * k))
    shadowed(c, im, (MW - im.width) / 2, top + 80 + (room_h - im.height) / 2,
             ((70, 40, 0.45), (12, 6, 0.32)), shadow_colour(i))
    return c


def mac_store_pages(load, names):
    """The Mac set from the ci-shots store-*.png captures, in the order of MAC (load: name -> image)."""
    return [mac_store_page(i, load(name)) for i, name in enumerate(names[:len(MAC)])]


def make_mac_set(store_pngs):
    """The Mac set (2880x1800) from the ci-shots branch's store-*.png captures, given as file paths (or
    already-open images), in page order: mac_store_page for each. Same skies, type scale and copy system as
    the iOS sets. Run it from the command line with:  --only mac --mac git:ci-shots   (or --mac <folder>)."""
    return [mac_store_page(i, p) for i, p in enumerate(list(store_pngs)[:len(MAC)])]


def mac_helpers():
    spec = importlib.util.spec_from_file_location("macshots", os.path.join(ROOT, "scripts", "make-mac-screenshots.py"))
    mac = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mac)
    return mac


def window_chrome(im, mac, mark_at=(20, 46, 35), lights=True):
    """For a 2x snapshot: puts the current app mark over the snapshot's (mark_at is its x, y and size at
    1x) and, for the main window, draws the traffic lights in the hidden title bar."""
    im = im.copy()
    x, y, n = (v * 2 for v in mark_at)
    bg = im.getpixel((8, y + n // 2))
    ImageDraw.Draw(im).rectangle([x - 4, y - 4, x + n + 4, y + n + 4], fill=bg)
    mark = down(Image.open(ICON).convert("RGBA"), n)
    mark.putalpha(squircle_mask(n, n, (0, 0, n, n), n * 0.36, 4.6))
    im.alpha_composite(mark, (x, y))
    if not lights:
        return im
    k = 4
    tl = Image.new("RGBA", (80 * 2 * k, 28 * 2 * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(tl)
    for i, (face, rim) in enumerate((((255, 95, 87), (226, 70, 63)), ((254, 188, 46), (223, 158, 25)),
                                     ((40, 200, 64), (27, 168, 47)))):
        cx, cy, r = (14 + 20 * i) * 2 * k, 14 * 2 * k, 6 * 2 * k
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=rim + (255,))
        r -= k
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=face + (255,))
    im.alpha_composite(tl.resize((160, 56), Image.LANCZOS), (0, 4))
    return im


def mac_pages(load):
    """The Mac set from the older panel-*.png snapshots (1x, put up to 2x by make-mac-screenshots.py)."""
    mac = mac_helpers()

    def window(im, **chrome):
        return mac.rounded(window_chrome(mac.up(im, 2), mac, **chrome), 24)

    def put(c, im, x, y):
        shadowed(c, im, x, y, ((70, 40, 0.5), (12, 6, 0.36)))

    shots = []
    c, top = mac_page(0)
    f = window(mac.no_banner(mac.no_update_dot(load("panel-4-extraLarge-base.png"))).crop((0, 0, 619, 512)))
    cc = window(mac.no_banner(mac.no_update_dot(load("panel-4-extraLarge-celsius.png"))).crop((0, 0, 619, 512)))
    gap = 110
    x = (MW - f.width - cc.width - gap) / 2
    y = top + (MH - top - f.height) / 2 + 20
    put(c, f, x, y)
    put(c, cc, x + f.width + gap, y)
    shots.append(c)

    c, top = mac_page(1)
    days = window(mac.no_update_dot(load("panel-4-extraLarge-days.png")).crop((0, 0, 619, 558)))
    widget = load("widget-large.png")
    gap = 130
    x = (MW - days.width - widget.width - gap) / 2
    y = top + (MH - top - days.height) / 2 + 20
    put(c, days, x, y)
    put(c, widget, x + days.width + gap, y + (days.height - widget.height) / 2)
    shots.append(c)

    c, top = mac_page(2)
    raw = load("panel-4-extraLarge-tiles.png")
    stitched = Image.new("RGBA", (raw.width, raw.height - 48))
    stitched.paste(mac.no_update_dot(load("panel-4-extraLarge-days.png")).crop((0, 0, raw.width, 86)), (0, 0))
    stitched.paste(raw.crop((0, 134, raw.width, raw.height)), (0, 86))
    tiles = window(stitched)
    room = MH - top - 90
    if tiles.height > room:
        tiles = mac.rounded(tiles.crop((0, 0, tiles.width, room)), 24)
    put(c, tiles, (MW - tiles.width) / 2, top + (MH - top - tiles.height) / 2 + 10)
    shots.append(c)

    c, top = mac_page(3)
    large, zurich = load("widget-large.png"), load("widget-picked-zurich-large.png")
    medium, small, small2 = load("widget-picked-denver-medium.png"), load("widget-small.png"), load("widget-picked-reykjavik-small.png")
    gap = 70
    x = (MW - (large.width * 3 + gap * 2)) / 2
    y = top + (MH - top - large.height) / 2 + 20
    put(c, large, x, y)
    mx = x + large.width + gap
    put(c, medium, mx, y)
    put(c, small, mx, y + large.height - small.height)
    put(c, small2, mx + medium.width - small2.width, y + large.height - small2.height)
    put(c, zurich, mx + medium.width + gap, y)
    shots.append(c)

    c, top = mac_page(4)
    panel_im = window(load("menu-bar-panel.png").crop((0, 0, 492, 610)), mark_at=(16, 22, 28), lights=False)
    tile = load("dock-tile.png")
    tile = tile.resize((512, 512), Image.LANCZOS)
    gap = 300
    x = (MW - panel_im.width - gap - tile.width) / 2
    y = top + (MH - top - panel_im.height) / 2 + 20
    put(c, panel_im, x, y)
    tx, ty = x + panel_im.width + gap, y + (panel_im.height - tile.height) / 2 - 20
    put(c, tile, tx, ty)
    ImageDraw.Draw(c).ellipse([tx + 246, ty + 552, tx + 266, ty + 572], fill=(255, 255, 255, 200))
    shots.append(c)
    return shots


def mac_set(source):
    """The Mac set from a folder (or git:<branch>): store-*.png captures when present (make_mac_set), else
    the older panel-*.png snapshots."""
    load = loader(source)
    store = names_in(source, r"store-\d+.*\.png")
    store.sort(key=lambda n: int(re.search(r"\d+", n).group()))
    if store and not source.startswith("git:"):
        return make_mac_set(os.path.join(source, n) for n in store)
    return mac_store_pages(load, store) if store else mac_pages(load)



# ---------- main ----------

def save(im, name):
    path = os.path.join(OUT, name)
    im.convert("RGB").save(path, optimize=True)
    print(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("raw", nargs="?", default=DEFAULT_RAW, help="folder of iPhone/iPad captures and widget renders")
    ap.add_argument("--mac", help="folder (or git:<branch>) of Mac captures; without it the Mac set is skipped")
    ap.add_argument("--only", default="iphone,ipad,mac", help="comma list of iphone, ipad, mac")
    a = ap.parse_args()
    only = a.only.split(",")
    os.makedirs(OUT, exist_ok=True)
    if "iphone" in only:
        for k, im in enumerate(iphone_set(a.raw), 1):
            save(im, f"iphone-{k}.png")
    if "ipad" in only:
        for k, im in enumerate(ipad_set(a.raw), 1):
            save(im, f"ipad-{k}.png")
    if "mac" in only and a.mac:
        for k, im in enumerate(mac_set(a.mac), 1):
            save(im, f"mac-{k}.png")


if __name__ == "__main__":
    main()
