//
//  DesignTokenLintTests.swift
//  SonavaTests
//
//  The design tokens are only worth having if the app actually uses them.
//  Four independent design reviews found the same thing: a ramp had been
//  written and then bypassed at 170 call sites, so nothing responded to
//  Dynamic Type. Fixing that once is easy; keeping it fixed needs a test,
//  because the next person to add a screen will reach for `size: 15`.
//
//  This reads the source tree rather than the built product, which is what
//  makes it a lint. `#filePath` is baked in at compile time, so it finds the
//  repository without anything being configured.
//

import Testing
import Foundation

struct DesignTokenLintTests {

    /// The `Sonava/` source directory, or nil when the sources aren't beside
    /// the built tests (an archived run, say) — in which case there is nothing
    /// to lint and the test says so rather than failing.
    private static var sourceRoot: URL? {
        let root = URL(fileURLWithPath: #filePath)      // …/SonavaTests/<this file>
            .deletingLastPathComponent()                // …/SonavaTests
            .deletingLastPathComponent()                // repository root
            .appendingPathComponent("Sonava")
        return FileManager.default.fileExists(atPath: root.path) ? root : nil
    }

    private static func swiftFiles(in root: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: root,
                                                          includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// `.system(size: <number>)` with a literal below this is body-ish text
    /// that has to scale. At or above it, it is a display glyph or a card
    /// rendered to a fixed-size image, where a fixed measurement is correct.
    private static let displaySizeFloor = 36

    @Test("No new fixed font sizes below the display floor")
    func fixedFontSizesStayContained() throws {
        let root = try #require(Self.sourceRoot, "sources not present; nothing to lint")

        // Matches a *literal* size only. Sizes derived from geometry —
        // `size: iconSize`, `size: size * 0.4` — are legitimate: a glyph
        // inside a 46pt circle must match the circle, not the reader's text
        // setting.
        let pattern = try NSRegularExpression(pattern: #"\.system\(size:\s*(\d+)"#)
        var offenders: [String] = []

        for file in Self.swiftFiles(in: root) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                guard let sizeRange = Range(match.range(at: 1), in: text),
                      let size = Int(text[sizeRange]), size < Self.displaySizeFloor else { continue }
                let line = text[text.startIndex..<text.index(text.startIndex, offsetBy: match.range.location)]
                    .count(where: { $0 == "\n" }) + 1
                offenders.append("\(file.lastPathComponent):\(line) — size: \(size)")
            }
        }

        #expect(offenders.isEmpty, """
            Fixed font sizes below \(Self.displaySizeFloor)pt do not respond to Dynamic Type. \
            Use a role from the ramp in DesignTokens.swift, or @ScaledMetric for a display size:
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// Keeps the tile vocabulary at two.
    ///
    /// A review counted three artwork sizes on Home — 130, 150 and 160 — with
    /// identical gutters and margins, so the differences read as accidents.
    /// Its verdict on the app as a whole was that the tokens are well-conceived
    /// and then bypassed at the call site, over and over. A rule nobody can
    /// enforce is the thing that lets that happen, so this is the enforcement:
    /// `Tile.feature` and `Tile.standard` exist, and a literal is a failure.
    @Test("Artwork tiles come from the two tokens, not from literals")
    func tileSizesComeFromTokens() throws {
        let root = try #require(Self.sourceRoot, "sources not present; nothing to lint")

        // Deliberately narrow, and narrow on purpose. A first draft matched any
        // `size:`/`width:` in the hundreds and would have failed on six
        // legitimate sites — a podcast's hero cover, an artist portrait, the
        // Shazam rings, a chart height. Lint that fires on correct code is lint
        // that gets switched off, so this matches exactly one call shape.
        //
        // The trade is real: the curated-playlist tile is an `AsyncImage`, not
        // an `ArtworkThumbnail`, so a literal creeping back in there would slip
        // past this. A rule that is always right about less beats one that is
        // sometimes wrong about more.
        let pattern = try NSRegularExpression(pattern: #"ArtworkThumbnail\([^)]*?size:\s*(\d+)"#)
        var offenders: [String] = []

        for file in Self.swiftFiles(in: root) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text),
                      let size = Int(text[range]), size >= 100 else { continue }
                let line = text[text.startIndex..<text.index(text.startIndex, offsetBy: match.range.location)]
                    .count(where: { $0 == "\n" }) + 1
                offenders.append("\(file.lastPathComponent):\(line) — size: \(size)")
            }
        }

        #expect(offenders.isEmpty, """
            Artwork rails must use Tile.feature or Tile.standard from DesignTokens.swift. \
            A third size on one screen reads as a mistake, not a hierarchy:
            \(offenders.joined(separator: "\n"))
            """)
    }

    @Test("The type ramp is actually used")
    func rampIsAdopted() throws {
        let root = try #require(Self.sourceRoot, "sources not present; nothing to lint")

        var rampUses = 0
        for file in Self.swiftFiles(in: root) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            rampUses += text.components(separatedBy: ".sonava").count - 1
            rampUses += text.components(separatedBy: ".system(.").count - 1
        }

        // A floor, not a target: it fails if a refactor quietly rips the ramp
        // out again, which is exactly how the app got into this state before.
        #expect(rampUses > 100, "the type ramp is barely used (\(rampUses) references)")
    }
}
