"""Makes the Mac App Store screenshots (appstore/screenshots/mac-1.png and on, 2880x1800) from the Mac
self-test's snapshots on the ci-shots branch: a headline on a soft dark desktop with the real app, widgets
and Dock tile on it.

Usage: python3 scripts/make-mac-screenshots.py [folder of snapshots]
Without a folder, it reads them from origin/ci-shots (run git fetch origin ci-shots first). Needs Pillow.
"""
import io
import math
import os
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

W, H = 2880, 1800
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "appstore", "screenshots")
CREAM = (255, 241, 229)
MUTED = (176, 168, 152)


def font(weight, size):
    """Inter as on the product page, or a plain sans if it isn't installed."""
    names = {"semibold": ["InterDisplay-SemiBold.otf", "Inter-SemiBold.otf", "DejaVuSans-Bold.ttf"],
             "regular": ["Inter-Regular.otf", "DejaVuSans.ttf"]}[weight]
    for folder in ["/usr/share/fonts/opentype/inter", "/usr/share/fonts/truetype/dejavu",
                   "/Library/Fonts", os.path.expanduser("~/Library/Fonts"), "/System/Library/Fonts"]:
        for name in names:
            path = os.path.join(folder, name)
            if os.path.exists(path):
                return ImageFont.truetype(path, size)
    return ImageFont.load_default(size)


def loader(folder):
    def load(name):
        if folder:
            return Image.open(os.path.join(folder, name)).convert("RGBA")
        data = subprocess.run(["git", "-C", ROOT, "show", f"origin/ci-shots:{name}"], check=True, capture_output=True).stdout
        return Image.open(io.BytesIO(data)).convert("RGBA")
    return load


def desktop():
    """The product page's desk: pink light from the top left, orange from the bottom right, on warm dark brown."""
    stops = [(0.0, (0x2B, 0x21, 0x1E)), (0.55, (0x1E, 0x1A, 0x17)), (1.0, (0x24, 0x1B, 0x1F))]
    w, h = W // 8, H // 8
    small = Image.new("RGB", (w, h))
    px = small.load()
    dx, dy = math.sin(math.radians(160)), -math.cos(math.radians(160))   # CSS 160deg points down and a little right
    span = abs(w * dx) + abs(h * dy)
    for y in range(h):
        for x in range(w):
            t = min(1.0, max(0.0, ((x - w / 2) * dx + (y - h / 2) * dy) / span + 0.5))
            (t0, c0), (t1, c1) = next((stops[i], stops[i + 1]) for i in range(len(stops) - 1) if t <= stops[i + 1][0])
            k = (t - t0) / (t1 - t0)
            px[x, y] = tuple(round(c0[j] + (c1[j] - c0[j]) * k) for j in range(3))
    base = small.resize((W, H), Image.BICUBIC)

    def glow(cx, cy, rx, ry, colour, strength):
        g = Image.new("L", (W // 8, H // 8), 0)
        ImageDraw.Draw(g).ellipse([(cx - rx) / 8, (cy - ry) / 8, (cx + rx) / 8, (cy + ry) / 8], fill=int(255 * strength))
        g = g.filter(ImageFilter.GaussianBlur(min(rx, ry) / 8 * 0.6)).resize((W, H), Image.BICUBIC)
        return Image.composite(Image.new("RGB", (W, H), colour), base, g)

    base = glow(W * 0.15, 0, W * 0.75, H * 0.75, (224, 74, 122), 0.17)
    base = glow(W, H, W * 0.6, H * 0.7, (242, 166, 90), 0.14)
    return base.convert("RGBA")


def rounded(im, radius):
    """Rounds the corners of a window snapshot and adds the thin light edge a Mac window has."""
    mask = Image.new("L", (im.width * 4, im.height * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, mask.width - 1, mask.height - 1], radius * 4, fill=255)
    mask = mask.resize(im.size, Image.LANCZOS)
    out = im.copy()
    out.putalpha(ImageChops.multiply(im.getchannel("A"), mask))
    edge = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius, outline=(255, 255, 255, 34), width=2)
    out.alpha_composite(edge)
    return out


def place(canvas, im, x, y, shadow=True):
    """Puts a picture on the desktop with a soft shadow under it, the way macOS draws windows."""
    if shadow:
        pad = 120
        alpha = Image.new("L", (im.width + pad * 2, im.height + pad * 2), 0)
        alpha.paste(im.getchannel("A"), (pad, pad))
        for blur, drop, opacity in ((60, 36, 0.55), (10, 6, 0.35)):
            s = alpha.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * opacity))
            layer = Image.new("RGBA", s.size, (0, 0, 0, 0))
            layer.putalpha(s)
            canvas.alpha_composite(layer, (int(x) - pad, int(y) - pad + drop))
    canvas.alpha_composite(im, (int(x), int(y)))


def up(im, factor):
    """Scales a 1x snapshot up by a whole factor, with a light sharpen so text stays crisp."""
    big = im.resize((im.width * factor, im.height * factor), Image.LANCZOS)
    rgb = big.convert("RGB").filter(ImageFilter.UnsharpMask(radius=1.6, percent=60, threshold=1))
    rgb.putalpha(big.getchannel("A"))
    return rgb


def headline(canvas, title, sub):
    d = ImageDraw.Draw(canvas)
    f1, f2 = font("semibold", 124), font("regular", 56)
    d.text((W / 2, 150), title, font=f1, fill=CREAM, anchor="ma")
    if sub:
        d.text((W / 2, 318), sub, font=f2, fill=MUTED, anchor="ma")


def no_update_dot(panel):
    """Mirrors the left half of the toolbar's More button over its right half, which hides the red
    dot that says an update is waiting (the self-test runs as 0.0.0)."""
    out = panel.copy()
    src, dst = panel.load(), out.load()
    left, right = 559, 598   # the More button's left and right edges in the large panel snapshots
    for y in range(36, 72):
        for x in range((left + right) // 2 + 1, min(right + 6, panel.width - 8)):
            dst[x, y] = src[left + right - x, y]
    return out


def cut_rows(panel, top, bottom):
    """Takes the rows from top to bottom out of a snapshot and closes the gap."""
    out = Image.new("RGBA", (panel.width, panel.height - (bottom - top)))
    out.paste(panel.crop((0, 0, panel.width, top)), (0, 0))
    out.paste(panel.crop((0, bottom, panel.width, panel.height)), (0, top))
    return out


def no_banner(panel):
    """Takes out the 'Two Degrees 2.x is available' banner under the toolbar, keeping the usual gap."""
    return cut_rows(panel, 91, 164)


def main():
    load = loader(sys.argv[1] if len(sys.argv) > 1 else None)
    os.makedirs(OUT, exist_ok=True)
    shots = []
    radius = 24

    # 1. Both units: the same city with °F large, then °C large.
    c = desktop()
    headline(c, "Every temperature in °F and °C.", "Pick which unit is large. The other is always right beside it.")
    f = rounded(up(no_banner(no_update_dot(load("panel-4-extraLarge-base.png"))).crop((0, 0, 619, 512)), 2), radius)
    cc = rounded(up(no_banner(no_update_dot(load("panel-4-extraLarge-celsius.png"))).crop((0, 0, 619, 512)), 2), radius)
    gap = 96
    x = (W - f.width - cc.width - gap) / 2
    y = 470 + (H - 470 - f.height) / 2
    place(c, f, x, y)
    place(c, cc, x + f.width + gap, y)
    shots.append(c)

    # 2. The 10 days, beside the large widget that shows them too.
    c = desktop()
    headline(c, "The 10-day forecast, on one scale.", "Every day's low and high on one bar, so a warm day looks warm.")
    # Cropped under Tuesday, so no row is cut in half.
    days = rounded(up(no_update_dot(load("panel-4-extraLarge-days.png")).crop((0, 0, 619, 558)), 2), radius)
    widget = load("widget-large.png")
    gap = 120
    x = (W - days.width - widget.width - gap) / 2
    y = 440 + (H - 440 - days.height) / 2
    place(c, days, x, y)
    place(c, widget, x + days.width + gap, y + (days.height - widget.height) / 2)
    shots.append(c)

    # 3. The detail tiles. The tiles half scrolled under the toolbar are taken out, and the toolbar comes
    # from the 10-day snapshot, where nothing shows through under it.
    c = desktop()
    headline(c, "Every detail, in both units.", "Visibility, precipitation, cloud at each height, the moon and more.")
    raw = load("panel-4-extraLarge-tiles.png")
    stitched = Image.new("RGBA", (raw.width, raw.height - 48))
    stitched.paste(no_update_dot(load("panel-4-extraLarge-days.png")).crop((0, 0, raw.width, 86)), (0, 0))
    stitched.paste(raw.crop((0, 134, raw.width, raw.height)), (0, 86))
    tiles = rounded(up(stitched, 2), radius)
    place(c, tiles, (W - tiles.width) / 2, 440 + (H - 440 - tiles.height) / 2)
    shots.append(c)

    # 4. Widgets, as they sit on a desktop. They are already at 2x.
    c = desktop()
    headline(c, "Widgets on your desktop.", "Small, medium and large. Each one can show a city of its own.")
    large, zurich = load("widget-large.png"), load("widget-picked-zurich-large.png")
    medium, small, small2 = load("widget-picked-denver-medium.png"), load("widget-small.png"), load("widget-picked-reykjavik-small.png")
    gap = 64
    total = large.width * 3 + gap * 2
    x = (W - total) / 2
    y = 430 + (H - 430 - large.height) / 2
    place(c, large, x, y)
    mx = x + large.width + gap
    place(c, medium, mx, y)
    place(c, small, mx, y + large.height - small.height)
    place(c, small2, mx + medium.width - small2.width, y + large.height - small2.height)
    place(c, zurich, mx + medium.width + gap, y)
    shots.append(c)

    # 5. The menu bar panel and the Dock tile with the live reading.
    c = desktop()
    headline(c, "In your Dock and menu bar.", "The temperature in both units, always a glance away.")
    # Cropped under the next 24 hours, so no card is cut in half.
    panel = rounded(up(load("menu-bar-panel.png").crop((0, 0, 492, 618)), 2), radius)
    tile = load("dock-tile.png").resize((512, 512), Image.LANCZOS)
    gap = 300
    x = (W - panel.width - gap - tile.width) / 2
    y = 430 + (H - 430 - panel.height) / 2
    place(c, panel, x, y)
    # The tile with the dot macOS draws under an open app in the Dock.
    tx, ty = x + panel.width + gap, y + (panel.height - tile.height) / 2 - 20
    place(c, tile, tx, ty)
    ImageDraw.Draw(c).ellipse([tx + 256 - 10, ty + 512 + 40, tx + 256 + 10, ty + 512 + 60], fill=(255, 241, 229, 210))
    shots.append(c)

    for i, im in enumerate(shots, 1):
        path = os.path.join(OUT, f"mac-{i}.png")
        im.convert("RGB").save(path, optimize=True)
        print(path)


if __name__ == "__main__":
    main()
