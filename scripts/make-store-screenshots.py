"""Makes the App Store screenshots for iPhone (6.9", 1320x2868), iPad (13", 2064x2752) and Mac (2880x1800)
in one system: the app icon's sky, a large white headline with a short subhead, and the real app in a
device frame drawn here, large and running off the bottom edge.

Writes appstore/screenshots/iphone-1..5.png, ipad-1..4.png and (with --mac) mac-1..5.png.

Usage:
  python3 scripts/make-store-screenshots.py [RAW]              iPhone and iPad sets from RAW
  python3 scripts/make-store-screenshots.py [RAW] --mac DIR    also the Mac set from DIR
  python3 scripts/make-store-screenshots.py --only mac --mac DIR

RAW holds iphone-1..4.png (1320x2868), ipad-1..4.png (2064x2752) and the 2x widget renders
widget-<n><city>-{small,medium,large,lock-circular,lock-rectangular,lock-inline}.png.
DIR holds the Mac captures: the store-*.png files from the ci-shots branch (see mac_store_pages), or the
older panel-*.png snapshots (see mac_pages). "--mac git:ci-shots" reads them from origin/ci-shots.

Every capture is only ever scaled down (LANCZOS); all text is drawn at the final size. Needs Pillow and numpy.
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
SUB = (255, 255, 255, 191)   # subhead: white at 75%


# ---------- copy ----------

IPHONE = [
    ("Every temperature,\nin °F and °C", "Fahrenheit and Celsius, side by side."),
    ("Ten days\non one scale", "Every low and high on one bar, in both units."),
    ("Twelve tiles\nof detail", "Sunrise colour, air quality, cloud and the moon."),
    ("All your cities\nat a glance", "Up to 20 places, each on its own sky."),
    ("Widgets for\nevery screen", "Home Screen and Lock Screen, in both units."),
]

IPAD = [
    ("Every temperature,\nin °F and °C", "Fahrenheit and Celsius, side by side."),
    ("Ten days on one scale", "Every low and high on one bar, in both units."),
    ("Twelve tiles of detail", "Sunrise colour, air quality, cloud and the moon."),
    ("All your cities at a glance", "Up to 20 places, each on its own sky."),
]

MAC = [
    ("Every temperature in °F and °C", "Press F or C to choose which unit is large"),
    ("Ten days on one scale", "Every low and high on one bar, beside the large widget"),
    ("Twelve tiles of detail", "Visibility, precipitation, cloud at each height, the moon and more"),
    ("Widgets on your desktop", "Small, medium and large. Each can show a city of its own."),
    ("In your menu bar and Dock", "The temperature in both units, always a glance away"),
]


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


SKY = [(0.0, (112, 170, 236)), (0.28, (82, 138, 222)), (0.62, (46, 92, 186)), (1.0, (24, 48, 122))]


def sky_array(w, h):
    """The app icon's sky (#72AAE9 -> #204294): bright at the top for the headline, deepening downwards,
    with a soft light behind the headline. One field for every page and every size, so the set matches."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    s = max(w, h)
    # Mostly vertical, a touch of the icon's diagonal.
    t = np.clip((yy / h) * 0.9 + (xx / w - 0.5) * 0.12 + 0.03, 0, 1)
    img = ramp(t, SKY)
    img = glow(img, xx, yy, w * 0.5, -h * 0.02, s * 0.55, s * 0.30, (176, 214, 250), 0.42)   # light at the top
    img = glow(img, xx, yy, w * 0.08, h * 1.0, s * 0.45, s * 0.30, (230, 112, 128), 0.10)    # coral, the ring
    return img


def sky(w, h):
    return to_image(sky_array(w, h)).convert("RGBA")


# ---------- shapes ----------

def squircle_mask(w, h, box, R, n=5.0):
    """Anti-aliased mask of a rectangle with continuous (superellipse) corners, computed analytically.
    R is how far along each edge the corner curve starts; n sets its shape (5 is close to Apple's)."""
    x0, y0, x1, y1 = box
    cx, cy, hw, hh = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2
    R = min(R, hw, hh)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    xx += 0.5
    yy += 0.5
    ax, ay = np.abs(xx - cx), np.abs(yy - cy)
    qx, qy = np.maximum(ax - (hw - R), 0) / R, np.maximum(ay - (hh - R), 0) / R
    f = qx ** n + qy ** n
    g = (n / R) * np.sqrt(qx ** (2 * n - 2) + qy ** (2 * n - 2))
    corner = (qx > 0) | (qy > 0)
    d = np.where(corner, (f ** (1 / n) - 1) * R, np.maximum(ax - hw, ay - hh))
    # Near the curve, the first-order distance is better; far away the radial one is fine.
    d = np.where(corner & (g > 0), np.where(np.abs(f - 1) < 0.5, (f - 1) / np.maximum(g, 1e-9), d), d)
    a = np.clip(0.5 - d, 0, 1)
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


def shadowed(canvas, im, x, y, layers=((70, 50, 0.42), (18, 12, 0.28)), colour=(6, 14, 44)):
    """Puts a picture down with a soft shadow under it, lit from the top."""
    pad = max(b for b, _, _ in layers) * 3
    a = Image.new("L", (im.width + pad * 2, im.height + pad * 2), 0)
    a.paste(im.getchannel("A"), (pad, pad))
    for blur, drop, opacity in layers:
        s = a.filter(ImageFilter.GaussianBlur(blur)).point(lambda v, o=opacity: int(v * o + 0.5))
        layer = Image.new("RGBA", s.size, colour + (0,))
        layer.putalpha(s)
        canvas.alpha_composite(layer, (int(round(x)) - pad, int(round(y)) - pad + drop))
    canvas.alpha_composite(im, (int(round(x)), int(round(y))))


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


def title(canvas, head, sub, top, size, sub_size, max_w, cx=None):
    """Headline (lines split at '\\n') and subhead, centred, the headline's cap top at `top`.
    Returns the y of the bottom of the subhead's descenders."""
    cx = canvas.width / 2 if cx is None else cx
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    lines = head.split("\n")
    while True:
        f = font("SemiBold", size)
        track = -0.02 * size
        if max(text_width(l, f, track) for l in lines) <= max_w:
            break
        size -= 2
    cap = size * 0.727   # Inter's cap height
    lead = round(size * 1.06)
    y = top + cap
    for line in lines:
        draw_line(d, cx, y, line, f, WHITE, track)
        y += lead
    y -= lead
    if sub:
        fs = font("Medium", sub_size)
        st = -0.006 * sub_size
        y += round(sub_size * 1.55)
        for line in wrap(sub, fs, st, max_w):
            draw_line(d, cx, y, line, fs, SUB, st)
            y += round(sub_size * 1.28)
        y -= round(sub_size * 1.28)
    canvas.alpha_composite(layer)
    return y + round(sub_size * 0.25)


# ---------- the app icon ----------

def app_icon(px, shadow=True):
    """The approved icon at px across, masked to the iOS icon shape."""
    tile = down(Image.open(ICON).convert("RGBA"), px)
    tile.putalpha(squircle_mask(px, px, (0, 0, px, px), px * 0.36, 4.6))
    return tile


# ---------- devices ----------

def iphone(shot, sw):
    """An iPhone 16 Pro Max drawn around a 1320-wide capture shown sw wide: a dark titanium band with a
    polished outer edge and a faint inner highlight, a thin black border, the screen with continuous
    corners concentric with the body, and low-key side buttons. The capture brings the Dynamic Island."""
    scr = down(shot, sw)
    sh = scr.height
    band = max(6, round(sw * 0.0105))
    border = round(sw * 0.029)
    btn = max(3, round(sw * 0.0045))
    Rs = sw * 0.192
    side = band + border
    W, H = sw + 2 * side + 2 * btn, sh + 2 * side
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))

    # Side buttons, just proud of the frame (drawn first, the body covers their inner ends).
    def button(left, a, b):
        y0, y1 = H * a, H * b
        x0 = 0 if left else W - btn * 4
        m = squircle_mask(W, H, (x0, y0, x0 + btn * 4, y1), btn * 1.6, 4)
        out.alpha_composite(solid((W, H), (58, 58, 64, 255), m))
    button(True, 0.178, 0.204)    # action button
    button(True, 0.243, 0.300)    # volume up
    button(True, 0.318, 0.375)    # volume down
    button(False, 0.270, 0.360)   # side button
    button(False, 0.548, 0.600)   # camera control

    body = (btn, 0, W - btn, H)
    Rb = Rs + side
    m = squircle_mask(W, H, body, Rb)
    t = np.linspace(0, 1, H, dtype=np.float32)[:, None]
    u = np.linspace(0, 1, W, dtype=np.float32)[None, :]
    lum = 84 - 30 * t + 10 * np.cos((u - 0.5) * np.pi) - 6   # dark titanium, lit from above
    ti = np.stack([lum, lum, lum * 1.05 + 2, np.asarray(m, np.float32)], -1)
    out.alpha_composite(to_image(ti, 3))
    # The polished outer edge catches the light.
    out.alpha_composite(solid((W, H), (190, 190, 200, 120), ring(W, H, body, Rb, 2.2)))
    inner = (btn + band, band, W - btn - band, H - band)
    out.alpha_composite(solid((W, H), (5, 5, 7, 255), squircle_mask(W, H, inner, Rb - band)))
    # A hairline of light where the titanium meets the glass.
    out.alpha_composite(solid((W, H), (255, 255, 255, 46), ring(W, H, inner, Rb - band, 1.6)))
    scr.putalpha(squircle_mask(sw, sh, (0, 0, sw, sh), Rs))
    out.alpha_composite(scr, (btn + side, side))
    return out


def ipad(shot, sw):
    """An iPad Pro 13" drawn around a capture shown sw wide: a thin, even black border, a fine dark
    aluminium edge and rounded corners concentric with the screen's."""
    scr = down(shot, sw)
    sh = scr.height
    edge = max(4, round(sw * 0.0035))
    border = round(sw * 0.027)
    Rs = sw * 0.040
    side = edge + border
    W, H = sw + 2 * side, sh + 2 * side
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    Rb = Rs + side
    m = squircle_mask(W, H, (0, 0, W, H), Rb)
    t = np.linspace(0, 1, H, dtype=np.float32)[:, None] * np.ones((1, W), np.float32)
    lum = 98 - 34 * t
    out.alpha_composite(to_image(np.stack([lum, lum, lum * 1.04 + 2, np.asarray(m, np.float32)], -1), 4))
    out.alpha_composite(solid((W, H), (200, 200, 210, 110), ring(W, H, (0, 0, W, H), Rb, 2)))
    inner = (edge, edge, W - edge, H - edge)
    out.alpha_composite(solid((W, H), (6, 6, 8, 255), squircle_mask(W, H, inner, Rb - edge)))
    out.alpha_composite(solid((W, H), (255, 255, 255, 34), ring(W, H, inner, Rb - edge, 1.4)))
    cam = border * 0.16
    ImageDraw.Draw(out).ellipse([W / 2 - cam, side / 2 - cam, W / 2 + cam, side / 2 + cam], fill=(26, 28, 36, 255))
    scr.putalpha(squircle_mask(sw, sh, (0, 0, sw, sh), Rs))
    out.alpha_composite(scr, (side, side))
    return out


DEVICE_SHADOW = ((90, 60, 0.40), (26, 16, 0.26))


# ---------- iPhone pages ----------

PW, PH = 1320, 2868
P_HEAD, P_SUB, P_MAXW = 128, 50, PW - 200
P_TOP = 196          # cap top of the headline on pages 2-5
P_DEVICE = 760       # top of the device on pages 2-4
P_SW = 1092          # screen width: the device is 1180 wide, 89% of the page


def phone_hero(shot, head, sub):
    c = sky(PW, PH)
    icon = app_icon(224)
    shadowed(c, icon, (PW - icon.width) / 2, 150, ((30, 18, 0.30), (8, 4, 0.18)))
    bottom = title(c, head, sub, 150 + 224 + 92, P_HEAD, P_SUB, P_MAXW)
    dev = iphone(shot, P_SW)
    shadowed(c, dev, (PW - dev.width) / 2, bottom + 96, DEVICE_SHADOW)
    return c


def phone_feature(shot, head, sub):
    c = sky(PW, PH)
    title(c, head, sub, P_TOP, P_HEAD, P_SUB, P_MAXW)
    dev = iphone(shot, P_SW)
    shadowed(c, dev, (PW - dev.width) / 2, P_DEVICE, DEVICE_SHADOW)
    return c


def phone_closeup(shot, head, sub, sw=1236):
    """The device larger and closer, its sides just inside the page: for a screen whose content sits in
    its upper part (the city list), so the feature reads bigger."""
    c = sky(PW, PH)
    title(c, head, sub, P_TOP, P_HEAD, P_SUB, P_MAXW)
    dev = iphone(shot, sw)
    shadowed(c, dev, (PW - dev.width) / 2, P_DEVICE, DEVICE_SHADOW)
    return c


def find_widget(raw, city, kind):
    hits = sorted(glob.glob(os.path.join(raw, f"widget-*{city}-{kind}.png")))
    if not hits:
        raise FileNotFoundError(f"no widget-*{city}-{kind}.png in {raw}")
    return Image.open(hits[0]).convert("RGBA")


def wallpaper(w, h, stops, glows, seed):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    s = max(w, h)
    t = np.clip(yy / h * 0.85 + xx / w * 0.15, 0, 1)
    img = ramp(t, stops)
    for gx, gy, gr, colour, strength in glows:
        img = glow(img, xx, yy, w * gx, h * gy, s * gr, s * gr, colour, strength)
    return img


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


def panel(c, x0, y0, x1, y1, field, R=120):
    w, h = x1 - x0, y1 - y0
    im = to_image(np.concatenate([field, np.full(field.shape[:2] + (1,), 255, np.float32)], -1), 11)
    im.putalpha(squircle_mask(w, h, (0, 0, w, h + (R * 2 if y1 >= c.height else 0)), R))
    shadowed(c, im, x0, y0, ((60, 36, 0.32), (16, 8, 0.18)))


def phone_widgets(raw, head, sub):
    """Home Screen widgets (large and medium Honolulu, small Sydney, Auckland, Honolulu) on a bright
    wallpaper made from the app's clear-day sky, then the Lock Screen widgets on its dusk sky below.
    Widgets are drawn at their 2x render size: never scaled up."""
    c = sky(PW, PH)
    title(c, head, sub, P_TOP, P_HEAD, P_SUB, P_MAXW)

    # Home Screen: a two-column grid, 728 | 340, both columns 1156 tall.
    large = find_widget(raw, "honolulu", "large")
    medium = find_widget(raw, "honolulu", "medium")
    smalls = [find_widget(raw, city, "small") for city in ("sydney", "auckland", "honolulu")]
    gap = 52
    gw = large.width + gap + smalls[0].width
    gh = large.height + gap + medium.height
    sgap = (gh - 3 * smalls[0].height) / 2
    pad = 40
    px0, py0 = (PW - gw) / 2 - pad, 720
    px0, py0 = round(px0), py0
    pw_, ph_ = gw + 2 * pad, gh + 2 * pad
    home = wallpaper(pw_, ph_, [(0, (196, 226, 252)), (0.5, (142, 194, 244)), (1, (96, 150, 226))],
                     [(0.92, 0.02, 0.42, (255, 226, 180), 0.75), (0.1, 0.95, 0.5, (250, 170, 160), 0.30)], 5)
    panel(c, px0, py0, px0 + pw_, py0 + ph_, home, R=112)
    x, y = px0 + pad, py0 + pad
    ws = ((30, 22, 0.30), (8, 5, 0.18))
    shadowed(c, large, x, y, ws)
    shadowed(c, medium, x, y + large.height + gap, ws)
    for i, s in enumerate(smalls):
        shadowed(c, s, x + large.width + gap, y + i * (s.height + sgap), ws)

    # Lock Screen: dusk wallpaper running off the bottom, the inline widget, the time, the widget row.
    ly0 = py0 + ph_ + 60
    lock = wallpaper(pw_, PH - ly0, [(0, (52, 86, 168)), (0.6, (30, 52, 120)), (1, (18, 30, 80))],
                     [(0.85, 0.1, 0.5, (238, 132, 132), 0.30), (0.1, 0.0, 0.4, (120, 170, 236), 0.35)], 6)
    panel(c, px0, ly0, px0 + pw_, PH, lock, R=112)
    d = ImageDraw.Draw(c)
    inline = lock_glass(find_widget(raw, "honolulu", "lock-inline"), False)
    cy = ly0 + 70
    c.alpha_composite(inline, ((PW - inline.width) // 2, cy))
    clock = font("SemiBold", 250)
    draw_line(d, PW / 2, cy + inline.height + 34 + 250 * 0.727, "9:41", clock, (255, 255, 255, 235), -5)
    row = [lock_glass(find_widget(raw, "honolulu", "lock-circular"), True),
           lock_glass(find_widget(raw, "sydney", "lock-circular"), True),
           lock_glass(find_widget(raw, "honolulu", "lock-rectangular"), False)]
    rgap = 36
    rw = sum(r.width for r in row) + rgap * (len(row) - 1)
    rx, ry = (PW - rw) / 2, cy + inline.height + 34 + 250 * 0.727 + 70
    for r in row:
        c.alpha_composite(r, (round(rx), round(ry + (row[0].height - r.height) / 2)))
        rx += r.width + rgap
    return c


# ---------- iPad pages ----------

TW, TH = 2064, 2752
T_HEAD, T_SUB, T_MAXW = 136, 54, TW - 360
T_TOP = 190
T_DEVICE = 640
T_SW = 1760          # the device is 1855 wide, 90% of the page


def tablet_hero(shot, head, sub):
    c = sky(TW, TH)
    icon = app_icon(220)
    shadowed(c, icon, (TW - icon.width) / 2, 140, ((30, 18, 0.30), (8, 4, 0.18)))
    bottom = title(c, head, sub, 140 + 220 + 88, T_HEAD, T_SUB, T_MAXW)
    dev = ipad(shot, T_SW)
    shadowed(c, dev, (TW - dev.width) / 2, bottom + 100, DEVICE_SHADOW)
    return c


def tablet_feature(shot, head, sub):
    c = sky(TW, TH)
    bottom = title(c, head, sub, T_TOP, T_HEAD, T_SUB, T_MAXW)
    dev = ipad(shot, T_SW)
    shadowed(c, dev, (TW - dev.width) / 2, max(T_DEVICE, bottom + 110), DEVICE_SHADOW)
    return c


# ---------- Mac pages ----------

MW, MH = 2880, 1800


def mac_page(i):
    c = sky(MW, MH)
    head, sub = MAC[i]
    bottom = title(c, head, sub, 150, 118, 52, MW - 400)
    return c, bottom


def mac_store_pages(load, names):
    """The Mac set from the ci-shots store-*.png captures (each a finished window or scene at 2x, in the
    order of MAC): each under its headline, centred in the space below, scaled down only if it must be."""
    shots = []
    for i, name in enumerate(names[:len(MAC)]):
        c, top = mac_page(i)
        im = load(name)
        room_w, room_h = MW - 320, MH - top - 120
        k = min(1.0, room_w / im.width, room_h / im.height)
        if k < 1:
            im = down(im, round(im.width * k))
        shadowed(c, im, (MW - im.width) / 2, top + 80 + (room_h - im.height) / 2,
                 ((70, 40, 0.45), (12, 6, 0.32)))
        shots.append(c)
    return shots


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
    """The Mac set from a folder (or git:<branch>): store-*.png captures when present, else the older
    panel-*.png snapshots."""
    load = loader(source)
    store = names_in(source, r"store-\d+.*\.png")
    store.sort(key=lambda n: int(re.search(r"\d+", n).group()))
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
    shot = lambda n: Image.open(os.path.join(a.raw, n)).convert("RGBA")
    if "iphone" in only:
        save(phone_hero(shot("iphone-1.png"), *IPHONE[0]), "iphone-1.png")
        save(phone_feature(shot("iphone-2.png"), *IPHONE[1]), "iphone-2.png")
        save(phone_feature(shot("iphone-3.png"), *IPHONE[2]), "iphone-3.png")
        save(phone_closeup(shot("iphone-4.png"), *IPHONE[3]), "iphone-4.png")
        save(phone_widgets(a.raw, *IPHONE[4]), "iphone-5.png")
    if "ipad" in only:
        save(tablet_hero(shot("ipad-1.png"), *IPAD[0]), "ipad-1.png")
        for i in range(2, 5):
            save(tablet_feature(shot(f"ipad-{i}.png"), *IPAD[i - 1]), f"ipad-{i}.png")
    if "mac" in only and a.mac:
        for i, im in enumerate(mac_set(a.mac), 1):
            save(im, f"mac-{i}.png")


if __name__ == "__main__":
    main()
