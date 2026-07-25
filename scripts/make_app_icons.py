#!/usr/bin/env python3
"""Generate Sonava's app icons — the primary one plus a set per theme palette.

The mark is a five-bar waveform: it reads at 40px, it says "music player with a
real equalizer" without a word of copy, and it recolours cleanly, which is what
makes the alternate icons feel like the same app rather than five apps.

Every `.appiconset` in the catalog is generated, so edit this rather than the
PNGs. Needs Pillow.

    python3 scripts/make_app_icons.py Sonava/Resources/Assets.xcassets

Adding a palette means three matching edits, or the picker will offer an icon
iOS cannot apply — `AppIconOptionTests` asserts against the built bundle and
will catch it:

  1. PALETTES below,
  2. `AppIconOption` in Sonava/DesignSystem/AppIconOption.swift,
  3. ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES in the project file.
"""
import json
import math
import os
import shutil
import sys
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024

# Matches Sonava/DesignSystem/ThemePalette.swift — the icon and the in-app
# accent must be the same colour or picking a theme feels broken.
PALETTES = {
    "AppIcon":         ("aurora", 0x4A00E0, 0x7C5CFF, 0xFF6FD8),
    "AppIcon-Sunset":  ("sunset", 0xB4256B, 0xFF7A5A, 0xFFB03A),
    "AppIcon-Ocean":   ("ocean",  0x0E5BE0, 0x2BD3E8, 0x38EF9D),
    "AppIcon-Forest":  ("forest", 0x0E7A55, 0x3DD68C, 0xC6E85A),
    "AppIcon-Rose":    ("rose",   0xB01E5A, 0xFF5C8A, 0xFF8FB4),
    "AppIcon-Mono":    ("mono",   0x2A2A32, 0x6E6E7A, 0xC7C7D2),
}

# Every slot iOS asks for, keyed by the filename the Contents.json points at.
SLOTS = [
    ("Icon-App-20x20@1x.png", 20), ("Icon-App-20x20@2x.png", 40), ("Icon-App-20x20@3x.png", 60),
    ("Icon-App-29x29@1x.png", 29), ("Icon-App-29x29@2x.png", 58), ("Icon-App-29x29@3x.png", 87),
    ("Icon-App-40x40@1x.png", 40), ("Icon-App-40x40@2x.png", 80), ("Icon-App-40x40@3x.png", 120),
    ("Icon-App-60x60@2x.png", 120), ("Icon-App-60x60@3x.png", 180),
    ("Icon-App-76x76@1x.png", 76), ("Icon-App-76x76@2x.png", 152),
    ("Icon-App-83.5x83.5@2x.png", 167),
    ("ItunesArtwork@2x.png", 1024),
]


def rgb(value):
    return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)


def diagonal_gradient(size, deep, mid, bright):
    """Three-stop gradient along the top-left → bottom-right diagonal."""
    image = Image.new("RGB", (size, size))
    pixels = image.load()
    deep, mid, bright = rgb(deep), rgb(mid), rgb(bright)
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            if t < 0.5:
                u = t / 0.5
                a, b = deep, mid
            else:
                u = (t - 0.5) / 0.5
                a, b = mid, bright
            # Smoothstep keeps the two joins from showing as bands.
            u = u * u * (3 - 2 * u)
            pixels[x, y] = tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3))
    return image


def add_glow(image, centre, radius, strength=70):
    """A soft light behind the mark, so the glyph doesn't sit flat on the gradient."""
    glow = Image.new("L", image.size, 0)
    draw = ImageDraw.Draw(glow)
    cx, cy = centre
    draw.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=strength)
    glow = glow.filter(ImageFilter.GaussianBlur(radius * 0.55))
    white = Image.new("RGB", image.size, (255, 255, 255))
    return Image.composite(white, image, glow.point(lambda v: min(255, v)))


def draw_wave(image):
    """Five rounded bars, tallest in the middle — a waveform, and an equalizer."""
    draw = ImageDraw.Draw(image, "RGBA")
    heights = [0.34, 0.62, 1.00, 0.70, 0.44]
    opacities = [200, 230, 255, 235, 210]

    bar_w = SIZE * 0.106
    gap = SIZE * 0.052
    tallest = SIZE * 0.56
    total_w = len(heights) * bar_w + (len(heights) - 1) * gap
    x = (SIZE - total_w) / 2
    cy = SIZE / 2

    for height, alpha in zip(heights, opacities):
        h = tallest * height
        draw.rounded_rectangle(
            [x, cy - h / 2, x + bar_w, cy + h / 2],
            radius=bar_w / 2,
            fill=(255, 255, 255, alpha),
        )
        x += bar_w + gap
    return image


def render(name, deep, mid, bright):
    icon = diagonal_gradient(SIZE, deep, mid, bright)
    # A glow behind the mark was tried and dropped: lightening the middle is
    # exactly where the white bars need contrast most.
    icon = draw_wave(icon)
    return icon


def contents_json(idioms_source):
    with open(idioms_source) as handle:
        return json.load(handle)


def write_set(directory, master, template):
    os.makedirs(directory, exist_ok=True)
    for filename, px in SLOTS:
        master.resize((px, px), Image.LANCZOS).save(os.path.join(directory, filename))
    with open(os.path.join(directory, "Contents.json"), "w") as handle:
        json.dump(template, handle, indent=2)
        handle.write("\n")


def main(assets_dir):
    template = contents_json(os.path.join(assets_dir, "AppIcon.appiconset", "Contents.json"))
    for name, (_slug, deep, mid, bright) in PALETTES.items():
        master = render(name, deep, mid, bright)
        target = os.path.join(assets_dir, f"{name}.appiconset")
        if name != "AppIcon" and os.path.isdir(target):
            shutil.rmtree(target)
        write_set(target, master, template)
        print("wrote", target)


if __name__ == "__main__":
    main(sys.argv[1])
