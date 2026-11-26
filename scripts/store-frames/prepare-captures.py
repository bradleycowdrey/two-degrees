"""Gathers Two Degrees' raw App Store captures into one folder, under the names apps/two-degrees.json uses, for the
family compositor (store-frames.js). Nothing on a screen is edited: the app's own pixels are copied as they are.

  python3 scripts/store-frames/prepare-captures.py --ios DIR [--mac DIR] --out DIR

--ios DIR: what .github/workflows/appstore-screenshots.yml photographs in the Simulator: iphone-1..4.png
  (1320 x 2868), ipad-1..4.png (2064 x 2752) and the widget renders widget-<n><city>-<kind>.png. The main city's
  (n = 0) become widget-<kind>.png (small, medium, large, lock-circular, lock-rectangular, lock-inline).
--mac DIR: the Mac self-test's App Store pass (TwoDegrees --selftest DIR --store): the window at 2x
  (store-1-top.png, store-2-days.png, store-3-tiles.png, store-5-panel.png; 492 x 620 pt) and the widgets
  (store-widget-*.png). The Mac standard is a 2880 x 1800 screen (16:10, a 1440 x 900 pt display at 2x), and the
  app's window is a fixed 492 pt wide, so each Mac capture is two of the app's real windows side by side on the
  app's own sky (the colours of the window's own top and bottom edge), as on a Mac desktop:
    mac-1.png: the city page (store-1-top) and a second city (store-5-panel)
    mac-2.png: the 10-day forecast (store-2-days) and the detail tiles (store-3-tiles)
  The windows are shown at 1.4x their 2x pixels; the compositor then draws the 2880-wide screen 1840 wide, so each
  window ends up at 0.89x its captured pixels: smaller than captured, never enlarged. Widgets: mac-widget-<kind>.png.
Needs Pillow.
"""
import argparse
import glob
import os
import re
import shutil
import sys

from PIL import Image, ImageDraw, ImageFilter

SIZES = {"iphone": (1320, 2868), "ipad": (2064, 2752)}
MAC = (2880, 1800)
WIN_K = 1.4          # the windows' scale on the 2880 x 1800 screen
WIN_RADIUS = 10      # macOS window corners, in points
GAP = 64             # between the two windows, in screen pixels


def fail(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def ios(src, out):
    for kind, size in SIZES.items():
        for n in range(1, 5):
            f = os.path.join(src, f"{kind}-{n}.png")
            if not os.path.isfile(f):
                if kind == "ipad":
                    print(f"warning: no {kind}-{n}.png; the iPad set needs it", file=sys.stderr)
                    continue
                fail(f"no {f}")
            with Image.open(f) as im:
                if im.size != size:
                    fail(f"{f} is {im.size[0]} x {im.size[1]}, not {size[0]} x {size[1]}")
            shutil.copyfile(f, os.path.join(out, f"{kind}-{n}.png"))
    found = 0
    for f in sorted(glob.glob(os.path.join(src, "widget-0*.png"))):
        m = re.match(r"widget-0[^-]*-(small|medium|large|lock-circular|lock-rectangular|lock-inline)\.png$", os.path.basename(f))
        if m:
            shutil.copyfile(f, os.path.join(out, f"widget-{m.group(1)}.png"))
            found += 1
    if found < 6:
        fail(f"found {found} of the main city's 6 widget renders (widget-0<city>-<kind>.png) in {src}")


def sky_of(win):
    """The window's own sky: its colour at the top edge and at the bottom edge."""
    rgb = win.convert("RGB")
    return rgb.getpixel((6, 4)), rgb.getpixel((6, rgb.height - 5))


def mac_screen(files, out_file):
    wins = [Image.open(f).convert("RGBA") for f in files]
    top, bottom = sky_of(wins[0])
    screen = Image.new("RGB", MAC, top)
    px = ImageDraw.Draw(screen)
    for y in range(MAC[1]):   # the window's own sky, top to bottom, behind the windows
        t = y / (MAC[1] - 1)
        px.line([(0, y), (MAC[0], y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    scaled = [w.resize((round(w.width * WIN_K), round(w.height * WIN_K)), Image.LANCZOS) for w in wins]
    total = sum(w.width for w in scaled) + GAP * (len(scaled) - 1)
    if total > MAC[0] or max(w.height for w in scaled) > MAC[1]:
        fail(f"the windows ({total} wide) don't fit a {MAC[0]} x {MAC[1]} screen")
    x = (MAC[0] - total) // 2
    r = round(WIN_RADIUS * 2 * WIN_K)
    for w in scaled:
        y = (MAC[1] - w.height) // 2
        mask = Image.new("L", w.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, w.width - 1, w.height - 1], radius=r, fill=255)
        shadow = Image.new("L", MAC, 0)
        shadow.paste(mask, (x, y + 24))
        shadow = shadow.filter(ImageFilter.GaussianBlur(40)).point(lambda v: v * 0.45)
        screen.paste((3, 9, 22), (0, 0), shadow)
        screen.paste(w.convert("RGB"), (x, y), Image.composite(w.getchannel("A"), Image.new("L", w.size, 0), mask))
        x += w.width + GAP
    screen.save(out_file)


def mac(src, out):
    need = ["store-1-top.png", "store-5-panel.png", "store-2-days.png", "store-3-tiles.png"]
    missing = [n for n in need if not os.path.isfile(os.path.join(src, n))]
    if missing:
        fail(f"the Mac self-test's App Store pass is missing {', '.join(missing)} in {src}")
    mac_screen([os.path.join(src, n) for n in need[:2]], os.path.join(out, "mac-1.png"))
    mac_screen([os.path.join(src, n) for n in need[2:]], os.path.join(out, "mac-2.png"))
    for kind in ("small", "medium", "large"):
        f = os.path.join(src, f"store-widget-{kind}.png")
        if not os.path.isfile(f):
            fail(f"no {f}")
        shutil.copyfile(f, os.path.join(out, f"mac-widget-{kind}.png"))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ios", required=True)
    ap.add_argument("--mac")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    ios(a.ios, a.out)
    if a.mac:
        mac(a.mac, a.out)
    print("captures ready in", a.out)


if __name__ == "__main__":
    main()
