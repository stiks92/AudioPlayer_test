//
//  ArtworkPaletteTests.swift
//  SonavaTests
//
//  The sleeve-colour extractor is the honesty mechanism for the whole colour
//  story — the app's light must be the record's, so the function that reads
//  the record has to be right. Synthetic sleeves make the contract exact:
//  a red cover glows red, a two-colour cover yields both, a grey cover stays
//  grey rather than being assigned an invented hue, and a white cover is
//  clamped so it cannot bleach a black screen.
//

import Testing
import UIKit
@testable import Sonava

struct ArtworkPaletteTests {

    // MARK: - Helpers

    private func sleeve(_ draw: (CGContext, CGRect) -> Void) -> CGImage {
        let size = CGSize(width: 64, height: 64)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            draw(ctx.cgContext, CGRect(origin: .zero, size: size))
        }
        return image.cgImage!
    }

    private func fill(_ ctx: CGContext, _ rect: CGRect, r: CGFloat, g: CGFloat, b: CGFloat) {
        ctx.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
        ctx.fill(rect)
    }

    private func channels(_ hex: UInt) -> (r: Int, g: Int, b: Int) {
        (Int((hex >> 16) & 0xFF), Int((hex >> 8) & 0xFF), Int(hex & 0xFF))
    }

    // MARK: - Contracts

    @Test("A red sleeve glows red — both stops")
    func solidRed() throws {
        let image = sleeve { ctx, rect in fill(ctx, rect, r: 0.85, g: 0.10, b: 0.10) }
        let palette = try #require(ArtworkPalette.extract(from: image))
        #expect(palette.count == 2)
        for stop in palette {
            let c = channels(stop)
            #expect(c.r > c.g * 2 && c.r > c.b * 2, "stop \(String(stop, radix: 16)) is not red")
        }
    }

    @Test("A two-colour sleeve yields both hues, dominant first")
    func twoTone() throws {
        let image = sleeve { ctx, rect in
            fill(ctx, rect, r: 0.10, g: 0.55, b: 0.55)                      // teal, three quarters
            fill(ctx, CGRect(x: 0, y: 0, width: rect.width, height: rect.height / 4),
                 r: 0.90, g: 0.50, b: 0.10)                                 // orange band
        }
        let palette = try #require(ArtworkPalette.extract(from: image))
        let first = channels(palette[0]), second = channels(palette[1])
        #expect(first.g > first.r && first.b > first.r, "dominant stop should be teal")
        #expect(second.r > second.b, "secondary stop should be the orange band")
    }

    @Test("A grey sleeve stays grey — no invented hue")
    func monochrome() throws {
        let image = sleeve { ctx, rect in
            fill(ctx, rect, r: 0.80, g: 0.80, b: 0.80)
            fill(ctx, CGRect(x: 0, y: rect.height / 2, width: rect.width, height: rect.height / 2),
                 r: 0.25, g: 0.25, b: 0.25)
        }
        let palette = try #require(ArtworkPalette.extract(from: image))
        for stop in palette {
            let c = channels(stop)
            let spread = max(c.r, c.g, c.b) - min(c.r, c.g, c.b)
            #expect(spread <= 30, "stop \(String(stop, radix: 16)) drifted from neutral")
        }
        let first = channels(palette[0]), second = channels(palette[1])
        #expect(first.r > second.r, "bright half leads, dark half follows")
    }

    @Test("A near-white sleeve is clamped so it cannot bleach the screen")
    func clampedBrightness() throws {
        let image = sleeve { ctx, rect in fill(ctx, rect, r: 0.97, g: 0.96, b: 0.95) }
        let palette = try #require(ArtworkPalette.extract(from: image))
        let c = channels(palette[0])
        #expect(max(c.r, c.g, c.b) <= 205, "brightness clamp did not hold")
    }

    @Test("Loading from a file URL round-trips through the real decoder")
    func loadFromDisk() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
            fill(ctx.cgContext, CGRect(x: 0, y: 0, width: 64, height: 64), r: 0.10, g: 0.30, b: 0.75)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sleeve-\(UUID().uuidString).png")
        try image.pngData()!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let palette = try #require(await ArtworkPalette.load(from: url))
        let c = channels(palette[0])
        #expect(c.b > c.r, "a blue sleeve should come back blue")
    }
}
