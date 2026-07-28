//
//  DemoCatalog.swift
//  Sonava
//
//  A canned catalogue for DEBUG builds, enabled by the `-seedDemoContent`
//  launch argument.
//
//  Design review is worthless against empty shelves: without this, every
//  screenshot of Home, Search, Radio or Podcasts shows section headers with
//  nothing underneath, and the critique is about missing data instead of about
//  the design. It also makes App Store screenshots reproducible — the same
//  tracks, in the same order, every time.
//
//  Artwork is drawn procedurally into the app's container rather than bundled,
//  so nothing here reaches a Release build. Names are invented: a debug fixture
//  should never imply a catalogue licence the app doesn't have.
//

#if DEBUG
import SwiftUI
import UIKit

enum DemoCatalog {

    /// Only ever on when the launch argument says so.
    static var isActive: Bool { CommandLine.arguments.contains("-seedDemoContent") }

    // MARK: - Shelves

    static var trending: [Song] {
        songs(from: [
            ("Halcyon Drift", "Vaelo", "Nightfold"),
            ("Paper Lanterns", "Mira Sund", "Slow Country"),
            ("Cassette Sun", "The Owl Field", "Cassette Sun"),
            ("Low Tide", "Kestrel Bay", "Saltwater"),
            ("Neon Orchard", "Tomas Hale", "Neon Orchard"),
            ("Blue Hour", "Ansel Ro", "Blue Hour"),
            ("Static Bloom", "Iri", "Fieldwork"),
            ("Winter Ferry", "Nord Atlas", "Crossings")
        ], source: .audius)
    }

    static var charts: [Song] {
        songs(from: [
            ("Golden Static", "Peral", "Golden Static"),
            ("Every Little Ghost", "Sable Youth", "Hollow Season"),
            ("Undertow", "Kestrel Bay", "Saltwater"),
            ("Roman Candle", "Vaelo", "Nightfold"),
            ("Long Way Down", "The Owl Field", "Cassette Sun"),
            ("Marble Sky", "Mira Sund", "Slow Country")
        ], source: .deezer)
    }

    static var madeForYou: [Song] {
        songs(from: [
            ("Second Light", "Ansel Ro", "Blue Hour"),
            ("Glasshouse", "Iri", "Fieldwork"),
            ("Northbound", "Nord Atlas", "Crossings"),
            ("Tidewater", "Kestrel Bay", "Saltwater"),
            ("Slow Signal", "Peral", "Golden Static"),
            ("Evening Class", "Tomas Hale", "Neon Orchard")
        ], source: .audius)
    }

    static var searchResults: [Song] {
        songs(from: [
            ("Halcyon Drift", "Vaelo", "Nightfold"),
            ("Halcyon Drift (Live)", "Vaelo", "Nightfold Sessions"),
            ("Halcyon", "Sable Youth", "Hollow Season"),
            ("Drift", "Iri", "Fieldwork"),
            ("Drift Season", "Nord Atlas", "Crossings")
        ], source: .audius)
    }

    static var stations: [Song] {
        [
            station("Nocturne FM", "Ambient · Berlin"),
            station("Harbour Radio", "Jazz · Lisbon"),
            station("Signal 88", "Electronic · Tokyo"),
            station("The Long Room", "Classical · Dublin"),
            station("Coast Line", "Indie · Vancouver"),
            station("Meridian", "Downtempo · Reykjavík")
        ]
    }

    static var playlists: [RemotePlaylist] {
        [
            playlist("Late Night Drive", "38 tracks · 2h 14m"),
            playlist("Deep Focus", "52 tracks · 3h 06m"),
            playlist("Sunday Morning", "24 tracks · 1h 31m"),
            playlist("Rain on Glass", "41 tracks · 2h 28m")
        ]
    }

    static var podcasts: [Podcast] {
        [
            show("The Quiet Part", "Field Notes Media"),
            show("Signal & Noise", "Halcyon Studios"),
            show("Long Player", "Nord Atlas Media"),
            show("Room Tone", "Peral Audio"),
            show("Third Coast", "Kestrel Bay Radio"),
            show("Nightshift", "Owl Field Productions")
        ]
    }

    // MARK: - Builders

    private static func songs(from rows: [(String, String, String)], source: TrackSource) -> [Song] {
        rows.enumerated().map { index, row in
            let (title, artist, album) = row
            let id = "demo:\(source.rawValue):\(index)-\(title)"
            return Song(
                id: id,
                title: title,
                artist: artist,
                album: album,
                source: source,
                artworkURL: artwork(seed: album),
                streamURL: URL(string: "https://demo.invalid/\(index).mp3"),
                gradientHex: Palette.hex(forSeed: album)
            )
        }
    }

    private static func station(_ name: String, _ detail: String) -> Song {
        Song(
            id: "demo:radio:\(name)",
            title: name,
            artist: detail,
            album: "Live",
            source: .radio,
            artworkURL: artwork(seed: name),
            streamURL: URL(string: "https://demo.invalid/stream"),
            isLive: true,
            gradientHex: Palette.hex(forSeed: name)
        )
    }

    private static func playlist(_ title: String, _ subtitle: String) -> RemotePlaylist {
        RemotePlaylist(
            id: "demo:playlist:\(title)",
            title: title,
            subtitle: subtitle,
            artworkURL: artwork(seed: title),
            gradientHex: Palette.hex(forSeed: title),
            fetchID: title
        )
    }

    private static func show(_ title: String, _ author: String) -> Podcast {
        Podcast(
            title: title,
            author: author,
            artworkURL: artwork(seed: title),
            feedURL: URL(string: "https://demo.invalid/\(title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "feed").xml")!
        )
    }

    // MARK: - Procedural artwork

    private static let artworkDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DemoArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    /// A deterministic cover for a seed string: the same album always gets the
    /// same art, so two capture runs are comparable.
    private static func artwork(seed: String) -> URL? {
        let file = artworkDirectory.appendingPathComponent("\(abs(stableHash(seed))).png")
        if FileManager.default.fileExists(atPath: file.path) { return file }

        let side: CGFloat = 600
        let colors = Palette.hex(forSeed: seed).colors.map { UIColor($0) }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { context in
            let cg = context.cgContext
            // Diagonal two-stop gradient, matching the app's own palette.
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors.map(\.cgColor) as CFArray,
                locations: [0, 1]
            ) {
                cg.drawLinearGradient(gradient, start: .zero,
                                      end: CGPoint(x: side, y: side), options: [])
            }
            // A few soft shapes so covers read as artwork rather than as a
            // gradient placeholder — deterministic, seeded by the title.
            var rng = SeededGenerator(seed: UInt64(abs(stableHash(seed))))
            for _ in 0..<3 {
                let radius = CGFloat.random(in: side * 0.18...side * 0.42, using: &rng)
                let x = CGFloat.random(in: 0...side, using: &rng)
                let y = CGFloat.random(in: 0...side, using: &rng)
                cg.setFillColor(UIColor.white.withAlphaComponent(
                    CGFloat.random(in: 0.05...0.16, using: &rng)).cgColor)
                cg.fillEllipse(in: CGRect(x: x - radius, y: y - radius,
                                          width: radius * 2, height: radius * 2))
            }
        }
        guard let data = image.pngData() else { return nil }
        try? data.write(to: file)
        return file
    }

    /// `String.hashValue` is salted per launch, which would reshuffle every
    /// cover on every run — the opposite of what a fixture needs.
    private static func stableHash(_ string: String) -> Int {
        var hash = 5381
        for byte in string.utf8 { hash = (hash &* 33) &+ Int(byte) }
        return hash
    }
}

/// Deterministic RNG so the generated covers never change between runs.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
#endif
