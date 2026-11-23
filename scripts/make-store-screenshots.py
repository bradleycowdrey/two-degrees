"""Makes the App Store screenshots for iPhone (6.9", 1320x2868), iPad (13", 2064x2752) and Mac (2880x1800)
in one style: a short white headline on the app icon's sky, and the real app in a device frame drawn here.

Writes appstore/screenshots/iphone-1..5.png, ipad-1..4.png and mac-1..5.png.

Usage: python3 scripts/make-store-screenshots.py [folder of phone shots] [folder of Mac snapshots]
Without folders, it reads the iPhone and iPad shots (and widget-*.png) from origin/appstore-screenshots and
the Mac snapshots from origin/ci-shots (git fetch origin appstore-screenshots ci-shots first).
Needs Pillow and numpy.
"""
import importlib.util
import io
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "appstore", "screenshots")
FONTS = os.path.join(ROOT, "Resources", "Fonts")
WHITE = (255, 255, 255)

# The Mac snapshot helpers (banner and update dot removal, window corners, window shadow).
_spec = importlib.util.spec_from_file_location("macshots", os.path.join(ROOT, "scripts", "make-mac-screenshots.py"))
mac = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mac)


# ---------- sources ----------

def loader(folder, branch):
    def load(name):
        if folder:
            return Image.open(os.path.join(folder, name)).convert("RGBA")
        data = subprocess.run(["git", "-C", ROOT, "show", f"origin/{branch}:{name}"], check=True, capture_output=True).stdout
        return Image.open(io.BytesIO(data)).convert("RGBA")
    return load


def font(weight, size):
    return ImageFont.truetype(os.path.join(FONTS, f"Inter-{weight}.ttf"), size)


# ---------- background ----------

def sky(w, h):
    """The app icon's sky: sky blue at the top left (#72AAE9 family), down to the icon's deep blue (#204294)
    and a little past it at the bottom, so white text and the device frames stay crisp. A faint coral glow
    low on one side, the degree ring's colour. Dithered so the gradient never bands."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = np.clip((yy / h) * 0.8 + (xx / w) * 0.2, 0, 1)
    stops = [(0.0, (98, 150, 222)), (0.45, (50, 92, 178)), (1.0, (22, 42, 104))]
    img = np.zeros((h, w, 3), np.float32)
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        m = (t >= t0) & (t <= t1)
        k = ((t - t0) / (t1 - t0))[..., None]
        k = k * k * (3 - 2 * k)
        img = np.where(m[..., None], np.array(c0) + (np.array(c1) - np.array(c0)) * k, img)

    def glow(cx, cy, r, colour, strength):
        d = np.sqrt(((xx - cx) / r) ** 2 + ((yy - cy) / r) ** 2)
        a = (np.clip(1 - d, 0, 1) ** 2 * strength)[..., None]
        return img * (1 - a) + np.array(colour, np.float32) * a

    s = max(w, h)
    img = glow(w * 0.3, -h * 0.05, s * 0.55, (140, 186, 240), 0.14)    # light from the top left
    img = glow(w * 0.05, h * 1.02, s * 0.55, (236, 104, 118), 0.14)     # coral, the degree ring's colour
    img = glow(w * 0.98, h * 0.95, s * 0.40, (255, 200, 160), 0.07)
    img += np.random.default_rng(2).uniform(-1.2, 1.2, img.shape)
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


# ---------- text ----------

def text_width(text, f, track):
    return f.getlength(text) + track * (len(text) - 1)


def draw_line(d, cx, y, text, f, fill, track):
    """Draws one centred line with tight tracking, keeping Inter's kerning."""
    x0 = cx - text_width(text, f, track) / 2
    for i, ch in enumerate(text):
        # Where this glyph sits in the kerned run: the run up to and including it, less its own advance.
        # (Using the run before it would drop the kerning pair with the previous glyph, as in "Te n".)
        x = f.getlength(text[:i + 1]) - f.getlength(ch)
        d.text((x0 + x + track * i, y), ch, font=f, fill=fill, anchor="ls")


def headline(canvas, title, sub, top, size, sub_size, max_w):
    """A headline of one or two lines (split at '\\n') and an optional subhead. Returns the y under it."""
    d = ImageDraw.Draw(canvas)
    lines = title.split("\n")
    while True:
        f = font("SemiBold", size)
        track = -0.022 * size
        if max(text_width(l, f, track) for l in lines) <= max_w:
            break
        size -= 2
    asc = f.getmetrics()[0]
    lead = round(size * 1.12)
    y = top + asc
    for line in lines:
        draw_line(d, canvas.width / 2, y, line, f, WHITE, track)
        y += lead
    y = y - lead + f.getmetrics()[1]
    if sub:
        fs = font("Medium", sub_size)
        while text_width(sub, fs, -0.008 * sub_size) > max_w:
            sub_size -= 1
            fs = font("Medium", sub_size)
        y += round(sub_size * 0.55) + fs.getmetrics()[0]
        draw_line(d, canvas.width / 2, y, sub, fs, (255, 255, 255, 178), -0.008 * sub_size)
        y += fs.getmetrics()[1]
    return y


def over(canvas, draw_fn):
    """Draws translucent text on its own layer so alpha blends instead of replacing pixels."""
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    out = draw_fn(layer)
    canvas.alpha_composite(layer)
    return out


def title_block(canvas, title, sub, band, size, sub_size, max_w, lift=0.04):
    """Draws the headline and subhead centred in the band above the device (a touch above centre, so it
    hangs from the top), whatever their number of lines, so devices sit at the same place on every page."""
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    headline(layer, title, sub, top=0, size=size, sub_size=sub_size, max_w=max_w)
    x0, y0, x1, y1 = layer.getbbox()
    ink = layer.crop((0, y0, canvas.width, y1))
    y = round((band - (y1 - y0)) / 2 - band * lift)
    canvas.alpha_composite(ink, (0, y))


# ---------- shapes ----------

SS = 4   # supersampling for every curved edge


def squircle_points(x0, y0, x1, y1, r, n=5.0, k=1.42):
    """An Apple-style continuous-corner rectangle as a polygon: each corner is a superellipse that starts
    further along the edge than a plain arc would, so the curve eases in."""
    R = min(r * k, (x1 - x0) / 2, (y1 - y0) / 2)
    pts = []
    steps = 48
    corners = [(x1 - R, y0 + R, 1, -1), (x1 - R, y1 - R, 1, 1), (x0 + R, y1 - R, -1, 1), (x0 + R, y0 + R, -1, -1)]
    for ci, (cx, cy, sx, sy) in enumerate(corners):
        rng = range(steps + 1)
        for j in rng:
            a = (math.pi / 2) * j / steps
            if ci % 2 == 0:
                a = math.pi / 2 - a
            ca, sa = math.cos(a), math.sin(a)
            px = cx + sx * R * (ca ** (2 / n))
            py = cy + sy * R * (sa ** (2 / n))
            pts.append((px, py))
    # order: top-right corner runs from the top edge to the right edge, and so on, clockwise
    return pts


def shape_mask(size, box, r, continuous=True):
    w, h = size
    m = Image.new("L", (w * SS, h * SS), 0)
    d = ImageDraw.Draw(m)
    x0, y0, x1, y1 = [v * SS for v in box]
    if continuous:
        d.polygon(squircle_points(x0, y0, x1, y1, r * SS), fill=255)
    else:
        d.rounded_rectangle([x0, y0, x1, y1], r * SS, fill=255)
    return m.resize(size, Image.LANCZOS)


def fill(size, colour, mask):
    im = Image.new("RGBA", size, colour)
    im.putalpha(ImageChops.multiply(mask, im.getchannel("A")))
    return im


def vgradient(size, top, bottom):
    w, h = size
    t = np.linspace(0, 1, h, dtype=np.float32)[:, None, None]
    arr = np.array(top, np.float32) * (1 - t) + np.array(bottom, np.float32) * t
    return Image.fromarray(np.repeat(arr, w, axis=1).astype(np.uint8), "RGBA" if len(top) == 4 else "RGB").convert("RGBA")


def shadowed(canvas, im, x, y, layers=((90, 60, 0.55), (24, 14, 0.35))):
    """Puts a picture down with a soft shadow under it, lit from the top."""
    pad = 260
    a = Image.new("L", (im.width + pad * 2, im.height + pad * 2), 0)
    a.paste(im.getchannel("A"), (pad, pad))
    for blur, drop, opacity in layers:
        s = a.filter(ImageFilter.GaussianBlur(blur)).point(lambda v, o=opacity: int(v * o))
        layer = Image.new("RGBA", s.size, (4, 8, 24, 0))
        layer.putalpha(s)
        canvas.alpha_composite(layer, (int(x) - pad, int(y) - pad + drop))
    canvas.alpha_composite(im, (int(x), int(y)))


def sharp(im, percent=40):
    rgb = im.convert("RGB").filter(ImageFilter.UnsharpMask(radius=1.2, percent=percent, threshold=1))
    rgb.putalpha(im.getchannel("A"))
    return rgb


# ---------- devices ----------

def iphone(screen, sw):
    """An iPhone 16 Pro Max drawn around a screenshot: a thin titanium band, a black border and the screen
    with continuous corners. The screenshot already has the Dynamic Island."""
    sh = round(screen.height * sw / screen.width)
    scr = screen.resize((sw, sh), Image.LANCZOS)
    border = round(sw * 0.034)
    band = max(4, round(sw * 0.0075))
    btn = round(sw * 0.007)
    r_screen = sw * 0.122
    W, H = sw + 2 * border + 2 * btn, sh + 2 * border
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bx0, bx1 = btn, W - btn

    # Buttons first, so the body covers their inner ends.
    d = ImageDraw.Draw(out)
    def button(side, a, b):
        y0, y1 = H * a, H * b
        x0, x1 = (0, btn * 3) if side == "l" else (W - btn * 3, W)
        m = Image.new("L", (W * SS, H * SS), 0)
        ImageDraw.Draw(m).rounded_rectangle([x0 * SS, y0 * SS, x1 * SS, y1 * SS], btn * SS, fill=255)
        out.alpha_composite(fill((W, H), (70, 70, 74, 255), m.resize((W, H), Image.LANCZOS)))
    button("l", 0.175, 0.205)   # action button
    button("l", 0.245, 0.305)   # volume up
    button("l", 0.325, 0.385)   # volume down
    button("r", 0.275, 0.365)   # side button
    button("r", 0.555, 0.615)   # camera control

    body = (bx0, 0, bx1, H)
    r_body = r_screen + border
    titanium = vgradient((W, H), (96, 96, 102, 255), (54, 54, 58, 255))
    titanium.putalpha(shape_mask((W, H), body, r_body))
    out.alpha_composite(titanium)
    inner = (bx0 + band, band, bx1 - band, H - band)
    out.alpha_composite(fill((W, H), (6, 6, 8, 255), shape_mask((W, H), inner, r_body - band)))
    # A hairline of light just inside the band, the way the edge catches the light.
    hl = ImageChops.subtract(shape_mask((W, H), inner, r_body - band),
                             shape_mask((W, H), (inner[0] + 2, inner[1] + 2, inner[2] - 2, inner[3] - 2), r_body - band - 2))
    out.alpha_composite(fill((W, H), (255, 255, 255, 36), hl))
    sx, sy = bx0 + border, border
    smask = shape_mask((sw, sh), (0, 0, sw, sh), r_screen)
    scr.putalpha(smask)
    out.alpha_composite(scr, (sx, sy))
    return out


def ipad(screen, sw):
    """An iPad Pro drawn around a screenshot: a thin, even black border and a fine aluminium edge."""
    sh = round(screen.height * sw / screen.width)
    scr = screen.resize((sw, sh), Image.LANCZOS)
    border = round(sw * 0.026)
    band = max(3, round(sw * 0.004))
    r_screen = sw * 0.024
    W, H = sw + 2 * border, sh + 2 * border
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    r_body = r_screen + border
    alu = vgradient((W, H), (120, 122, 128, 255), (70, 72, 78, 255))
    alu.putalpha(shape_mask((W, H), (0, 0, W, H), r_body))
    out.alpha_composite(alu)
    out.alpha_composite(fill((W, H), (8, 8, 10, 255), shape_mask((W, H), (band, band, W - band, H - band), r_body - band)))
    # Front camera, centred in the top border (landscape camera sits on the long side, but this is portrait).
    cam = round(border * 0.22)
    d = ImageDraw.Draw(out)
    d.ellipse([W / 2 - cam, border / 2 - cam, W / 2 + cam, border / 2 + cam], fill=(28, 30, 38, 255))
    scr.putalpha(shape_mask((sw, sh), (0, 0, sw, sh), r_screen))
    out.alpha_composite(scr, (border, border))
    return out


# ---------- pages ----------

IPHONE = [
    ("Every temperature\nin °F and °C", "Pick which unit is large. The other sits beside it."),
    ("Ten days on one scale", "Every low and high on one bar, in both units"),
    ("Twelve tiles of detail", "Sunrise colour, air quality, cloud, the moon and more"),
    ("All your cities,\nside by side", "Up to 20 places, each on its own sky"),
    ("Widgets for every screen", "Home Screen and Lock Screen, in both units"),
]

IPAD = [
    ("Every temperature in °F and °C", "Pick which unit is large. The other sits beside it."),
    ("Ten days on one scale", "Every low and high on one bar, in both units"),
    ("Twelve tiles of detail", "Sunrise colour, air quality, cloud, the moon and more"),
    ("All your cities, side by side", "Up to 20 places, each on its own sky"),
]

MAC = [
    ("Every temperature in °F and °C", "Press F or C to choose which unit is large"),
    ("Ten days on one scale", "Every low and high on one bar, beside the large widget"),
    ("Twelve tiles of detail", "Visibility, precipitation, cloud at each height, the moon and more"),
    ("Widgets on your desktop", "Small, medium and large. Each can show a city of its own."),
    ("In your menu bar and Dock", "The temperature in both units, always a glance away"),
]


def phone_page(shot, title, sub):
    W, H = 1320, 2868
    c = sky(W, H)
    top = 770
    title_block(c, title, sub, top, size=112, sub_size=50, max_w=W - 180)
    dev = iphone(shot, 1040)
    shadowed(c, dev, (W - dev.width) / 2, top)
    return c


def widgets_page(load, title, sub):
    W, H = 1320, 2868
    c = sky(W, H)
    title_block(c, title, sub, 600, size=112, sub_size=50, max_w=W - 180)
    bottom = 480
    s = 1.4
    def big(name, k=s):
        im = load(name)
        return sharp(im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS))
    large, medium = big("widget-denver-large.png"), big("widget-zurich-medium.png")
    inline = big("widget-denver-lock-inline.png")
    circ, rect, circ2 = big("widget-denver-lock-circular.png"), big("widget-denver-lock-rectangular.png"), big("widget-zurich-lock-circular.png")
    # The rectangular Lock Screen widget is drawn edge to edge; give it the inset it has on a Lock Screen.
    pad = 30
    padded = Image.new("RGBA", (rect.width + pad * 2, rect.height), (0, 0, 0, 0))
    padded.alpha_composite(fill(padded.size, (31, 31, 31, 255),
                                shape_mask(padded.size, (0, 0, padded.width, padded.height), 44, continuous=False)))
    padded.alpha_composite(rect, (pad, 0))
    rect = padded
    gap = 60
    col = large.width
    row_gap = (col - circ.width * 2 - rect.width) / 2
    total = large.height + gap + medium.height + gap + inline.height + 40 + circ.height
    y = bottom + 120
    x = (W - col) / 2
    gap = 70
    shadowed(c, large, x, y, ((60, 40, 0.45), (16, 10, 0.3)))
    y += large.height + gap
    shadowed(c, medium, x, y, ((60, 40, 0.45), (16, 10, 0.3)))
    y += medium.height + gap + 40
    shadowed(c, inline, (W - inline.width) / 2, y, ((30, 16, 0.35),))
    y += inline.height + 54
    rx = x
    for im in (circ, rect, circ2):
        shadowed(c, im, rx, y + (circ.height - im.height) / 2, ((30, 16, 0.35),))
        rx += im.width + row_gap
    return c


def tablet_page(shot, title, sub):
    W, H = 2064, 2752
    c = sky(W, H)
    top = 720
    title_block(c, title, sub, top, size=124, sub_size=56, max_w=W - 300)
    dev = ipad(shot, 1600)
    shadowed(c, dev, (W - dev.width) / 2, top)
    return c


def app_mark(px):
    """The new app mark (the iOS icon, in the toolbar's continuous corners), px across."""
    icon = Image.open(os.path.join(ROOT, "Resources", "iOS", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png"))
    tile = icon.convert("RGBA").resize((px, px), Image.LANCZOS)
    tile.putalpha(shape_mask((px, px), (0, 0, px, px), px * 0.26))
    return tile


def window_chrome(im, mark_at=(20, 46, 35), lights=True):
    """For a 2x snapshot: puts back what the real window has and the snapshot lacks, or shows from before
    the icon change. Puts the current app mark over the snapshot's (mark_at is its x, y and size at 1x;
    20,46,35 in the main window, 16,22,28 in the menu bar panel) and, for the main window, draws the traffic
    lights in the hidden title bar (12 pt, 20 pt apart)."""
    im = im.copy()
    x, y, n = (v * 2 for v in mark_at)
    bg = im.getpixel((8, y + n // 2))
    ImageDraw.Draw(im).rectangle([x - 4, y - 4, x + n + 4, y + n + 4], fill=bg)
    im.alpha_composite(app_mark(n), (x, y))
    if not lights:
        return im
    k = SS
    lights = Image.new("RGBA", (80 * 2 * k, 28 * 2 * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(lights)
    for i, (face, rim) in enumerate((((255, 95, 87), (226, 70, 63)), ((254, 188, 46), (223, 158, 25)),
                                     ((40, 200, 64), (27, 168, 47)))):
        cx, cy, r = (14 + 20 * i) * 2 * k, 14 * 2 * k, 6 * 2 * k
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=rim + (255,))
        r -= k
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=face + (255,))
    im.alpha_composite(lights.resize((160, 56), Image.LANCZOS), (0, 4))
    return im


def mac_pages(load):
    W, H = 2880, 1800

    def page(i):
        c = sky(W, H)
        title, sub = MAC[i]
        bottom = over(c, lambda l: headline(l, title, sub, top=130, size=118, sub_size=52, max_w=W - 400))
        return c, bottom

    def window(im, **chrome):
        return mac.rounded(window_chrome(mac.up(im, 2), **chrome), 24)

    def put(c, im, x, y):
        shadowed(c, im, x, y, ((70, 40, 0.55), (12, 6, 0.4)))

    shots = []
    # 1. Both units: the same city with °F large, then °C large.
    c, top = page(0)
    f = window(mac.no_banner(mac.no_update_dot(load("panel-4-extraLarge-base.png"))).crop((0, 0, 619, 512)))
    cc = window(mac.no_banner(mac.no_update_dot(load("panel-4-extraLarge-celsius.png"))).crop((0, 0, 619, 512)))
    gap = 110
    x = (W - f.width - cc.width - gap) / 2
    y = top + (H - top - f.height) / 2 + 20
    put(c, f, x, y)
    put(c, cc, x + f.width + gap, y)
    shots.append(c)

    # 2. The 10 days, beside the large widget.
    c, top = page(1)
    days = window(mac.no_update_dot(load("panel-4-extraLarge-days.png")).crop((0, 0, 619, 558)))
    widget = load("widget-large.png")
    gap = 130
    x = (W - days.width - widget.width - gap) / 2
    y = top + (H - top - days.height) / 2 + 20
    put(c, days, x, y)
    put(c, widget, x + days.width + gap, y + (days.height - widget.height) / 2)
    shots.append(c)

    # 3. The detail tiles, with the toolbar from the 10-day snapshot (nothing shows through under it there).
    c, top = page(2)
    raw = load("panel-4-extraLarge-tiles.png")
    stitched = Image.new("RGBA", (raw.width, raw.height - 48))
    stitched.paste(mac.no_update_dot(load("panel-4-extraLarge-days.png")).crop((0, 0, raw.width, 86)), (0, 0))
    stitched.paste(raw.crop((0, 134, raw.width, raw.height)), (0, 86))
    tiles = window(stitched)
    room = H - top - 90
    if tiles.height > room:   # keep a margin under the window
        tiles = tiles.crop((0, 0, tiles.width, room))
        tiles = mac.rounded(tiles, 24)
    put(c, tiles, (W - tiles.width) / 2, top + (H - top - tiles.height) / 2 + 10)
    shots.append(c)

    # 4. Widgets as they sit on a desktop (already at 2x).
    c, top = page(3)
    large, zurich = load("widget-large.png"), load("widget-picked-zurich-large.png")
    medium, small, small2 = load("widget-picked-denver-medium.png"), load("widget-small.png"), load("widget-picked-reykjavik-small.png")
    gap = 70
    total = large.width * 3 + gap * 2
    x = (W - total) / 2
    y = top + (H - top - large.height) / 2 + 20
    put(c, large, x, y)
    mx = x + large.width + gap
    put(c, medium, mx, y)
    put(c, small, mx, y + large.height - small.height)
    put(c, small2, mx + medium.width - small2.width, y + large.height - small2.height)
    put(c, zurich, mx + medium.width + gap, y)
    shots.append(c)

    # 5. The menu bar panel and the Dock tile with the live reading.
    c, top = page(4)
    panel = window(load("menu-bar-panel.png").crop((0, 0, 492, 610)), mark_at=(16, 22, 28), lights=False)
    tile = load("dock-tile.png").resize((512, 512), Image.LANCZOS)
    gap = 300
    x = (W - panel.width - gap - tile.width) / 2
    y = top + (H - top - panel.height) / 2 + 20
    put(c, panel, x, y)
    tx, ty = x + panel.width + gap, y + (panel.height - tile.height) / 2 - 20
    put(c, tile, tx, ty)
    ImageDraw.Draw(c).ellipse([tx + 256 - 10, ty + 512 + 40, tx + 256 + 10, ty + 512 + 60], fill=(255, 255, 255, 200))
    shots.append(c)
    return shots


def save(im, name):
    path = os.path.join(OUT, name)
    im.convert("RGB").save(path, optimize=True)
    print(path)


def main():
    phone = loader(sys.argv[1] if len(sys.argv) > 1 else None, "appstore-screenshots")
    desk = loader(sys.argv[2] if len(sys.argv) > 2 else None, "ci-shots")
    only = os.environ.get("ONLY", "iphone,ipad,mac").split(",")
    os.makedirs(OUT, exist_ok=True)
    if "iphone" in only:
        for i, (title, sub) in enumerate(IPHONE[:4], 1):
            save(phone_page(phone(f"iphone-{i}.png"), title, sub), f"iphone-{i}.png")
        save(widgets_page(phone, *IPHONE[4]), "iphone-5.png")
    if "ipad" in only:
        for i, (title, sub) in enumerate(IPAD, 1):
            save(tablet_page(phone(f"ipad-{i}.png"), title, sub), f"ipad-{i}.png")
    if "mac" in only:
        for i, im in enumerate(mac_pages(desk), 1):
            save(im, f"mac-{i}.png")


if __name__ == "__main__":
    main()
