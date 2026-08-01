//
//  ArtworkPalette.swift
//  Sonava
//
//  The sleeve lights the room.
//
//  Until now every track carried a colour pair *seeded from its title hash* —
//  seventeen stock neon gradients, half of them violet, assigned to music that
//  had never seen those colours. The owner's verdict on the result was blunt,
//  and right: the cover is on screen while the light around it belongs to a
//  template. So the colours now come from the only honest source there is —
//  the artwork's own pixels. The seeded pair remains solely as the fallback
//  for the moment before the sleeve has been read, or for tracks that have
//  no art at all.
//
//  The extractor is a pure function over a downsampled bitmap, so it is unit
//  tested with synthetic sleeves: a red cover must glow red, a two-colour
//  cover must yield both, a grey cover must stay grey — a black-and-white
//  sleeve deserves a silver room, not an invented hue.
//

import SwiftUI
import ImageIO

enum ArtworkPalette {

    /// The side of the working bitmap. 32×32 is a thousand samples — plenty
    /// to rank hues, cheap enough to run on every track change.
    private static let side = 32

    // MARK: - Loading

    /// Reads a sleeve from disk or network and extracts its palette.
    ///
    /// `nonisolated` + async on purpose: AudioManager lives on the main actor,
    /// and this hops to a background executor for the decode so a track change
    /// never pays for pixel work on the UI thread.
    static func load(from url: URL) async -> [UInt]? {
        let source: CGImageSource?
        if url.isFileURL {
            source = CGImageSourceCreateWithURL(url as CFURL, nil)
        } else {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            source = CGImageSourceCreateWithData(data as CFData, nil)
        }
        guard let source else { return nil }

        // A thumbnail, not the full decode: a 1400px sleeve is 60× more pixels
        // than the ranking needs.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: side * 2,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return extract(from: thumb)
    }

    // MARK: - Extraction

    /// The two colours that dominate a sleeve, brightest-scoring first,
    /// stored as hex so they slot straight into `Song.gradientHex`'s world.
    static func extract(from image: CGImage) -> [UInt]? {
        guard let pixels = resample(image) else { return nil }

        // Rank chromatic pixels into 30° hue bins, weighted by vibrancy —
        // a saturated mid-tone should outrank acres of murky shadow.
        let bins = 12
        var count = [Int](repeating: 0, count: bins)
        var score = [Double](repeating: 0, count: bins)
        var sums = [(r: Double, g: Double, b: Double)](repeating: (0, 0, 0), count: bins)
        var chromatic = 0

        // The neutral story, gathered in the same pass: the bright and dark
        // halves of the sleeve, kept separately so a grey cover still yields
        // a two-stop ramp with its own cast.
        var bright: (r: Double, g: Double, b: Double, n: Double) = (0, 0, 0, 0)
        var dark: (r: Double, g: Double, b: Double, n: Double) = (0, 0, 0, 0)

        for p in pixels {
            let (h, s, v) = hsv(r: p.r, g: p.g, b: p.b)
            if s >= 0.15 && v >= 0.14 {
                chromatic += 1
                let bin = min(bins - 1, Int(h / 360 * Double(bins)))
                count[bin] += 1
                score[bin] += s * v
                sums[bin].r += p.r; sums[bin].g += p.g; sums[bin].b += p.b
            }
            if v >= 0.5 { bright.r += p.r; bright.g += p.g; bright.b += p.b; bright.n += 1 }
            else { dark.r += p.r; dark.g += p.g; dark.b += p.b; dark.n += 1 }
        }

        // A sleeve that is essentially monochrome gets a monochrome answer.
        guard Double(chromatic) >= Double(pixels.count) * 0.04 else {
            let hi = bright.n > 0 ? (bright.r / bright.n, bright.g / bright.n, bright.b / bright.n)
                                  : (0.72, 0.72, 0.74)
            let lo = dark.n > 0 ? (dark.r / dark.n, dark.g / dark.n, dark.b / dark.n)
                                : (0.16, 0.16, 0.18)
            return [tone(hi.0, hi.1, hi.2), tone(lo.0, lo.1, lo.2)]
        }

        guard let first = score.indices.max(by: { score[$0] < score[$1] }) else { return nil }

        // The second colour must be a genuinely different hue — at least two
        // bins away around the circle — and carry real weight. Otherwise the
        // sleeve is effectively one-coloured, and its own colour deepened
        // makes a truer pair than a hue the ranking barely saw.
        let second = score.indices
            .filter { bin in
                let d = abs(bin - first)
                return min(d, bins - d) >= 2 && score[bin] >= score[first] * 0.18
            }
            .max(by: { score[$0] < score[$1] })

        let primary = mean(sums[first], count[first])
        if let second {
            let secondary = mean(sums[second], count[second])
            return [tone(primary.r, primary.g, primary.b),
                    tone(secondary.r, secondary.g, secondary.b)]
        }
        return [tone(primary.r, primary.g, primary.b),
                tone(primary.r * 0.45, primary.g * 0.45, primary.b * 0.45)]
    }

    // MARK: - Pixels

    private struct Pixel { let r, g, b: Double }

    private static func resample(_ image: CGImage) -> [Pixel]? {
        let w = side, h = side
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let raw = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        var pixels: [Pixel] = []
        pixels.reserveCapacity(w * h)
        for i in 0..<(w * h) {
            let o = i * 4
            pixels.append(Pixel(r: Double(raw[o]) / 255,
                                g: Double(raw[o + 1]) / 255,
                                b: Double(raw[o + 2]) / 255))
        }
        return pixels
    }

    private static func mean(_ sum: (r: Double, g: Double, b: Double), _ n: Int)
        -> (r: Double, g: Double, b: Double) {
        let d = Double(max(1, n))
        return (sum.r / d, sum.g / d, sum.b / d)
    }

    // MARK: - Colour maths

    /// Settles a raw mean into a usable glow stop: brightness is clamped into
    /// a band that reads on a black ground without fogging it (a near-white
    /// sleeve would otherwise bleach the whole screen at 55% opacity), and
    /// saturation is capped short of neon.
    private static func tone(_ r: Double, _ g: Double, _ b: Double) -> UInt {
        var (h, s, v) = hsv(r: r, g: g, b: b)
        v = min(max(v, 0.30), 0.78)
        s = min(s, 0.82)
        let (tr, tg, tb) = rgb(h: h, s: s, v: v)
        return UInt(tr * 255) << 16 | UInt(tg * 255) << 8 | UInt(tb * 255)
    }

    private static func hsv(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let hi = max(r, g, b), lo = min(r, g, b)
        let delta = hi - lo
        var h: Double = 0
        if delta > 0 {
            if hi == r { h = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if hi == g { h = 60 * ((b - r) / delta + 2) }
            else { h = 60 * ((r - g) / delta + 4) }
            if h < 0 { h += 360 }
        }
        return (h, hi == 0 ? 0 : delta / hi, hi)
    }

    private static func rgb(h: Double, s: Double, v: Double) -> (Double, Double, Double) {
        let c = v * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<60: (r, g, b) = (c, x, 0)
        case ..<120: (r, g, b) = (x, c, 0)
        case ..<180: (r, g, b) = (0, c, x)
        case ..<240: (r, g, b) = (0, x, c)
        case ..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }
}
