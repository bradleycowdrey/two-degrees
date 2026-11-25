"""The iPhone and iPad App Store screenshots are now made on the Cowdrey family standard by
scripts/app-store-screens.mjs (see appstore/listing.md); this older generator still makes the Mac set
(--only mac, the default), whose menu bar panel doesn't fit the family template's 1180 x 700 pt Mac window:
--screens DIR writes its MacBooks, which scripts/store-frames.mjs frames.

Makes the App Store screenshots for iPhone (6.9", 1320x2868), iPad (13", 2064x2752) and Mac (2880x1800)
in one system: each page has its own sky from the same family (clear day, golden hour, dusk, lagoon, night),
dark at the top so the white headline reads, opening into a light pool behind the device. Every headline sits
at the same place in a set (no icon above it), so the headlines share one baseline.
The real app is shown in a device frame drawn here (natural-titanium iPhone, silver iPad, each lit from the
upper left with a near-white outer edge, and a page-tinted shadow), at one scale and one top per set, running
off the page's foot on every page; each screen is real app pixels down to that foot. The Mac pages show one
MacBook Pro (notch, lid edge, hinge and base) at one place, with the same desktop and menu bar.

Writes appstore/screenshots/iphone-1..5.png, ipad-1..5.png and mac-1..5.png.

Usage:
  python3 scripts/make-store-screenshots.py [RAW]                     the Mac set (from DEFAULT_MAC)
  python3 scripts/make-store-screenshots.py [RAW] --mac DIR           the Mac set from DIR
  python3 scripts/make-store-screenshots.py --only mac --mac git:ci-shots
                                                                      the Mac set from origin/ci-shots
  python3 scripts/make-store-screenshots.py --only iphone             one set only (iphone, ipad, mac)

RAW (default DEFAULT_RAW) holds iphone-1..4.png (1320x2868), ipad-1..4.png (2064x2752) and the 2x widget renders
widget-<n><city>-{small,medium,large,...}.png, all from ONE capture session (the same frozen weather on every
page: Bangkok 93°F / 34°C the hero, Mumbai, Dubai, Tokyo, Auckland). DIR (default DEFAULT_MAC) holds the Mac
captures: store-1-top.png, store-2-days.png, store-3-tiles.png (the window at 2x, 984x1240),
store-widget-{small,medium,large}.png and store-dock.png (make_mac_set), or the older panel-*.png snapshots
(mac_pages). "--mac git:ci-shots" reads them from origin/ci-shots. The Mac set also uses RAW's Mumbai widgets.

The captures are tidied in their own pixels (see "touch-ups", "figures and legibility" and "the screens"):
  - status bars: the charging battery becomes a full, plain one (battery_full); the iPhone city list gets its
    Dynamic Island back (its black status bar hid it); iPad keeps '9:41 AM  Tue Nov 24';
  - the 10-day 'Today' cloud becomes the sun of the 'Clear' reading (from the hourly 'Now' icon);
  - every °C equals its °F converted and rounded: where the app rounded the two units apart (94°F / 35°C,
    78°F / 25°C, 92°F / 34°C, 76°F / 25°C, 67°F / 20°C, 44°F / 6°C, 74°F / 24°C), the °C label is replaced by
    the right one from another row, or set in Inter (the app's face) at the same size and colour;
  - the secondary °C labels (and km, mm) are raised to near-white so both units read at thumbnail size;
  - the widgets' hourly 'Now' (92° / 33°C, partly cloudy) becomes 93° / 34°C under a sun, the large widget's
    'Today' a sun and its 'Thu' Wed's rain cloud (as the app shows it), from renders of the same session;
  - iphone-2's Humidity copy is re-wrapped so '20' and '°C' stay together (dew_point_line);
  - the tiles pages leave out Air quality and Averages ('7° above normal' carries no unit); the iPad Wind tile
    is joined from two captures (its compass, in neither, is left out);
  - the city lists show all five cities on the app's sky, without the footer (its credits) and the selection;
  - page 5 is a Home Screen drawn in the device: the widgets at their real sizes (the 2x renders enlarged 1.5x on
    iPhone, 1.25x on iPad), the app's icon on the grid and the page dots; the Mac windows are shown at 1.2x
    (MAC_K). These are the only enlargements.
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
DEFAULT_RAW = "/tmp/claude-0/-home-user/d6b2fce6-87e9-5a4e-8aa5-26a3546d263b/scratchpad/raw8"
DEFAULT_MAC = "/tmp/claude-0/-home-user/d6b2fce6-87e9-5a4e-8aa5-26a3546d263b/scratchpad/rawmac8"
WHITE = (255, 255, 255)
SUB = (255, 255, 255, 255)   # subhead: solid white (on the sky's dark top stops it is at least 5:1)
CORAL = (255, 111, 97)       # the icon's degree ring, #FF6F61
INK = (18, 40, 96)           # dark text on the light callout card
# The app's own pixels are never edited: no label, figure, icon or brightness is changed from what the app
# drew (App Store Review Guideline 2.3.3: screenshots show the app in use). The functions below that would
# (copy_label, whiten, retype, swap_icon, move_glyphs, copy_raw, widgets_now) do nothing while this is True.
AUTHENTIC = True
HEAD_WEIGHT = "SemiBold"     # the heaviest Inter in Resources/Fonts (there is no Inter Bold here)
SUB_WEIGHT = "Medium"


# ---------- copy: ONE list shared by iPhone and iPad (US English; one idea per page) ----------
# Captions avoid "color/colour" since the app's own en strings use UK spelling ("Some colour possible").

COPY = [
    ("Every temperature\nin °F and °C", "Both units, always. No switching."),
    ("Ten days,\nboth units", "Every high and low, in °F and °C."),
    ("Every detail\nin both units", "Feels like, dew point, visibility and more."),
    ("All your cities,\nboth units", "Up to 20 places in one list."),
    ("Both units on\nyour Home Screen", "Small, medium and large widgets."),
]
IPHONE = COPY
IPAD = COPY

MAC = [
    ("Every temperature in °F and °C", "Both units, side by side."),
    ("Ten days, both units", "Every high and low, in °F and °C."),
    ("Every detail in both units", "Visibility in miles and km, rain in inches and mm."),
    ("Widgets on your desktop", "Small, medium and large, each in both units."),
    ("In your menu bar and Dock", "Both units, always a glance away."),
]

# Which widget city goes with the app captures: the hero city (Bangkok 93°F / 34°C, H 95 L 79, as on every
# app page). The small Home Screen widget shows the second city (Mumbai 86°F / 30°C, as in the city list), so
# the panel shows that each widget can follow a city of its own.
WIDGET_CITY = "tokyo"
WIDGET_CITY2 = "mumbai"

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
    ("clear day",   [(0.0, (10, 36, 118)), (0.22, (20, 64, 170)), (0.62, (70, 140, 232)), (1.0, (150, 200, 250))],
     (196, 230, 255)),
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


def sky_array(w, h, index=0, count=1, pool=0.46):
    """The page's sky: a vertical ramp, symmetric left to right, with a bright pool of light centred at `pool`
    of the height (behind the device's top half), so the device's edge and shadow stand clear of the page. The
    top, where the text sits, keeps the ramp's dark stops. Float, dithered once."""
    _, stops, light = sky_stops(index)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = np.clip(yy / h, 0, 1)
    img = ramp(t, stops)
    img = glow(img, xx, yy, w * 0.5, h * (pool + 0.06), w * 0.80, h * 0.40, light, 0.62)
    img = glow(img, xx, yy, w * 0.5, h * pool, w * 0.46, h * 0.20, (255, 255, 255), 0.16)
    return img


def sky(w, h, index=0, count=1, pool=0.46):
    return to_image(sky_array(w, h, index, count, pool), 7 + index).convert("RGBA")


def shadow_colour(index):
    """The page's darkest stop, darker still: device shadows are tinted by the page, not grey."""
    c = sky_stops(index)[1][0][1]
    return tuple(int(v * 0.30) for v in c)

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


# ---------- touch-ups: small, local repairs in the captures' own pixels ----------
# Each works on a float RGB array. A glyph is lifted off its local background as a difference from that
# background (read on the box's left and right edges, row by row) and put down on another background the same
# way, so it lands on the destination's own colours.

def bg_lerp(a, box, k=3):
    """The background under box, row by row: a straight blend from the median of the k columns left of the box
    to the median of the k columns right of it."""
    x0, y0, x1, y1 = box
    L = np.median(a[y0:y1, x0 - k:x0], 1)
    R = np.median(a[y0:y1, x1:x1 + k], 1)
    t = np.linspace(0, 1, x1 - x0, dtype=np.float32)[None, :, None]
    return L[:, None, :] * (1 - t) + R[:, None, :] * t


def erase(a, box):
    x0, y0, x1, y1 = box
    a[y0:y1, x0:x1] = bg_lerp(a, box)


def lift(a, box, scale=1.0):
    """The content of box as a difference from its background, optionally scaled (LANCZOS, down only)."""
    x0, y0, x1, y1 = box
    d = a[y0:y1, x0:x1] - bg_lerp(a, box)
    if scale != 1.0:
        assert scale < 1.0
        w, h = round((x1 - x0) * scale), round((y1 - y0) * scale)
        d = np.stack([np.asarray(Image.fromarray(np.ascontiguousarray(d[..., c]), "F").resize((w, h), Image.LANCZOS))
                      for c in range(3)], -1)
    return d


def put(a, d, cx, cy, add=False):
    """Puts a lifted difference down centred at (cx, cy) on whatever background is there (add: straight onto the
    pixels there, for a background already known to be clean)."""
    h, w = d.shape[:2]
    x0, y0 = round(cx - w / 2), round(cy - h / 2)
    base = a[y0:y0 + h, x0:x0 + w] if add else bg_lerp(a, (x0, y0, x0 + w, y0 + h))
    a[y0:y0 + h, x0:x0 + w] = base + d


def swap_icon(a, src, sbox, dbox, scale=1.0, src_arr=None):
    """Replaces the icon in dbox with the one in sbox (from src_arr, or the same array), centred where the old one
    was. Boxes are (x0, y0, x1, y1) with a few pixels of background around the glyph."""
    if AUTHENTIC:
        return
    d = lift(a if src_arr is None else src_arr, sbox, scale)
    erase(a, dbox)
    put(a, d, (dbox[0] + dbox[2]) / 2, (dbox[1] + dbox[3]) / 2)


def move_glyphs(a, box, dx, dy):
    """Moves the glyphs in box by (dx, dy): lifted, the box cleared, put down at the new place."""
    if AUTHENTIC:
        return
    d = lift(a, box)
    erase(a, box)
    put(a, d, (box[0] + box[2]) / 2 + dx, (box[1] + box[3]) / 2 + dy)


def copy_label(a, src, dst, src_arr=None):
    """Puts the label in box src (from src_arr, or the same array) in place of the one in box dst (the same size,
    both with a few pixels of background around the glyphs): how a °C that disagrees with its °F is set right
    from the same label, in the same type, elsewhere on the screen."""
    if AUTHENTIC:
        return
    d = lift(a if src_arr is None else src_arr, src)
    erase(a, dst)
    put(a, d, (dst[0] + dst[2]) / 2, (dst[1] + dst[3]) / 2)


def text_cover(a, box):
    """The coverage (0..1) of light text in box over its background (read on the box's left and right edges),
    and that background."""
    x0, y0, x1, y1 = box
    bg = bg_lerp(a, box)
    lum = (a[y0:y1, x0:x1] - bg).mean(-1)
    top = max(np.percentile(lum, 99.7), 1)
    return np.clip(lum / top, 0, 1), bg


def whiten(a, box, level=0.95, bold=0.0):
    """Raises secondary text in box (light glyphs on a darker card) to near-white, keeping its own anti-aliasing:
    each pixel goes from the background towards white by its coverage. bold > 0 thickens the strokes a little
    (a share of the coverage spread one pixel left and right), so small °C values hold up at thumbnail size."""
    if AUTHENTIC:
        return
    x0, y0, x1, y1 = box
    c, bg = text_cover(a, box)
    if bold:
        s = np.maximum(np.pad(c, ((0, 0), (1, 0)))[:, :-1], np.pad(c, ((0, 0), (0, 1)))[:, 1:])
        c = np.maximum(c, s * bold)
    c = np.where(c < 0.06, 0, c)[..., None]
    a[y0:y1, x0:x1] = bg * (1 - c) + 255 * level * c


def erase_v(a, box, k=3):
    """Clears box from above and below instead of from the sides (a straight blend, column by column, from the
    rows over it to the rows under it): for a glyph with others tight on either side."""
    x0, y0, x1, y1 = box
    T = np.median(a[y0 - k:y0, x0:x1], 0)
    B = np.median(a[y1:y1 + k, x0:x1], 0)
    t = np.linspace(0, 1, y1 - y0, dtype=np.float32)[:, None, None]
    a[y0:y1, x0:x1] = T[None] * (1 - t) + B[None] * t


def retype(a, box, text, weight="Regular", align="right", track=0.0, vertical=False):
    """Sets text in Inter (the app's own typeface) in place of the light label inside box: the same cap height,
    baseline, colour and right (or left) edge as the glyphs there, drawn 4x and scaled down. For a figure the
    captures show rounded the other way (a °C that is not the °F converted and rounded)."""
    if AUTHENTIC:
        return
    x0, y0, x1, y1 = box
    c, bg = text_cover(a, box)
    ys, xs = np.where(c > 0.5)
    gy0, gy1 = y0 + ys.min(), y0 + ys.max() + 1
    gx0, gx1 = x0 + np.where(c.max(0) > 0.3)[0].min(), x0 + np.where(c.max(0) > 0.3)[0].max() + 1
    colour = a[y0:y1, x0:x1][c > 0.9].mean(0)
    (erase_v if vertical else erase)(a, box)
    k = 4
    size = (gy1 - gy0) / 0.727
    f = font(weight, round(size * k))
    w = round(text_width(text, f, track * size * k)) + 8 * k
    h = round(size * k * 1.4)
    g = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(g)
    base = round(size * k * 1.1)
    x = 4 * k
    for i, ch in enumerate(text):
        d.text((x + f.getlength(text[:i + 1]) - f.getlength(ch) + track * size * k * i, base), ch, font=f,
               fill=255, anchor="ls")
    cols = np.where(np.asarray(g).max(0) > 0)[0]
    g = g.crop((cols.min() // k * k, 0, (cols.max() // k + 1) * k, h))
    al = np.asarray(g.resize((g.width // k, h // k), Image.LANCZOS), np.float32) / 255
    by = gy1 - round(base / k)
    bx = gx1 - al.shape[1] if align == "right" else gx0
    reg = a[by:by + al.shape[0], bx:bx + al.shape[1]]
    a[by:by + al.shape[0], bx:bx + al.shape[1]] = reg * (1 - al[..., None]) + colour * al[..., None]


def battery_full(a, band, x_from):
    """The status bar's battery as Apple's marketing shows it: full and not charging (a white body inside a
    translucent outline, and the translucent cap), drawn 4x over the capture's charging glyph. The glyph is
    found as the rightmost mark in band (rows) right of x_from; the page's colour is read right of it."""
    y0, y1 = band
    ref = np.median(a[y0:y1, -24:-8], 1)
    m = np.abs(a[y0:y1, x_from:] - ref[:, None, :]).sum(-1) > 30
    xs = np.where(m.any(0))[0]
    ys = np.where(m.any(1))[0]
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


def unselect_card(a, card, ref, edge=9):
    """Takes out the list's selection outline: the outline band of the selected card (rows card[0]..card[1]) is
    replaced by the same band of the card under it (starting at row ref), which has none. The band is found from
    the black page around the cards, so only the card's rim is touched."""
    y0, y1 = card
    h = y1 - y0 + 1
    inside = a[y0 - 6:y1 + 7].mean(-1) > 4
    im = Image.fromarray((inside * 255).astype(np.uint8), "L")
    core = np.asarray(im.filter(ImageFilter.MinFilter(edge * 2 + 1)), np.uint8) > 0
    band = inside & ~core
    src = a[ref - 6:ref + h + 6]
    seg = a[y0 - 6:y1 + 7]
    seg[band] = src[band]
    a[y0 - 6:y1 + 7] = seg


def dew_point_line(a):
    """iphone-2's Humidity tile wraps 'The dew point is 68°F · 20 / °C right now.', leaving '°C' alone on the second
    line. The '20' (x 1163..1209 on the first line, rows 2405..2443) is moved to the start of the second line
    (48 rows down, x 719) and the second line's words are moved right to make room, so it reads
    '68°F ·' / '20°C right now.' with the same spacing the app sets in '68°F'."""
    if AUTHENTIC:
        return
    line2 = (712, 2449, 966, 2497)
    d2 = lift(a, line2)
    n20 = lift(a, (1157, 2401, 1215, 2447))
    erase(a, line2)
    erase(a, (1157, 2401, 1215, 2447))       # the '20'; the '·' before it stays on the first line
    shift = (1209 - 1163) + 5
    put(a, d2, (line2[0] + line2[2]) / 2 + shift, (line2[1] + line2[3]) / 2, add=True)
    put(a, n20, 713 + 29, 2424 + 48, add=True)


# iPhone (1320x2868): the condensed header ends at 402 (its fade runs to ~432); the toolbar starts at 2625.
PH_HEADER, PH_TOOLBAR, PH_GAP = 402, 2625, 31
# iPad (2064x2752): header ends at 265 (fade to ~295); toolbar at 2610.
TH_HEADER, TH_TOOLBAR, TH_GAP = 265, 2610, 28


def stack(dst, Bd, top, pieces, gap, end):
    """Lays whole cards or tile rows down one under the other from `top` (the first one's top edge), `gap` rows
    apart edge to edge, on the destination's sky, each re-lit for where it lands. A piece is (array, its sky,
    top edge, bottom edge) with the edges inclusive. Returns the last piece's bottom edge."""
    m = 8
    y = top
    for a, B, e0, e1 in pieces:
        move(dst, Bd, a, B, e0 - m, e1 + 1 + m, y - m, end)
        y += e1 - e0 + 1 + gap
    return y - gap - 1


def swap_tiles(a, cols):
    """Swaps the two tiles of a row: cols are the left and right tiles' (x0, x1), each taken with 8px of sky."""
    (l0, l1), (r0, r1) = cols
    b = a.copy()
    w = l1 - l0 + 16
    b[:, r0 - 8:r0 - 8 + w] = a[:, l0 - 8:l0 - 8 + w]
    b[:, l0 - 8:l0 - 8 + w] = a[:, r0 - 8:r0 - 8 + w]
    return b


def clean_below(a, B, y):
    """Plain app sky from row y down: nothing is shown half."""
    fill(a, B, y, a.shape[0])


def phone_status(a):
    battery_full(a, (60, 135), 1090)
    return a


def tablet_status_bar(a):
    battery_full(a, (10, 54), 1950)
    return a


def sun_for_today(a, src, sbox, dbox, scale):
    """The 10-day 'Today' row under a 'Clear' header gets the sun the hourly 'Now' shows, at the daily rows'
    icon size (the daily cloud is 0.9x the hourly one)."""
    swap_icon(a, None, sbox, dbox, scale, src_arr=src)


def copy_raw(a, src, dst, ref_src, ref_dst):
    """Copies the block src to dst (same size) as it is, shifted by the difference of the plain background read
    in ref_src and ref_dst: for one glyph wedged between others, where there is no clean edge to lift it from."""
    if AUTHENTIC:
        return
    x0, y0, x1, y1 = src
    X0, Y0, X1, Y1 = dst
    off = a[ref_dst[1]:ref_dst[3], ref_dst[0]:ref_dst[2]].reshape(-1, 3).mean(0) - \
        a[ref_src[1]:ref_src[3], ref_src[0]:ref_src[2]].reshape(-1, 3).mean(0)
    a[Y0:Y1, X0:X1] = a[y0:y1, x0:x1] + off


# ---------- figures and legibility ----------
# The app takes every reading in °C and rounds each unit on its own, so a 33.5°C high shows as 92°F / 34°C and a
# 25.5°C low as 78°F / 25°C. On a page that sells both units a sharp eye converts them, so every °C shown here is
# the °F beside it converted and rounded: the wrong label is replaced by the same label, in the same type, from
# another row (or, where the screen has none, set in Inter, the app's own face, at the same size and colour).
# The secondary °C labels are then raised to near-white so both units read at thumbnail size.

PH_DAY_LOW, PH_DAY_HIGH = (472, 570), (1075, 1175)     # the 10-day rows' low and high label columns (3x)


def phone_day_labels(a, rows, fixes):
    """A 10-day card's °C labels (each row's °F at r..r+39, °C at r+58..r+84): fixes is a list of
    (side, from row, to row); then every °C is raised to near-white."""
    for side, r0, r1 in fixes:
        x0, x1 = PH_DAY_LOW if side == "low" else PH_DAY_HIGH
        copy_label(a, (x0, r0 + 51, x1, r0 + 91), (x0, r1 + 51, x1, r1 + 91))
    for r in rows:
        for x0, x1 in (PH_DAY_LOW, PH_DAY_HIGH):
            whiten(a, (x0, r + 51, x1, r + 91), 0.93, 0.45)


PH1_DAYS = [1867, 2012, 2157, 2302, 2447, 2592]                      # iphone-1: Today .. Sun
PH2_DAYS = [480, 625, 770, 915, 1060, 1205, 1350, 1495, 1640]       # iphone-2: Wed .. Thu


def phone_fix_1(a):
    """iphone-1: the hourly 12 PM and 4 PM read 94° / 35°C (94°F is 34°C: Now's '34°C', columns 186 apart);
    10-day Thu reads 78° / 25°C (78°F is 26°C: Wed's '26°C'). The hero's 34°C and H/L °C line, the hourly °C row
    and the 10-day °C labels are raised to near-white."""
    for j in (1, 5):
        copy_label(a, (128, 1600, 240, 1644), (128 + 186 * j, 1600, 240 + 186 * j, 1644))
    whiten(a, (725, 480, 1050, 712), 1.0)              # the hero's 34°C
    whiten(a, (470, 934, 850, 986), 0.96, 0.4)          # H:35°C L:26°C
    whiten(a, (110, 1600, 1190, 1644), 0.94, 0.45)      # the hourly °C row
    phone_day_labels(a, PH1_DAYS[:5], [("low", 2012, 2157)])
    return a


def phone_fix_2(a):
    """iphone-2: both Thu rows 78° / 25°C (26°C, Wed's) and the second Wed 92° / 34°C (33°C, Mon's)."""
    phone_day_labels(a, PH2_DAYS, [("low", 480, 625), ("low", 480, 1640), ("high", 1205, 1495)])
    whiten(a, (85, 2298, 230, 2347), 0.94, 0.3)          # Feels like's 38°C
    return a


def phone_fix_3(a):
    """iphone-3: the tiles' secondary units (Visibility's 29 km, Precipitation's 0.0 mm) to near-white."""
    whiten(a, (85, 1786, 240, 1835), 0.94, 0.3)
    whiten(a, (712, 1786, 1030, 1844), 0.94, 0.3)
    return a


def phone_fix_list(a):
    """iphone-4's city cards (tops 641, 1067, 1493, 1919, 2345): Dubai 76°F reads 25°C (24°C), Auckland 67°F
    20°C (19°C) and Tokyo's low 44°F 6°C (7°C), set in Inter Medium over the figures (the °C after them stays);
    each card's °C lines are raised to near-white."""
    retype(a, (1106, 1680, 1170, 1727), "24", "Medium")
    retype(a, (1106, 2532, 1170, 2579), "19", "Medium")
    retype(a, (1157, 2222, 1180, 2262), "7", "Medium", vertical=True)
    for t in (641, 1067, 1493, 1919, 2345):
        whiten(a, (1090, t + 186, 1240, t + 236), 0.97, 0.3)
        whiten(a, (900, t + 302, 1240, t + 344), 0.92, 0.4)
    return a


TB_DAY_LOW, TB_DAY_HIGH = (632, 724), (1640, 1736)    # the iPad 10-day label columns (2x)
TB1_DAYS = [1633, 1768, 1903, 2039, 2173, 2308, 2444, 2578]
TB2_DAYS = [340, 475, 611, 745, 880, 1016, 1150, 1285, 1420]


def tablet_day_labels(a, rows, fixes):
    """As phone_day_labels at 2x (°F at r..r+47, °C at r+55..r+78)."""
    for side, r0, r1 in fixes:
        x0, x1 = TB_DAY_LOW if side == "low" else TB_DAY_HIGH
        copy_label(a, (x0, r0 + 50, x1, r0 + 84), (x0, r1 + 50, x1, r1 + 84))
    for r in rows:
        for x0, x1 in (TB_DAY_LOW, TB_DAY_HIGH):
            whiten(a, (x0, r + 50, x1, r + 84), 0.93, 0.45)


def tablet_fix_1(a):
    """ipad-1: hourly 12 PM and 4 PM 94° / 35°C (Now's 34°C, columns 174 apart); 10-day Thu 25°C (Wed's 26°C);
    the hero's 34°C, the H/L °C line, the hourly °C row and the 10-day °C raised to near-white."""
    for j in (1, 5):
        copy_label(a, (310, 1382, 415, 1422), (310 + 174 * j, 1382, 415 + 174 * j, 1422))
    whiten(a, (1100, 400, 1400, 556), 1.0)
    whiten(a, (860, 764, 1205, 806), 0.96, 0.4)
    whiten(a, (300, 1382, 1800, 1422), 0.94, 0.45)
    tablet_day_labels(a, TB1_DAYS[:-1], [("low", 1768, 1903)])
    return a


def tablet_fix_2(a):
    tablet_day_labels(a, TB2_DAYS, [("low", 340, 475), ("low", 340, 1420), ("high", 1016, 1285)])
    whiten(a, (270, 2041, 400, 2087), 0.94, 0.3)         # Feels like's 38°C
    whiten(a, (270, 2514, 430, 2565), 0.94, 0.3)         # Wind's 8 km/h
    return a


def tablet_fix_3(a):
    """ipad-3: Visibility's 29 km and Precipitation's 0.0 mm to near-white."""
    whiten(a, (270, 1824, 420, 1870), 0.94, 0.3)
    whiten(a, (1080, 1825, 1380, 1879), 0.94, 0.3)
    return a


def tablet_fix_list(a):
    """ipad-4's cards (tops 393, 791, 1189, 1587, 1985): Dubai 24°C, Auckland 19°C, Tokyo low 7°C."""
    retype(a, (1866, 1368, 1924, 1412), "24", "Medium")
    retype(a, (1866, 2164, 1924, 2208), "19", "Medium")
    retype(a, (1910, 1876, 1934, 1914), "7", "Medium", vertical=True)
    for t in (393, 791, 1189, 1587, 1985):
        whiten(a, (1850, t + 179, 1985, t + 223), 0.97, 0.3)
        whiten(a, (1700, t + 289, 1985, t + 325), 0.92, 0.4)
    return a


# ---------- the screens ----------
# Every screen is a whole capture-sized picture of real app pixels down to the toolbar; the device then runs off
# the page's foot, so a screen only has to be whole as far as the page shows it (V rows, from the layout).



def under_header(out, B, src, Bs, sy0, dy, end, header, fade=30):
    """Copies src from row sy0 to dst row dy on, up to `end`, and lets the rows just under the condensed header
    fade in from the sky as the app draws them (smoothstep over `fade` rows)."""
    move(out, B, src, Bs, sy0, sy0 + (end - dy), dy, end)
    for y in range(header, header + fade):
        t = (y - header) / fade
        t = t * t * (3 - 2 * t)
        out[y] = B[y] + (out[y] - B[y]) * t


def phone_hero(i1):
    """iphone-1 as captured: the city and its reading, the hourly card and the top of the 10-day card."""
    a = phone_status(phone_fix_1(arr(i1)))
    sun_for_today(a, a, (140, 1402, 226, 1488), (287, 1876, 373, 1939), 0.91)
    return from_arr(a)


def phone_ten_days(i1, i2):
    """iphone-2: the 10-day card from its real top. Capture 1 has the card's title and Today row (rows
    1712..1979, down to the separator under Today), with the Today icon made the sun of the 'Clear' header;
    capture 2 carries on from that separator (row 447): the rest of the card, the Rain Map row and the tiles."""
    a1, a2 = phone_fix_1(arr(i1)), phone_status(phone_fix_2(arr(i2)))
    sun_for_today(a1, a1, (140, 1402, 226, 1488), (287, 1876, 373, 1939), 0.91)
    B1, B2 = sky_of(a1, 20, 2600), sky_of(a2, 20, 2600)
    out = a2.copy()
    top = PH_HEADER + PH_GAP - 6               # the card's top edge sits 31px under the header
    fill(out, B2, PH_HEADER, out.shape[0])
    y = move(out, B2, a1, B1, 1712, 1979, top, PH_TOOLBAR)
    move(out, B2, a2, B2, 447, 2625, y, PH_TOOLBAR)
    return from_arr(out)


def phone_tiles(i2, i3, V):
    """iphone-3: the page scrolled to the tiles. Under the header, the end of the 10-day card and the Rain Map
    row run into Feels like / Humidity (capture 2, edges 2059..2528, the dew point line re-wrapped), then
    Visibility / Precipitation (capture 3, 1549..2018) and Cloud cover / Moon (2059..2621), the app's 40 rows
    apart, the last ending 20 rows above the page's foot (screen row V). Air quality and Averages (its '7°
    above normal' carries no unit) are left out."""
    a2, a3 = phone_fix_2(arr(i2)), phone_status(phone_fix_3(arr(i3)))
    dew_point_line(a2)
    B2, B3 = sky_of(a2, 20, 2600), sky_of(a3, 20, 2600)
    out = a3.copy()
    fill(out, B3, PH_HEADER, out.shape[0])
    cloud = V - 20 - (2621 - 2059 + 1)
    vis = cloud - 40 - (2018 - 1549 + 1)
    feels = vis - 40 - (2528 - 2059 + 1)
    under_header(out, B3, a2, B2, 2059 - (feels - PH_HEADER), PH_HEADER, feels + 470 + 8, PH_HEADER)
    stack(out, B3, vis, [(a3, B3, 1549, 2018), (a3, B3, 2059, 2621)], 40, PH_TOOLBAR)
    return from_arr(out)


def phone_list(i4, i1, sky1):
    """iphone-4: the city list on the app's clear-day sky, all five cities (Auckland runs off the page's foot),
    without the selection outline on Bangkok. The list draws its status bar on black, which hides the Dynamic
    Island; it is put back from capture 1 (same sky, same place)."""
    a = phone_fix_list(arr(i4))
    unselect_card(a, (628, 1023), 1054)
    out = arr(list_on_sky(from_arr(a), sky1, 2740))
    a1 = arr(i1)
    out[20:150, 380:940] = a1[20:150, 380:940]
    return from_arr(phone_status(out))


def tablet_hours(p1):
    """ipad-1: the hourly strip shows eight whole columns (Now .. 6 PM) instead of ending on a clipped '7 PM':
    the clipped column is taken out and the eight are spread to the card's width, the first staying put, so the
    strip ends as far from the card's right edge as it starts from its left (card 240..1826, columns centred
    at 362 + 174k in the capture). Under it the 10-day card begins, as captured."""
    a = tablet_status_bar(tablet_fix_1(arr(p1)))
    sun_for_today(a, a, (322, 1198, 404, 1280), (460, 1640, 542, 1700), 0.904)
    y0, y1 = 1106, 1458                        # under the strip's separator (1101), above the card's foot (1464)
    bg = np.median(a[y0:y1, 1636:1700], 1)     # the card on each row, between '6 PM' and the clipped '7 PM'
    src = a[y0:y1].copy()
    a[y0:y1, 250:1816] = bg[:, None, :]
    centres = [362 + 174 * k for k in range(8)]
    pitch = ((1826 - (362 - 240)) - 362) / 7
    for k, c in enumerate(centres):
        nc = round(362 + pitch * k)
        a[y0:y1, nc - 87:nc + 87] = src[:, c - 87:c + 87]
    return from_arr(a)


def tablet_ten_days(p1, p2):
    """ipad-2: as phone_ten_days. ipad-1's card top runs 1486..1737 (top edge 1492, the separator under Today
    at 1737; Today's cloud made the sun); ipad-2 carries on from that separator (row 309) to the toolbar: the
    rest of the card, the Rain Map row and the first tiles."""
    a1, a2 = tablet_fix_1(arr(p1)), tablet_status_bar(tablet_fix_2(arr(p2)))
    sun_for_today(a1, a1, (322, 1198, 404, 1280), (460, 1640, 542, 1700), 0.904)
    B1, B2 = sky_of(a1, 30, 2600), sky_of(a2, 30, 2600)
    out = a2.copy()
    top = TH_HEADER + TH_GAP - 6
    fill(out, B2, TH_HEADER, out.shape[0])
    y = move(out, B2, a1, B1, 1486, 1737, top, TH_TOOLBAR)
    move(out, B2, a2, B2, 309, 2610, y, TH_TOOLBAR)
    return from_arr(out)


def tablet_wind_row(a2, a3):
    """The Wind / Rain tile row, which no one capture shows whole: its top (header, '5 mph', '8 km/h') from
    ipad-2 (rows 2289..2585, edge to just above the wind compass) and its foot (the description lines and the
    tiles' lower edge) from ipad-3 (rows 306..449, under the header's fade). The compass between them is not
    in either capture and is left out. Returns the row (the tiles 441 tall, 8 rows of sky above and below) as an array with its sky."""
    top, foot = a2[2281:2586], a3[306:458].copy()
    B2, B3 = sky_of(a2, 30, 2600)[2281:2586], sky_of(a3, 30, 2600)[306:458]
    # the missing compass rows carried the tiles' gradient down: the foot is brought up to meet the top at the
    # join (column by column, from the 6 rows either side, both blank) and eased back to itself at its edge
    off = top[-6:].mean(0) - foot[:6].mean(0)
    t = np.clip(1 - np.arange(len(foot), dtype=np.float32) / (len(foot) - 14), 0, 1)
    foot += off[None] * (t * t * (3 - 2 * t))[:, None, None]
    B3 = B3 + (B2[-1] - B3[0])[None] * (t * t * (3 - 2 * t))[:, None]
    return np.concatenate([top, foot], 0), np.concatenate([B2, B3], 0)


def tablet_tiles(p2, p3, V):
    """ipad-3: the page scrolled to the tiles, as on iPhone: the end of the 10-day card and the Rain Map run
    into Feels like / Humidity (ipad-2, edges 1813..2252), then Wind / Rain (tablet_wind_row), Visibility /
    Precipitation (ipad-3, 1594..2041) and the top of Cloud cover / Moon at the page's foot. Every tile shown
    whole carries both units or a plain figure; Air quality and Averages (no data on iPad) are left out."""
    a2, a3 = tablet_fix_2(arr(p2)), tablet_status_bar(tablet_fix_3(arr(p3)))
    B2, B3 = sky_of(a2, 30, 2600), sky_of(a3, 30, 2600)
    W, BW = tablet_wind_row(a2, a3)
    out = a3.copy()
    fill(out, B3, TH_HEADER, out.shape[0])
    g = 28
    vis = V - 60 - (2041 - 1594 + 1)
    wind = vis - g - 441
    feels = wind - g - (2252 - 1813 + 1)
    under_header(out, B3, a2, B2, 1813 - (feels - TH_HEADER), TH_HEADER, feels + 440 + 8, TH_HEADER)
    move(out, B3, W, BW, 0, W.shape[0], wind - 8, TH_TOOLBAR)
    stack(out, B3, vis, [(a3, B3, 1594, 2041), (a3, B3, 2070, 2600)], g, TH_TOOLBAR)
    return from_arr(out)


def tablet_list(p4, sky1):
    """ipad-4: the city list on the app's sky, no selection outline, all five cities; the footer under them
    (sources and credits, from row 2360) is left out."""
    a = tablet_fix_list(arr(p4))
    unselect_card(a, (386, 755), 784)
    im = list_on_sky(from_arr(a), sky1, 2360)
    return from_arr(tablet_status_bar(arr(im)))


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


def with_alpha(a, alpha):
    im = from_arr(a)
    im.putalpha(alpha)
    return im


def widgets_now(L, M, mL, mM):
    """The Bangkok large and medium widgets' hourly 'Now' column reads the hour's forecast (92° / 33°C, partly
    cloudy) while the widget's own reading and every app screen say 93°F / 34°C, Clear. The column is replaced
    by the same column of the Mumbai widgets' '12 PM' (93° / 34°C under a sun), rendered in the same session at
    the same size and layout (Mumbai's large widget sits 4 rows lower), and the large widget's 'Today' cloud by
    Mumbai's daily sun ('Sat'). Only the glyphs move; each lands on the Bangkok widget's own background.
    Then the figures (widget_figures)."""
    if AUTHENTIC:
        return L, M
    a, s = arr(L), arr(mL)
    erase(a, (53, 285, 120, 394))
    put(a, lift(s, (385, 289, 452, 398)), 86.5, 339.5)
    swap_icon(a, None, (132, 609, 172, 649), (130, 433, 175, 466), src_arr=s)
    b, t = arr(M), arr(mM)
    erase(b, (346, 128, 413, 241))
    put(b, lift(t, (557, 128, 624, 241)), 379.5, 184.5)
    widget_figures(a, b)
    return with_alpha(a, L.getchannel("A")), with_alpha(b, M.getchannel("A"))


def widget_figures(a, b):
    """The large (a) and medium (b) Bangkok widgets at 2x: 12 PM and 4 PM read 94° / 35°C (34°C: Now's label,
    columns 111 apart on the large, 70 on the medium); Thu's range 25-35°C (78-95°F is 26-35°C: Today's) and
    its plain cloud (the app's Thu is rain, 33%: Wed's rain cloud). The hourly °C row, the range column and
    the 'Clear' line's ranges are raised to near-white."""
    if AUTHENTIC:
        return
    copy_label(a, (56, 366, 118, 394), (167, 366, 229, 394))
    copy_label(a, (56, 366, 118, 394), (610, 366, 672, 394))
    copy_label(a, (601, 436, 701, 463), (601, 526, 701, 553))
    erase(a, (128, 522, 178, 560))
    put(a, lift(a, (130, 472, 176, 516)), 153, 541)
    whiten(a, (50, 366, 680, 394), 0.93, 0.4)
    whiten(a, (600, 434, 702, 692), 0.92, 0.4)
    copy_label(b, (349, 212, 410, 239), (419, 212, 480, 239))
    whiten(b, (348, 212, 692, 239), 0.93, 0.4)
    whiten(b, (28, 280, 300, 310), 0.92, 0.3)


def small_figures(s):
    """A small widget's range line, raised to near-white."""
    a = arr(s)
    whiten(a, (28, 280, 300, 310), 0.92, 0.3)
    return with_alpha(a, s.getchannel("A"))


def mumbai_figures(L, M):
    """Mumbai's large widget: Wed's range 24-34°C (74°F is 23°C: the '3' of Thu's 23-33°C, rows 44 below,
    put over the '4'); the hourly °C row, the range column and the ranges raised to near-white."""
    a, b = arr(L), arr(M)
    copy_raw(a, (617, 529, 631, 553), (617, 485, 631, 509), (700, 529, 716, 553), (700, 485, 716, 509))
    whiten(a, (50, 370, 680, 398), 0.93, 0.4)
    whiten(a, (600, 438, 702, 688), 0.92, 0.4)
    whiten(b, (348, 212, 692, 239), 0.93, 0.4)
    whiten(b, (28, 280, 300, 310), 0.92, 0.3)
    return with_alpha(a, L.getchannel("A")), with_alpha(b, M.getchannel("A"))


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


def home_wallpaper(w, h, seed=41):
    """A wallpaper for the Home Screen in the app's own sky: deep blue under the status bar, opening to a
    lighter blue and a soft coral horizon (the icon's degree ring), so the widgets' blue cards stand clear."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = np.clip(yy / h * 0.9 + xx / w * 0.1, 0, 1)
    img = ramp(t, [(0.0, (14, 30, 84)), (0.40, (40, 74, 160)), (0.75, (112, 120, 196)), (1.0, (240, 150, 140))])
    img = glow(img, xx, yy, w * 0.85, h * 0.22, w * 0.6, h * 0.3, (90, 150, 240), 0.35)
    img = glow(img, xx, yy, w * 0.15, h * 0.85, w * 0.7, h * 0.3, (255, 160, 140), 0.30)
    return to_image(img, seed).convert("RGBA")


def up(im, k):
    """Widgets are rendered at 2x; the iPhone screen is 3x, and iPad's large-icon Home Screen draws them larger.
    Only here (and for the Mac windows, MAC_K) is a picture made larger (by k <= 1.5, LANCZOS, then a light sharpen) so a widget keeps its true
    size on the Home Screen."""
    assert k <= 1.5
    out = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    return out.filter(ImageFilter.UnsharpMask(radius=1.2, percent=40, threshold=2))


def home_widgets(raw):
    """The Home Screen widgets: Bangkok large and medium (widgets_now), Mumbai large and medium
    (mumbai_figures), and the two small ones."""
    L, M = (find_widget(raw, WIDGET_CITY, k) for k in ("large", "medium"))
    mL, mM = find_widget(raw, WIDGET_CITY2, "large"), find_widget(raw, WIDGET_CITY2, "medium")
    L, M = widgets_now(L, M, mL, mM)
    mL, mM = mumbai_figures(mL, mM)
    return dict(L=L, M=M, S=small_figures(find_widget(raw, WIDGET_CITY, "small")), mL=mL, mM=mM,
                mS=small_figures(find_widget(raw, WIDGET_CITY2, "small")))


def home_shadow(p, im, x, y, s):
    shadowed(p, im, x, y, ((round(14 * s), round(6 * s), 0.30), (round(3 * s), round(1 * s), 0.16)), (16, 12, 50))


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


def phone_home(raw, status, V):
    """iphone-5's screen: an iPhone 16 Pro Max Home Screen (440 x 956 pt at 3x, 1320 wide) with the status bar
    of capture 1: Bangkok's large widget, Mumbai's medium, then Bangkok's small widget beside the app's icon
    on the icon grid, at their real point sizes (364 x 382, 364 x 170, 170) and margins (38 pt), 22 pt apart,
    the page dots under them, all above the page's foot (screen row V)."""
    pt = 3
    W, H = 1320, 2868
    p = home_wallpaper(W, H)
    p.alpha_composite(glyph_layer(status, 0, 190))
    w = home_widgets(raw)
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
    page_dots(p, W / 2, min(V - 22 * pt, y + S.height + 28 * pt), 7 * pt)
    return p


def tablet_home(raw, status, V):
    """ipad-5's screen: an iPad Home Screen at its own 2x (2064 x 2752) with large icons on, where iPadOS draws
    widgets larger (here 1.25x their 2x render): on the left Bangkok's large widget over Mumbai's medium and the
    app's icon; on the right Bangkok's medium, the two small ones (Mumbai, Bangkok) and Mumbai's large; the
    page dots under them, above the page's foot (screen row V)."""
    W, H = 2064, 2752
    p = home_wallpaper(W, H, 42)
    p.alpha_composite(glyph_layer(status, 0, 60))
    w = home_widgets(raw)
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
    page_dots(p, W / 2, min(V - 50, sy + S.height + g + mL.height + 60), 16)
    return p


# ---------- devices ----------

def metal(W, H, mask, top, bottom, warm, seed):
    """A brushed-metal fill under `mask`: lit from the upper left (top -> bottom luminance, brighter to the left),
    brighter along the middle of each edge, with a faint warm or cool cast."""
    t = np.linspace(0, 1, H, dtype=np.float32)[:, None]
    u = np.linspace(0, 1, W, dtype=np.float32)[None, :]
    lum = top + (bottom - top) * t + 10 * np.cos((u - 0.5) * np.pi) - 6 - 10 * u
    # specular highlights: a bright streak down the left edge (the key light) and a softer one on the right
    lum = lum + 62 * np.exp(-((u - 0.006) / 0.006) ** 2) + 30 * np.exp(-((u - 0.994) / 0.006) ** 2)
    return to_image(np.stack([lum + warm, lum + warm * 0.4, lum - warm * 0.6,
                              np.asarray(mask, np.float32)], -1), seed)


def light_edge(W, H, box, R, width, seed=0):
    """The outermost polished edge of a frame catching the light: a fine near-white line all round, brightest at
    the top-left corner (the key light) and dimmer towards the bottom right, so the device's silhouette reads on
    any sky."""
    m = np.asarray(ring(W, H, box, R, width, 4), np.float32) / 255
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    k = 0.55 + 0.45 * np.exp(-(((xx / W) ** 2 + (yy / max(H, W)) ** 2) / 0.18))
    out = np.zeros((H, W, 4), np.float32)
    out[..., :3] = 255
    out[..., 3] = m * k * 255
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def iphone(shot, sw):
    """An iPhone 16 Pro Max in natural titanium drawn around a 1320-wide capture shown sw wide: a light
    brushed-titanium band lit from the upper left, with a polished near-white outer edge and a darker chamfer
    where it meets the glass, a black bezel with a fine #3A3A3C line just inside the band, continuous (n=4)
    corners concentric with a 58pt display corner, and side buttons in titanium sitting nearly flush. The light
    band and edge keep the phone clear of even the darkest sky. The capture brings the Dynamic Island."""
    scr = down(shot, sw)
    sh = scr.height
    s = sw / 1320
    band = max(9, round(16 * s))
    border = max(14, round(23 * s))
    btn = max(3, round(5 * s))
    r = 58 * 3 * s                       # the display's corner radius, in px
    side = band + border
    W, H = sw + 2 * side + 2 * btn, sh + 2 * side
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))

    def button(left, a, b):
        y0, y1 = H * a, H * b
        x0 = 0 if left else W - btn * 3
        m = squircle_mask(W, H, (x0, y0, x0 + btn * 3, y1), btn * 1.4, 4)
        out.alpha_composite(metal(W, H, m, 200, 160, 3, 5))
        out.alpha_composite(solid((W, H), (255, 255, 255, 120), ring(W, H, (x0, y0, x0 + btn * 3, y1), btn * 1.4, 1.2, 4)))
    button(True, 0.178, 0.204)    # action button
    button(True, 0.243, 0.300)    # volume up
    button(True, 0.318, 0.375)    # volume down
    button(False, 0.270, 0.360)   # side button

    body = (btn, 0, W - btn, H)
    Rb = continuous(r + side)
    out.alpha_composite(metal(W, H, squircle_mask(W, H, body, Rb, 4), 222, 176, 3, 3))
    out.alpha_composite(light_edge(W, H, body, Rb, 2.6))
    chamfer = (btn + band * 0.55, band * 0.55, W - btn - band * 0.55, H - band * 0.55)
    out.alpha_composite(solid((W, H), (92, 90, 86, 150), ring(W, H, chamfer, continuous(r + side - band * 0.55),
                                                             band * 0.45, 4)))
    inner = (btn + band, band, W - btn - band, H - band)
    Ri = continuous(r + border)
    out.alpha_composite(solid((W, H), (10, 10, 12, 255), squircle_mask(W, H, inner, Ri, 4)))
    out.alpha_composite(solid((W, H), (58, 58, 60, 255), ring(W, H, inner, Ri, 2.0, 4)))
    scr.putalpha(squircle_mask(sw, sh, (0, 0, sw, sh), continuous(r), 4))
    out.alpha_composite(scr, (btn + side, side))
    return out, (btn + side, side)


def ipad(shot, sw):
    """An iPad Pro 13" in silver drawn around a capture shown sw wide: a bright aluminium edge lit from the upper
    left with a polished near-white rim, an even black border (with the landscape front camera on the right-hand
    border, as the M4 iPad Pro has it in portrait), continuous corners concentric with a 31pt display corner, and
    the top button and volume buttons standing just proud of the edge."""
    scr = down(shot, sw)
    sh = scr.height
    s = sw / 2064
    edge = max(9, round(14 * s))
    border = round(46 * s)
    btn = max(3, round(4 * s))
    r = 31 * 2 * s
    side = edge + border
    W, H = sw + 2 * side + 2 * btn, sh + 2 * side + btn
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bw, bh = W - 2 * btn, H - btn
    # top button (top edge, right) and volume up / down (right edge, top)
    for box in ((bw * 0.80, 0, bw * 0.90, btn * 3), ):
        x0, y0, x1, y1 = box[0] + btn, box[1], box[2] + btn, box[3]
        out.alpha_composite(metal(W, H, squircle_mask(W, H, (x0, y0, x1, y1), btn * 1.4, 4), 210, 190, -2, 6))
    for a, b in ((0.055, 0.095), (0.105, 0.145)):
        x0, y0, x1, y1 = W - btn * 3, btn + bh * a, W, btn + bh * b
        out.alpha_composite(metal(W, H, squircle_mask(W, H, (x0, y0, x1, y1), btn * 1.4, 4), 210, 190, -2, 6))
    body = (btn, btn, W - btn, H)
    Rb = continuous(r + side)
    out.alpha_composite(metal(W, H, squircle_mask(W, H, body, Rb, 4), 226, 184, -2, 4))
    out.alpha_composite(light_edge(W, H, body, Rb, 2.6))
    k = edge * 0.55
    out.alpha_composite(solid((W, H), (96, 98, 104, 150), ring(W, H, (btn + k, btn + k, W - btn - k, H - k),
                                                              continuous(r + side - k), edge * 0.45, 4)))
    inner = (btn + edge, btn + edge, W - btn - edge, H - edge)
    Ri = continuous(r + border)
    out.alpha_composite(solid((W, H), (10, 10, 12, 255), squircle_mask(W, H, inner, Ri, 4)))
    out.alpha_composite(solid((W, H), (58, 58, 60, 255), ring(W, H, inner, Ri, 2.0, 4)))
    # the front camera: a dark lens with a faint blue glint, centred in the right-hand border
    cx, cy, cr = W - btn - edge - border / 2, btn + edge + border + sh * 0.5, max(4, border * 0.16)
    kk = 4
    cam = Image.new("RGBA", (round(cr * 4 * kk), round(cr * 4 * kk)), (0, 0, 0, 0))
    d = ImageDraw.Draw(cam)
    c = cam.width / 2
    d.ellipse([c - cr * kk, c - cr * kk, c + cr * kk, c + cr * kk], fill=(26, 28, 34, 255))
    d.ellipse([c - cr * 0.55 * kk, c - cr * 0.55 * kk, c + cr * 0.55 * kk, c + cr * 0.55 * kk], fill=(14, 18, 40, 255))
    d.ellipse([c - cr * 0.35 * kk, c - cr * 0.5 * kk, c - cr * 0.05 * kk, c - cr * 0.2 * kk], fill=(70, 90, 150, 200))
    cam = cam.resize((cam.width // kk, cam.height // kk), Image.LANCZOS)
    out.alpha_composite(cam, (round(cx - cam.width / 2), round(cy - cam.height / 2)))
    scr.putalpha(squircle_mask(sw, sh, (0, 0, sw, sh), continuous(r), 4))
    out.alpha_composite(scr, (btn + side, btn + side))
    return out, (btn + side, btn + side)


def device_shadow(index, scale=1.0):
    """A broad ambient shadow tinted by the page (70px blur, 42%), a closer key shadow and a tight contact
    shadow, so the device lifts clear of the light pool behind it."""
    return ((round(70 * scale), round(34 * scale), 0.42), (round(24 * scale), round(12 * scale), 0.30),
            (round(5 * scale), round(2 * scale), 0.32)), shadow_colour(index)


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


def icon_cell(panel, x, y, label="Two Degrees", size=128):
    """The app's own icon on a Home Screen grid with its label under it (size px across; the label 3/16 of it)."""
    ic = app_icon(size)
    widget_shadow(panel, ic, x, y)
    f = font("Medium", round(size * 0.19))
    lay = Image.new("RGBA", panel.size, (0, 0, 0, 0))
    draw_line(ImageDraw.Draw(lay), x + size / 2, y + size + round(size * 0.27), label, f, (255, 255, 255, 255), 0)
    sh = lay.getchannel("A").filter(ImageFilter.GaussianBlur(3)).point(lambda v: int(v * 0.45))
    shl = Image.new("RGBA", panel.size, (10, 20, 60, 0))
    shl.putalpha(sh)
    panel.alpha_composite(shl)
    panel.alpha_composite(lay)


def panel_frame(panel, r=56):
    panel.putalpha(squircle_mask(panel.width, panel.height, (0, 0, panel.width, panel.height), continuous(r), 4))
    return panel


# ---------- page layout: one system for iPhone and iPad ----------

class Spec:
    """Sizes for one device's set. Every page of a set uses the same headline and subhead size at the same
    place (so the headlines share one baseline) and the same device scale and top; the device runs off the
    page's foot on every page."""
    def __init__(self, w, h, head, sub, max_w, sub_w, head_top, dev_top, sw, pool):
        self.w, self.h, self.head, self.sub, self.max_w, self.sub_w = w, h, head, sub, max_w, sub_w
        self.head_top, self.dev_top, self.sw, self.pool = head_top, dev_top, sw, pool


# iPhone 6.9": headline 116px, subhead up to 54px on one line, the screen 1140 wide (device ~1220, 92%).
PHONE = Spec(1320, 2868, head=116, sub=54, max_w=1160, sub_w=1120, head_top=176, dev_top=600, sw=1140,
             pool=0.30)
# iPad 13": headline 144px, subhead up to 64px, the screen 1800 wide (device ~1900, 92%).
TABLET = Spec(2064, 2752, head=144, sub=64, max_w=1700, sub_w=1600, head_top=170, dev_top=640, sw=1800,
              pool=0.30)


def visible_rows(spec, frame, shot_w, shot_h):
    """How many rows of a capture the page shows: the screen's top on the page to the page's foot, in capture
    rows."""
    dev, (ox, oy) = frame(Image.new("RGBA", (shot_w, shot_h)), spec.sw)
    return int((spec.h - spec.dev_top - oy) * shot_w / spec.sw)


def device_page(spec, frame, i, shot, head, sub, size, sub_size):
    """The page's sky, headline and subhead, and the device under them at the set's one scale and top, running
    off the page's foot."""
    dev, _ = frame(shot, spec.sw)
    c = sky(spec.w, spec.h, i, 1, spec.pool)
    title(c, head, sub, spec.head_top, size, sub_size, spec.max_w)
    layers, colour = device_shadow(i, spec.w / 1320)
    shadowed(c, dev, (spec.w - dev.width) / 2, spec.dev_top, layers, colour)
    return c


def mark(c, cx, top, d):
    """The app icon, d across, with a soft shadow."""
    ic = app_icon(d)
    shadowed(c, ic, cx - d / 2, top, ((round(d * 0.16), round(d * 0.06), 0.35), (round(d * 0.03), 1, 0.2)),
             (6, 10, 40))


def set_sizes(spec, copy):
    return (fit_size([h for h, _ in copy], spec.head, spec.max_w),
            fit_sub([s for _, s in copy], spec.sub, spec.sub_w))


# ---------- iPhone ----------

def iphone_set(raw, screens_only=False):
    shot = lambda n: Image.open(os.path.join(raw, n)).convert("RGBA")
    spec = PHONE
    size, sub_size = set_sizes(spec, IPHONE)
    i1, i2, i3, i4 = (shot(f"iphone-{k}.png") for k in range(1, 5))
    # The family template (scripts/store-frame.mjs) shows the whole phone, so its screens are full height.
    V = 2868 if screens_only else visible_rows(spec, iphone, 1320, 2868)
    a1 = arr(i1)
    sky1 = sky_of(a1, 20, 2600)
    status = phone_status(a1.copy())
    screens = [phone_hero(i1), phone_ten_days(i1, i2), phone_tiles(i2, i3, V), phone_list(i4, i1, sky1),
               phone_home(raw, status, V)]
    if screens_only:
        return screens
    return [device_page(spec, iphone, k, s, *IPHONE[k], size, sub_size) for k, s in enumerate(screens)]


# ---------- iPad ----------

def tablet_status(im):
    """Takes out iPadOS's window-resize arc in the bottom-right corner (x 2008..2054, rows 2690..2752); the
    status bar keeps its '9:41 AM  Tue Nov 24' as iPadOS shows it."""
    a = arr(im)
    a[2684:2752, 1996:2064] = a[2684:2752, 1960:1980].mean(1)[:, None, :]
    return from_arr(a)


def ipad_set(raw, screens_only=False):
    shot = lambda n: tablet_status(Image.open(os.path.join(raw, n)).convert("RGBA"))
    spec = TABLET
    size, sub_size = set_sizes(spec, IPAD)
    p1, p2, p3, p4 = (shot(f"ipad-{k}.png") for k in range(1, 5))
    V = 2752 if screens_only else visible_rows(spec, ipad, 2064, 2752)
    a1 = arr(p1)
    sky1 = sky_of(a1, 30, 2600)
    status = tablet_status_bar(a1.copy())
    screens = [tablet_hours(p1), tablet_ten_days(p1, p2), tablet_tiles(p2, p3, V), tablet_list(p4, sky1),
               tablet_home(raw, status, V)]
    if screens_only:
        return screens
    return [device_page(spec, ipad, k, s, *IPAD[k], size, sub_size) for k, s in enumerate(screens)]


# ---------- Mac pages ----------

MW, MH = 2880, 1800
MAC_HEAD, MAC_SUB, MAC_HEAD_TOP = 108, 50, 96
DW, DH = 2048, 1320     # the MacBook's display as shown, in page pixels (the captures' 2x pixels, 1:1)
LID_TOP = 318


def mac_page(i, pool=0.46):
    """A Mac page's sky, headline and subhead (one size for the whole set, the same baseline). Returns it and
    the y of the bottom of the text."""
    c = sky(MW, MH, i, len(MAC), pool)
    head, sub = MAC[i]
    size = fit_size([h for h, _ in MAC], MAC_HEAD, MW - 400)
    sub_size = fit_sub([s for _, s in MAC], MAC_SUB, MW - 500)
    bottom = title(c, head, sub, MAC_HEAD_TOP, size, sub_size, MW - 400)
    return c, bottom


def traffic_lights(im, x0=28, cy=30, r=12, pitch=40):
    """macOS's close / minimise / zoom buttons, drawn 4x and scaled down, on a 2x window."""
    k = 4
    w, h = (x0 + pitch * 2 + r + 4) * k, (cy + r + 4) * k
    tl = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(tl)
    for i, (face, rim) in enumerate((((255, 95, 87), (224, 68, 62)), ((254, 188, 46), (222, 160, 32)),
                                     ((40, 200, 64), (30, 168, 50)))):
        cx, cyk, rk = (x0 + pitch * i) * k, cy * k, r * k
        d.ellipse([cx - rk, cyk - rk, cx + rk, cyk + rk], fill=rim + (255,))
        rk -= k
        d.ellipse([cx - rk, cyk - rk, cx + rk, cyk + rk], fill=face + (255,))
    im.alpha_composite(tl.resize((w // k, h // k), Image.LANCZOS))
    return im


MAC_K = 1.2     # the app's windows on the Mac pages: the 2x captures at 1.2x (a Mac at a "larger text" scaling)


def mac_window(im, lights=True, radius=26):
    """A 2x window capture (opaque, no frame) as macOS shows it: the overlay scroller at the right edge taken
    out (the window's own background, read a little to its left, carried across), the traffic lights in the
    hidden title bar, continuous corners, a fine light rim inside and a thin dark outline."""
    a = arr(im)
    W, H = im.size
    k = W / 984                                 # the scroller runs from row 128 down, right of x 948 (at 2x)
    y0, x0 = round(128 * k), W - round(36 * k)
    col = np.median(a[y0:, x0 - round(8 * k):x0], 1)
    a[y0:, x0:] = col[:, None, :]
    win = from_arr(a)
    if lights:
        traffic_lights(win, *(round(v * k) for v in (28, 30, 12, 40)))
    radius = radius * k
    m = squircle_mask(W, H, (0, 0, W, H), continuous(radius), 4)
    win.putalpha(m)
    win.alpha_composite(solid((W, H), (255, 255, 255, 96), ring(W, H, (1, 1, W - 1, H - 1), continuous(radius) - 1,
                                                              1.6, 4)))
    hl = np.zeros((H, W), np.float32)               # a top-edge highlight, as macOS lights a window's top rim
    hl[1:4] = np.linspace(0.2, 1, 3)[::-1, None] * np.sin(np.linspace(0, np.pi, W))[None, :] ** 0.3
    win.alpha_composite(solid((W, H), (255, 255, 255, 120),
                              Image.fromarray((hl * np.asarray(m, np.float32)).astype(np.uint8), "L")))
    win.alpha_composite(solid((W, H), (0, 0, 0, 90), ring(W, H, (0, 0, W, H), continuous(radius), 1.0, 4)))
    return win


def sun_glyph(px, colour=(255, 255, 255, 255)):
    """A small sun (the menu bar's sun.max) drawn 4x and scaled down."""
    k = 4
    n = px * k
    g = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(g)
    c = n / 2
    rr = n * 0.20
    d.ellipse([c - rr, c - rr, c + rr, c + rr], fill=colour)
    for j in range(8):
        t = j * np.pi / 4
        r0, r1 = n * 0.32, n * 0.47
        d.line([(c + r0 * np.cos(t), c + r0 * np.sin(t)), (c + r1 * np.cos(t), c + r1 * np.sin(t))],
               fill=colour, width=round(n * 0.085))
    return g.resize((px, px), Image.LANCZOS)


def pad_bottom(im, rows):
    """Gives a window capture `rows` more of its own background at the foot (its last row carried down), so
    the last card does not sit on the window's edge."""
    a = arr(im)
    a = np.concatenate([a, np.repeat(a[-1:], rows, 0)], 0)
    return from_arr(a)


MAC_DAYS = [232, 330, 428, 526, 624, 722, 820, 918, 1016, 1114]     # store-2's 10-day rows (°F tops): Today .. Thu


def mac_hero(load):
    """mac-1's window: the window down to just above the hourly card (its top edge at 898), so the reading is
    the one idea; the hero's last line (H:35°C L:26°C) ends at 827. The city's line drops its local time
    ('Thailand · 11:15 AM' becomes 'Thailand', re-centred), which would read against the menu bar's 9:41; the
    34°C and the °C line are raised to near-white."""
    a = arr(load("store-1-top.png"))
    if not AUTHENTIC:
        d = lift(a, (356, 425, 472, 459))
        erase(a, (356, 425, 596, 459))
        put(a, d, 475, 442)
    whiten(a, (520, 560, 740, 662), 1.0)
    whiten(a, (350, 796, 605, 833), 0.96, 0.4)
    return from_arr(a).crop((0, 0, 984, 878))


def mac_days(load):
    """mac-2's window: the 10-day card (edges 135..1219) with Today's cloud made the sun of the 'Clear' reading
    (the hourly 'Now' sun of store-1, at the daily icon size), the °C set right where the app rounded the other
    way (both Thu 78° / 25°C to Wed's 26°C, the second Wed's 92° / 34°C to Mon's 33°C) and raised to near-white,
    and 30 more rows of window under the card."""
    a, s = arr(load("store-2-days.png")), arr(load("store-1-top.png"))
    swap_icon(a, None, (92, 1106, 152, 1166), (190, 240, 253, 285), 0.9, src_arr=s)
    lo, hi = (310, 382), (788, 860)
    for (x0, x1), r0, r1 in ((lo, 330, 428), (lo, 330, 1114), (hi, 820, 1016)):
        copy_label(a, (x0, r0 + 36, x1, r0 + 63), (x0, r1 + 36, x1, r1 + 63))
    for r in MAC_DAYS:
        for x0, x1 in (lo, hi):
            whiten(a, (x0, r + 36, x1, r + 63), 0.93, 0.45)
    return pad_bottom(from_arr(a), 30)


def mac_tiles(load):
    """mac-3's window: the toolbar, then Visibility / Precipitation (edges 518..837) and Cloud cover / Moon
    (858..1230), 21 rows apart as in the app, and the window's own margin under them. Air quality and Averages
    (its '7° above normal' carries no unit) are left out; the secondary units are raised to near-white."""
    a = arr(load("store-3-tiles.png"))
    whiten(a, (54, 678, 162, 716), 0.94, 0.3)          # 29 km
    whiten(a, (508, 678, 724, 721), 0.94, 0.3)         # 0.0 mm today
    B = sky_of(a, 12, a.shape[0])
    H = 144 + (837 - 518 + 1) + 21 + (1230 - 858 + 1) + 10
    out = a[:H].copy()
    Bd = B[:H]
    fill(out, Bd, 136, H)
    stack(out, Bd, 144, [(a, B, 518, 837), (a, B, 858, 1230)], 21, H)
    return from_arr(out)


def mac_widgets(load, raw):
    """The Mac widget renders (the same views as on iOS) with their hourly 'Now' and 'Today' made to match the
    app and their figures set right (widgets_now, from the iOS Mumbai renders of the same session), and the
    Mumbai large and small ones from the iOS renders."""
    L, M = widgets_now(load("store-widget-large.png"), load("store-widget-medium.png"),
                       find_widget(raw, WIDGET_CITY2, "large"), find_widget(raw, WIDGET_CITY2, "medium"))
    mL, mM = mumbai_figures(find_widget(raw, WIDGET_CITY2, "large"), find_widget(raw, WIDGET_CITY2, "medium"))
    return dict(L=L, M=M, S=small_figures(load("store-widget-small.png")), mL=mL, mM=mM,
                mS=small_figures(find_widget(raw, WIDGET_CITY2, "small")))


def apple_mark(px, colour=(255, 255, 255, 255)):
    """The menu bar's Apple menu glyph, drawn 4x from circles and scaled down."""
    k = 4
    n = px * k
    m = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(m)
    d.ellipse([n * 0.08, n * 0.27, n * 0.56, n * 0.98], fill=255)
    d.ellipse([n * 0.40, n * 0.27, n * 0.88, n * 0.98], fill=255)
    d.ellipse([n * 0.14, n * 0.42, n * 0.82, n * 0.96], fill=255)
    d.ellipse([n * 0.74, n * 0.42, n * 1.08, n * 0.78], fill=0)        # the bite
    d.ellipse([n * 0.40, n * 0.88, n * 0.56, n * 1.02], fill=0)        # the dip at the foot
    d.ellipse([n * 0.40, n * 0.20, n * 0.56, n * 0.34], fill=0)        # the dip at the stalk
    leaf = Image.new("L", (n, n), 0)
    ImageDraw.Draw(leaf).ellipse([n * 0.46, n * 0.02, n * 0.66, n * 0.26], fill=255)
    m = Image.composite(Image.new("L", (n, n), 255), m, leaf.rotate(-35, center=(n * 0.56, n * 0.14)))
    g = Image.new("RGBA", (n, n), colour)
    g.putalpha(m)
    return g.resize((px, px), Image.LANCZOS)


def status_glyphs(px, kind):
    """Menu bar status icons, white, drawn 4x: 'wifi', 'battery' (full) or 'control' (two toggles)."""
    k = 4
    w = round(px * (1.9 if kind == "battery" else 1.3 if kind == "control" else 1.25)) * k
    h = px * k
    g = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(g)
    W = (255, 255, 255, 255)
    if kind == "wifi":
        cx, cy = w / 2, h * 0.92
        for i, r in enumerate((h * 0.86, h * 0.58, h * 0.30)):
            d.pieslice([cx - r, cy - r, cx + r, cy + r], 225, 315, fill=W)
            if i < 2:
                r2 = r - h * 0.15
                d.pieslice([cx - r2, cy - r2, cx + r2, cy + r2], 225, 315, fill=(0, 0, 0, 0))
    elif kind == "battery":
        bw = w * 0.88
        d.rounded_rectangle([0, h * 0.2, bw, h * 0.8], h * 0.16, fill=(255, 255, 255, 110))
        d.rounded_rectangle([h * 0.07, h * 0.27, bw - h * 0.07, h * 0.73], h * 0.11, fill=W)
        d.rounded_rectangle([bw + h * 0.05, h * 0.38, w, h * 0.62], h * 0.06, fill=(255, 255, 255, 110))
    else:
        for i in range(2):
            y0 = h * (0.16 + 0.40 * i)
            d.rounded_rectangle([w * 0.06, y0, w * 0.94, y0 + h * 0.28], h * 0.14, outline=W, width=round(h * 0.07))
            cx = w * (0.30 if i == 0 else 0.70)
            d.ellipse([cx - h * 0.09, y0 + h * 0.05, cx + h * 0.09, y0 + h * 0.23], fill=W)
    return g.resize((w // k, h // k), Image.LANCZOS)


MENU_H = 48


# The Mac menu bar's reading and date come from the captures' store-snapshot.json (the hero city, as the app's
# menu-bar extra shows it), so they match every screen. Set by main(); the defaults are only placeholders.
MENU_READING = "93° · 34°"
MENU_CLOCK = "Tue Nov 24  9:41 AM"


def app_round(v):
    """Rounds half away from zero, as the apps do (TempUnit.value)."""
    import math
    return int(math.floor(abs(v) + 0.5)) * (1 if v >= 0 else -1)


def read_menu_bar(raw):
    """Sets MENU_READING and MENU_CLOCK from raw/store-snapshot.json: the first city's reading in °F and °C, and
    the day the forecast was fetched (Swift dates count seconds from 2001-01-01 UTC)."""
    global MENU_READING, MENU_CLOCK
    import datetime
    import json
    path = os.path.join(raw, "store-snapshot.json")
    if not os.path.exists(path):
        return
    snap = json.load(open(path))
    c = snap["cities"][0]
    f = snap["forecasts"]["%.2f,%.2f" % (c["latitude"], c["longitude"])]
    t = f["now"]["temperature"]
    MENU_READING = f"{app_round(t * 9 / 5 + 32)}° · {app_round(t)}°"
    day = datetime.datetime(2001, 1, 1) + datetime.timedelta(seconds=f["fetchedAt"])
    MENU_CLOCK = f"{day:%a %b} {day.day}  9:41 AM"


def menu_bar(p, extra_open=False, s=1.0):
    """A macOS menu bar across the top of a desktop picture p (2x: 24 pt tall, everything scaled by s for a
    magnified view): the Apple menu, the app's menus, then the status items (the app's '93° · 34°' extra,
    Wi-Fi, battery, Control Center) and the clock. Returns the extra's (x0, x1) and the bar's height."""
    W = p.width
    bar_h = round(MENU_H * s)
    p.alpha_composite(Image.new("RGBA", (W, bar_h), (255, 255, 255, 40)))
    d = ImageDraw.Draw(p)
    f, fb = font("Medium", round(26 * s)), font("SemiBold", round(26 * s))
    x = 40 * s
    p.alpha_composite(apple_mark(round(30 * s)), (round(x), round(7 * s)))
    x += (30 + 44) * s
    for i, item in enumerate(["Two Degrees", "File", "Edit", "View", "Window", "Help"]):
        ff = fb if i == 0 else f
        d.text((x, bar_h / 2), item, font=ff, fill=(255, 255, 255, 255), anchor="lm")
        x += ff.getlength(item) + 44 * s
    clock = MENU_CLOCK
    x = W - 36 * s - f.getlength(clock)
    d.text((x, bar_h / 2), clock, font=f, fill=(255, 255, 255, 255), anchor="lm")
    for kind in ("control", "battery", "wifi"):
        g = status_glyphs(round(26 * s), kind)
        x -= 40 * s + g.width
        p.alpha_composite(g, (round(x), round((bar_h - g.height) / 2)))
    reading = MENU_READING
    rw = f.getlength(reading)
    item_w = (30 + 10) * s + rw
    x -= 44 * s + item_w
    if extra_open:
        pw, ph = round(item_w + 28 * s), round(38 * s)
        p.alpha_composite(solid((pw, ph), (255, 255, 255, 70), squircle_mask(pw, ph, (0, 0, pw, ph), continuous(9 * s), 4)),
                          (round(x - 14 * s), round(5 * s)))
    sg = sun_glyph(round(30 * s))
    p.alpha_composite(sg, (round(x), round((bar_h - sg.height) / 2)))
    d.text((x + 40 * s, bar_h / 2), reading, font=f, fill=(255, 255, 255, 255), anchor="lm")
    return (x - 14 * s, x + item_w + 14 * s), bar_h


def dock(p, tile, cx, s=1.0):
    """A macOS Dock along the foot of p holding the app's live Dock tile (store-dock.png, 256 px) with its
    running dot: a frosted shelf, everything scaled by s (1: a 56 pt tile at 2x). No other apps' icons are
    shown. Returns the tile's box."""
    ts = round(112 * s)
    pad = round(14 * s)
    w, h = ts + 2 * pad, ts + 2 * pad + round(8 * s)
    x0, y0 = round(cx - w / 2), p.height - h - round(8 * s)
    under = p.crop((x0, y0, x0 + w, y0 + h)).filter(ImageFilter.GaussianBlur(24 * s))
    shelf = Image.blend(under, Image.new("RGBA", (w, h), (255, 255, 255, 255)), 0.30)
    R = continuous(round(26 * s))
    shelf.putalpha(squircle_mask(w, h, (0, 0, w, h), R, 4))
    shadowed(p, shelf, x0, y0, ((round(20 * s), round(6 * s), 0.24),), (10, 20, 60))
    p.alpha_composite(solid((w, h), (255, 255, 255, 120), ring(w, h, (0, 0, w, h), R, 1.5 * s, 4)), (x0, y0))
    t = tile if ts == tile.width else down(tile, ts)
    shadowed(p, t, x0 + pad, y0 + pad, ((round(5 * s), round(2 * s), 0.25),), (10, 20, 60))
    dr = round(3.5 * s)
    ImageDraw.Draw(p).ellipse([cx - dr, y0 + h - round(9 * s) - dr, cx + dr, y0 + h - round(9 * s) + dr],
                              fill=(255, 255, 255, 230))
    return (x0 + pad, y0 + pad, x0 + pad + ts, y0 + pad + ts)


def desktop_wallpaper(w, h, seed):
    """A macOS-style wallpaper in the app's sky: deep blue at the top, soft violet and a warm coral light low
    down (the icon's degree ring)."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = np.clip(yy / h, 0, 1)
    img = ramp(t, [(0.0, (22, 40, 112)), (0.45, (60, 84, 176)), (0.8, (150, 120, 196)), (1.0, (236, 164, 150))])
    img = glow(img, xx, yy, w * 0.78, h * 0.30, w * 0.5, h * 0.4, (110, 150, 240), 0.35)
    img = glow(img, xx, yy, w * 0.20, h * 0.95, w * 0.6, h * 0.3, (255, 180, 150), 0.30)
    return to_image(img, seed).convert("RGBA")


def macbook(screen):
    """A 14" MacBook Pro in silver around a desktop picture: a black glass border (thin at the sides and top,
    a little more at the chin) with the camera notch at the top centre, inside a machined aluminium lid edge lit
    from the upper left with a polished near-white rim; under the lid the dark hinge and the base's front edge
    (wider than the lid, with the thumb scoop at its middle and its rounded foot). Returns the picture and the
    screen's offset in it."""
    sw, sh = screen.size
    side, top, chin, edge = 22, 26, 34, 6
    lw, lh = sw + 2 * (side + edge), sh + top + chin + 2 * edge
    base_w = round(lw * 1.11)
    hinge_h, deck_h = 10, 30
    W, H = base_w, lh + hinge_h + deck_h
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    lx = (W - lw) // 2
    # the base: hinge, then the deck's front edge
    hb = (lx + 36, lh - 4, lx + lw - 36, lh + hinge_h)
    hinge = np.zeros((H, W, 4), np.float32)
    hy = np.linspace(0, 1, hinge_h + 4)[:, None]
    hinge[hb[1]:hb[3], hb[0]:hb[2], :3] = (40 + 30 * hy)[..., None] * np.ones(3)
    hinge[hb[1]:hb[3], hb[0]:hb[2], 3] = 255
    out.alpha_composite(Image.fromarray(hinge.astype(np.uint8), "RGBA"))
    db = (0, lh + hinge_h - 2, W, H)
    dm = squircle_mask(W, H, db, 22, 3)
    t = np.clip((np.arange(H, dtype=np.float32) - db[1]) / (db[3] - db[1]), 0, 1)[:, None]
    u = np.linspace(0, 1, W, dtype=np.float32)[None, :]
    lum = 226 - 20 * u - 70 * t ** 1.6 + 18 * np.exp(-((t - 0.08) / 0.06) ** 2)
    out.alpha_composite(to_image(np.stack([lum - 2, lum, lum + 4, np.asarray(dm, np.float32)], -1), 12))
    # the thumb scoop: a shallow darker dip in the middle of the deck's front top edge
    scoop = np.zeros((H, W), np.float32)
    sx = np.linspace(-1, 1, 360)
    for j in range(10):
        scoop[db[1] + 2 + j, W // 2 - 180:W // 2 + 180] = np.clip(1 - sx ** 6, 0, 1) * (1 - j / 10) * 0.35
    out.alpha_composite(solid((W, H), (40, 40, 46, 255), Image.fromarray((scoop * 255).astype(np.uint8), "L")))
    # the lid
    lid = (lx, 0, lx + lw, lh)
    R = 34
    lm = squircle_mask(W, H, lid, continuous(R), 4)
    out.alpha_composite(metal(W, H, lm, 224, 196, -2, 9))
    out.alpha_composite(light_edge(W, H, lid, continuous(R), 2.4))
    glass = (lx + edge, edge, lx + lw - edge, lh - edge)
    out.alpha_composite(solid((W, H), (8, 8, 10, 255), squircle_mask(W, H, glass, continuous(R - edge), 4)))
    out.alpha_composite(solid((W, H), (52, 52, 56, 255), ring(W, H, glass, continuous(R - edge), 1.4, 4)))
    scr = screen.copy()
    sm = squircle_mask(sw, sh + 40, (0, 0, sw, sh + 40), continuous(16), 4).crop((0, 0, sw, sh))
    scr.putalpha(sm)
    sx0, sy0 = lx + edge + side, edge + top
    out.alpha_composite(scr, (sx0, sy0))
    # the notch, the height of the menu bar, with the camera in it
    nw, nh = 300, MENU_H - 6
    k = 4
    n = Image.new("RGBA", (nw * k, (nh + 20) * k), (0, 0, 0, 0))
    nd = ImageDraw.Draw(n)
    nd.rounded_rectangle([0, -40 * k, nw * k, nh * k], 16 * k, fill=(8, 8, 10, 255))
    cx, cy, cr = nw * k / 2, nh * k * 0.45, 7 * k
    nd.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=(22, 24, 30, 255))
    nd.ellipse([cx - cr * 0.5, cy - cr * 0.5, cx + cr * 0.5, cy + cr * 0.5], fill=(16, 22, 48, 255))
    nd.ellipse([cx - cr * 0.45, cy - cr * 0.55, cx - cr * 0.1, cy - cr * 0.2], fill=(70, 90, 150, 200))
    n = n.resize((nw, nh + 20), Image.LANCZOS).crop((0, 0, nw, nh))
    out.alpha_composite(n, (sx0 + (sw - nw) // 2, sy0))
    return out, (sx0, sy0)


def loupe(src, d):
    """A round magnifier: src (already at the size it is shown, d across or more) cut to a circle d across, with
    a glass rim (a bright outer ring and a faint dark inner one) and a soft inner shade at its edge."""
    k = 4
    m = Image.new("L", (d * k, d * k), 0)
    ImageDraw.Draw(m).ellipse([0, 0, d * k - 1, d * k - 1], fill=255)
    m = m.resize((d, d), Image.LANCZOS)
    im = src.crop(((src.width - d) // 2, (src.height - d) // 2, (src.width - d) // 2 + d, (src.height - d) // 2 + d))
    im = im.copy()
    im.putalpha(m)
    yy, xx = np.mgrid[0:d, 0:d].astype(np.float32)
    r = np.hypot(xx - d / 2, yy - d / 2) / (d / 2)
    shade = np.clip((r - 0.86) / 0.14, 0, 1) ** 2 * 0.35
    im.alpha_composite(solid((d, d), (0, 0, 0, 255), Image.fromarray((shade * np.asarray(m) ).astype(np.uint8), "L")))
    for width, col in ((9, (255, 255, 255, 240)), (2, (0, 0, 0, 60))):
        rg = Image.new("L", (d * k, d * k), 0)
        inset = 0 if width == 9 else 9 * k
        ImageDraw.Draw(rg).ellipse([inset, inset, d * k - 1 - inset, d * k - 1 - inset], outline=255, width=width * k)
        im.alpha_composite(solid((d, d), col, rg.resize((d, d), Image.LANCZOS)))
    return im


def desktop(seed, extra_open=False):
    p = desktop_wallpaper(DW, DH, seed)
    extra, bar_h = menu_bar(p, extra_open)
    return p, extra, bar_h


def on_desktop(p, im, x, y):
    """A window or widget on the desktop, with macOS's soft shadow and a tight contact shadow."""
    shadowed(p, im, x, y, ((44, 26, 0.45), (12, 6, 0.30), (2, 1, 0.30)), (8, 14, 46))


def centred(p, im, bar_h):
    x, y = (DW - im.width) // 2, bar_h + (DH - bar_h - im.height) // 2
    on_desktop(p, im, x, y)
    return x, y


def mac_on_page(i, screen):
    """The page's sky and text, and the MacBook under them, centred, its lid at LID_TOP on every page, with a
    page-tinted shadow under the base and a softer one round the lid."""
    c, _ = mac_page(i)
    mb, _ = macbook(screen)
    x = (MW - mb.width) / 2
    shadowed(c, mb, x, LID_TOP, ((60, 30, 0.40), (18, 10, 0.30), (4, 2, 0.30)), shadow_colour(i))
    return c


def mac_desktop_window(load, page):
    """mac-1..3: one app window centred on the desktop at MAC_K (the Dock hidden, as many people keep it): 1, the
    reading; 2, the 10-day card (scaled to keep 40 rows of desktop above and below); 3, the tiles."""
    p, _, bar_h = desktop(30 + page)
    im = (mac_hero, mac_days, mac_tiles)[page](load)
    room = DH - bar_h - 80
    k = min(MAC_K, room / im.height)
    im = up(im, k) if k > 1 else down(im, round(im.width * k))
    centred(p, mac_window(im), bar_h)
    return p


def mac_desktop_widgets(load, raw):
    """mac-4: the desktop with widgets in two balanced columns at their 2x size: on the left Bangkok's large
    widget over the two small ones (Bangkok, Mumbai); on the right Bangkok's medium over Mumbai's large."""
    p, _, bar_h = desktop(35)
    w = mac_widgets(load, raw)
    g = 48
    L, M, S, mS, mL = w["L"], w["M"], w["S"], w["mS"], w["mL"]
    tw = L.width + g + M.width
    th = L.height + g + S.height
    x0, y0 = (DW - tw) // 2, bar_h + (DH - bar_h - th) // 2
    widget_shadow(p, L, x0, y0)
    widget_shadow(p, S, x0, y0 + L.height + g)
    widget_shadow(p, mS, x0 + L.width - mS.width, y0 + L.height + g)
    x1 = x0 + L.width + g
    widget_shadow(p, M, x1, y0)
    widget_shadow(p, mL, x1, y0 + M.height + g)
    return p


def leader(p, a, b, r_dot=9):
    """A callout's leader line from a to b: 5 px white with round dots at both ends."""
    lay = Image.new("RGBA", (p.width * 2, p.height * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    A, B = (a[0] * 2, a[1] * 2), (b[0] * 2, b[1] * 2)
    d.line([A, B], fill=(255, 255, 255, 235), width=10)
    for (x, y), r in ((A, r_dot), (B, r_dot)):
        d.ellipse([x - r * 2, y - r * 2, x + r * 2, y + r * 2], fill=(255, 255, 255, 255))
    lay = lay.resize(p.size, Image.LANCZOS)
    sh = lay.getchannel("A").filter(ImageFilter.GaussianBlur(4)).point(lambda v: int(v * 0.35))
    shl = Image.new("RGBA", p.size, (10, 20, 60, 0))
    shl.putalpha(sh)
    p.alpha_composite(shl)
    p.alpha_composite(lay)


def toward(c, target, r):
    """The point on a circle (centre c, radius r) facing target."""
    dx, dy = target[0] - c[0], target[1] - c[1]
    n = max(np.hypot(dx, dy), 1)
    return (c[0] + dx / n * r, c[1] + dy / n * r)


def mac_desktop_menubar(load):
    """mac-5: the app's menu bar extra open ('93° · 34°', highlighted) with its panel hanging from it on a beak,
    and the Dock with the app's live tile. Two round magnifiers on the left are drawn, not enlarged: the menu
    bar's right end redrawn at 2x (with the black of the bezel above it, as it is), and the Dock tile at its
    full 256 px render on its shelf; a leader runs from each to the exact item."""
    p, (ix0, ix1), bar_h = desktop(36, extra_open=True)
    tile = load("store-dock.png")
    tile_box = dock(p, tile, DW / 2)
    panel = mac_window(down(mac_hero(load), 700), lights=False, radius=22)
    ex = (ix0 + ix1) / 2
    px = round(ex + 60 - panel.width)        # the item near the panel's right end, so the leader clears it
    py = bar_h + 50
    beak = Image.new("RGBA", (64 * 4, 26 * 4), (0, 0, 0, 0))
    ImageDraw.Draw(beak).polygon([(0, 26 * 4), (32 * 4, 0), (64 * 4, 26 * 4)], fill=tuple(int(v) for v in
                                                                                         arr(panel)[8, panel.width // 2]) + (255,))
    beak = beak.resize((64, 26), Image.LANCZOS)
    on_desktop(p, panel, px, py)
    p.alpha_composite(beak, (round(ex - 32), py - 25))
    s = 2.0
    d = 400
    # magnifier 1: the menu bar around the extra, redrawn at s with the wallpaper's top under it and the bezel
    big_w = round(DW * s)
    strip = desktop_wallpaper(DW, 220, 36).resize((big_w, round(220 * s)), Image.BICUBIC)
    (jx0, jx1), bh = menu_bar(strip, True, s)
    cx = (jx0 + jx1) / 2
    view = Image.new("RGBA", (d, d), (8, 8, 10, 255))
    top = round(d / 2 - bh / 2 - 40)
    view.alpha_composite(strip.crop((round(cx - d / 2), 0, round(cx - d / 2) + d, d - top)), (0, top))
    c1, c2 = (DW - 250, 440), (480, 860)     # the menu bar's to the right of the panel, the Dock's low left
    # magnifier 2: the Dock tile at 256 px on its shelf
    shelf = desktop_wallpaper(DW, DH, 36).crop((DW // 2 - 200, DH - 400, DW // 2 + 200, DH)).resize((d, d), Image.BICUBIC)
    sc = 256 / 112
    dk = Image.new("RGBA", (d, d), (0, 0, 0, 0))
    dk.alpha_composite(shelf)
    dock(dk, tile, d / 2, sc)
    view2 = dk.crop((0, 0, d, d))
    tc = ((tile_box[0] + tile_box[2]) / 2, tile_box[1] - 6)
    leader(p, toward(c1, (ex, bar_h), d / 2 + 4), (ex, bar_h - 4))
    leader(p, toward(c2, tc, d / 2 + 4), (tc[0], tc[1]))
    for c, v in ((c1, view), (c2, view2)):
        shadowed(p, loupe(v, d), c[0] - d / 2, c[1] - d / 2, ((30, 14, 0.40), (6, 3, 0.25)), (10, 20, 60))
    return p


def mac_devices(load, raw):
    """For the family template: the five MacBooks of make_mac_set on a clear ground (the template sets them on
    its own sky, under its own headline)."""
    screens = [mac_desktop_window(load, 0), mac_desktop_window(load, 1), mac_desktop_window(load, 2),
               mac_desktop_widgets(load, raw), mac_desktop_menubar(load)]
    return [macbook(sc)[0] for sc in screens]


def make_mac_set(load, raw):
    """The Mac set (2880x1800) from the store-*.png captures (load: name -> image) and the iOS widget renders in
    raw (for the Mumbai widgets): five views of one MacBook Pro at one scale and place, the same desktop under
    the same menu bar, under the same skies and type scale as the iOS sets."""
    screens = [mac_desktop_window(load, 0), mac_desktop_window(load, 1), mac_desktop_window(load, 2),
               mac_desktop_widgets(load, raw), mac_desktop_menubar(load)]
    return [mac_on_page(i, s) for i, s in enumerate(screens)]


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


def mac_set(source, raw=DEFAULT_RAW):
    """The Mac set from a folder (or git:<branch>): the store-*.png captures when present (make_mac_set), else
    the older panel-*.png snapshots."""
    load = loader(source)
    if names_in(source, r"store-1-top\.png"):
        return make_mac_set(load, raw)
    return mac_pages(load)


# ---------- main ----------

def save(im, name):
    path = os.path.join(OUT, name)
    im.convert("RGB").save(path, optimize=True)
    print(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("raw", nargs="?", default=DEFAULT_RAW, help="folder of iPhone/iPad captures and widget renders")
    ap.add_argument("--mac", default=DEFAULT_MAC, help="folder (or git:<branch>) of Mac captures")
    ap.add_argument("--only", default="mac", help="comma list of iphone, ipad, mac (iPhone and iPad: the old style)")
    ap.add_argument("--screens", help="write only the finished screens (iphone-N, ipad-N) and MacBooks (mac-N, "
                    "transparent) to this folder, for scripts/store-frames.mjs (the family template)")
    a = ap.parse_args()
    only = a.only.split(",")
    os.makedirs(OUT, exist_ok=True)
    read_menu_bar(a.raw)
    if a.screens:
        os.makedirs(a.screens, exist_ok=True)
        sets = [("iphone", lambda: iphone_set(a.raw, True)), ("ipad", lambda: ipad_set(a.raw, True)),
                ("mac", lambda: mac_devices(loader(a.mac), a.raw))]
        for name, make in sets:
            if name in only:
                for k, im in enumerate(make(), 1):
                    path = os.path.join(a.screens, f"{name}-{k}.png")
                    (im if name == "mac" else im.convert("RGB")).save(path)
                    print(path, im.size)
        return
    if "iphone" in only:
        for k, im in enumerate(iphone_set(a.raw), 1):
            save(im, f"iphone-{k}.png")
    if "ipad" in only:
        for k, im in enumerate(ipad_set(a.raw), 1):
            save(im, f"ipad-{k}.png")
    if "mac" in only and a.mac:
        for k, im in enumerate(mac_set(a.mac, a.raw), 1):
            save(im, f"mac-{k}.png")


if __name__ == "__main__":
    main()
