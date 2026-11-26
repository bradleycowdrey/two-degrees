"""Makes the Mac App Store screenshots (appstore/screenshots/mac-1.png and on, 2880x1800) from the Mac
self-test's snapshots on the ci-shots branch, by running make-store-screenshots.py's Mac set (the Cowdrey One
App Store type standard). The helpers below (rounded, up, no_banner, ...) are also used by that script.

Usage: python3 scripts/make-mac-screenshots.py [folder of snapshots]
Without a folder, it reads them from origin/ci-shots (run git fetch origin ci-shots first). Needs Pillow, numpy
and fontTools.
"""
import os
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

W, H = 2880, 1800
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "appstore", "screenshots")


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


def up(im, factor):
    """Scales a 1x snapshot up by a whole factor, with a light sharpen so text stays crisp."""
    big = im.resize((im.width * factor, im.height * factor), Image.LANCZOS)
    rgb = big.convert("RGB").filter(ImageFilter.UnsharpMask(radius=1.6, percent=60, threshold=1))
    rgb.putalpha(big.getchannel("A"))
    return rgb


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
    """The Mac set now follows the Cowdrey One App Store type standard (Fraunces headline, eyebrow, SF Pro / Inter
    sub, the standard's window), which make-store-screenshots.py draws; this runs its Mac set from the same
    snapshots (a folder, or origin/ci-shots), so there is one Mac layout, not two."""
    folder = sys.argv[1] if len(sys.argv) > 1 else "git:ci-shots"
    script = os.path.join(ROOT, "scripts", "make-store-screenshots.py")
    sys.exit(subprocess.run([sys.executable, script, "--only", "mac", "--mac", folder, "--out", OUT]).returncode)


if __name__ == "__main__":
    main()
