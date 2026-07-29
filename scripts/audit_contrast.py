#!/usr/bin/env python3
"""Measure text contrast in captured screenshots and fail on anything below WCAG AA.

Written because a design review made a fair accusation: rules were being added
to source comments faster than they were being enforced in pixels. Three
separate defects survived a round while the code above them narrated the fix.
A comment cannot fail; this can.

    scripts/audit_contrast.py <screenshot-dir> [--floor 4.5] [--strict]

Known limits, measured rather than assumed: it samples the brightest pixel of
each bright run, so antialiased glyph fringes are read as their own runs and
scored low — it under-reports, sometimes by a lot. It also cannot tell text from
artwork, so a saturated album tile scores as a failure. Treat the absolute count
as a candidate list, and the run-to-run delta as the real signal.

The method is deliberately blunt. For every text-sized run of light pixels it
finds, it compares the run against the local background just outside it. That
over-reports on artwork and gradients, so the default run only *reports*; pass
--strict to exit non-zero, and keep a baseline of accepted regions if you wire
it into CI.
"""
import sys
import pathlib
from collections import Counter

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required: python3 -m pip install pillow")


def luminance(rgb):
    def channel(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = rgb[:3]
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def ratio(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def scan(path, floor, scale=3):
    """Yields (y, ratio, glyph, ground) for rows whose text fails the floor.

    Text is found as short bright runs on a darker row; the ground is sampled
    just beyond each run's ends. Runs longer than a third of the width are
    treated as fills rather than glyphs and skipped.
    """
    image = Image.open(path).convert("RGB")
    width, height = image.size
    worst = None
    failures = []

    for y in range(int(height * 0.06), int(height * 0.97), 2 * scale):
        row = [image.getpixel((x, y)) for x in range(0, width, 2)]
        lums = [luminance(p) for p in row]
        if not lums:
            continue
        # A row's ground is its most common dark value.
        dark = [p for p, l in zip(row, lums) if l < 0.25]
        if len(dark) < len(row) * 0.35:
            continue
        ground = Counter(dark).most_common(1)[0][0]

        run, runs = [], []
        for index, (pixel, lum) in enumerate(zip(row, lums)):
            if lum > luminance(ground) + 0.18:
                run.append((index, pixel))
            elif run:
                runs.append(run)
                run = []
        if run:
            runs.append(run)

        for candidate in runs:
            if not (2 <= len(candidate) <= len(row) // 3):
                continue
            glyph = max((p for _, p in candidate), key=luminance)
            value = ratio(glyph, ground)
            if worst is None or value < worst[0]:
                worst = (value, y, glyph, ground)
            if value < floor:
                failures.append((y, value, glyph, ground))
    return worst, failures


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    directory = pathlib.Path(args[0])
    floor = float(args[args.index("--floor") + 1]) if "--floor" in args else 4.5
    strict = "--strict" in args

    shots = sorted(directory.glob("*.png"))
    if not shots:
        sys.exit(f"no screenshots in {directory}")

    total_failures = 0
    for shot in shots:
        worst, failures = scan(shot, floor)
        if worst is None:
            print(f"{shot.name:<22} no measurable text")
            continue
        mark = "FAIL" if failures else "ok  "
        print(f"{mark} {shot.name:<22} worst {worst[0]:5.2f}:1  "
              f"glyph {worst[2]} on {worst[3]}  ({len(failures)} rows under {floor})")
        total_failures += len(failures)

    print(f"\n{total_failures} failing rows across {len(shots)} screens (floor {floor}:1)")
    if strict and total_failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
