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

    /// A ripped collection: real album titles, one artist each, several tracks
    /// per record — the shape `Album.group` exists to find. Without this the
    /// design-review captures showed "0 files" and an empty record wall, and
    /// every screen about owning music was being judged with nothing owned.
    static var localFiles: [Song] {
        songs(from: [
            ("First Light", "Vaelo", "Nightfold"),
            ("Halcyon Drift", "Vaelo", "Nightfold"),
            ("Undertow", "Vaelo", "Nightfold"),
            ("Roman Candle", "Vaelo", "Nightfold"),
            ("Paper Lanterns", "Sable Youth", "Every Little Ghost"),
            ("Every Little Ghost", "Sable Youth", "Every Little Ghost"),
            ("Cinder", "Sable Youth", "Every Little Ghost"),
            ("Golden Static", "Peral", "Field Recordings"),
            ("Warm Wire", "Peral", "Field Recordings"),
            ("Tape Hiss", "Peral", "Field Recordings"),
            ("Salt Air", "Peral", "Field Recordings"),
            ("Longitude", "Kestrel Bay", "Charts"),
            ("Latitude", "Kestrel Bay", "Charts"),
            ("Meridian Line", "Kestrel Bay", "Charts"),
            ("The Owl Field", "The Owl Field", "The Owl Field"),
            ("Long Way Down", "The Owl Field", "The Owl Field"),
            // A sixth record: the mood shelf shows six sleeves, and a demo
            // library one record short would force a repeat there.
            ("Glass Coast", "Marlowe", "Glass Coast"),
            ("Slow Tide", "Marlowe", "Glass Coast")
        ], source: .local)
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
                gradientHex: Palette.hex(forSeed: album),
                // Deterministic, plausible lengths — a fixture that lacked them
                // would hide the duration column on every review screenshot.
                durationSeconds: Double(172 + (index * 37) % 191),
                trackNumber: index % 4 + 1,
                year: 2019 + index % 7
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
            artworkURL: artwork(seed: title, kind: "podcasts"),
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
    ///
    /// What this replaced was a two-stop diagonal gradient with three random
    /// translucent white circles scattered on it — and the comment above it
    /// claimed they made the result "read as artwork rather than as a gradient
    /// placeholder". They did the opposite. Those bubbles filled every tile of
    /// every screenshot through eight rounds of design review, and the owner
    /// named them before I did: pretentious bubbles. Everything else on the
    /// screen was being judged around fake art that looked machine-made,
    /// because it was.
    ///
    /// Real sleeves are *printed*: flat fields, hard edges, structural
    /// geometry, high contrast. Six archetypes drawn from that tradition, one
    /// picked per seed, so a wall of them varies the way a shelf of records
    /// does instead of looking like one effect applied forty times. No
    /// gradients, no translucency, no soft shapes.
    /// A directory of real cover JPEGs to use instead of anything generated.
    ///
    /// The owner's rule, stated twice and now absolute: no hand-drawn vector
    /// art in a frame, ever — only real assets. Review captures pass
    /// `-demoArtDir <path>` pointing at genuine sleeves on disk (the simulator
    /// can read host paths), so every tile, disc and row carries a real cover
    /// and nothing procedural survives into a screenshot.
    private static var artDir: String? {
        guard let index = CommandLine.arguments.firstIndex(of: "-demoArtDir"),
              index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }

    /// First-come assignment, not a hash: every *distinct* seed takes the
    /// next free file, so sleeves never collide while files last. A hash put
    /// two of five records on the same cover once, and a shelf with a
    /// repeated sleeve reads as a bug regardless of how the songs differ.
    /// Deterministic per launch because the catalogue is built in a fixed
    /// order; cached so a seed keeps its sleeve across rebuilds of the list.
    /// Lock-guarded rather than actor-isolated so the nonisolated builders
    /// (and unit tests) can keep calling synchronously.
    ///
    /// Assignment tables are per *kind* — podcasts draw from a `podcasts/`
    /// subfolder of the art directory when one exists, so fictional shows
    /// stop wearing famous record sleeves that the music shelves are wearing
    /// on the next tab over. A kind falls back to the root pool (real art,
    /// duplication risk) before it falls back to anything generated.
    private static let artLock = NSLock()
    private static nonisolated(unsafe) var artAssignments: [String: [String: Int]] = [:]

    private static func artwork(seed: String, kind: String = "") -> URL? {
        if let dir = artDir {
            let candidates = kind.isEmpty ? [dir] : [dir + "/" + kind, dir]
            for candidate in candidates {
                let files = ((try? FileManager.default.contentsOfDirectory(atPath: candidate)) ?? [])
                    .filter { $0.hasSuffix(".jpg") }.sorted()
                guard !files.isEmpty else { continue }
                artLock.lock()
                var table = artAssignments[candidate] ?? [:]
                let index: Int
                if let assigned = table[seed] {
                    index = assigned
                } else {
                    index = table.count % files.count
                    table[seed] = index
                    artAssignments[candidate] = table
                }
                artLock.unlock()
                return URL(fileURLWithPath: candidate).appendingPathComponent(files[index])
            }
        }
        return generatedArtwork(seed: seed)
    }

    private static func generatedArtwork(seed: String) -> URL? {
        let file = artworkDirectory.appendingPathComponent("\(abs(stableHash(seed))).png")
        if FileManager.default.fileExists(atPath: file.path) { return file }

        let side: CGFloat = 600
        let palette = Palette.hex(forSeed: seed).colors.map { UIColor($0) }
        var rng = SeededGenerator(seed: UInt64(abs(stableHash(seed))))
        let ink = palette.first ?? .black
        let paper = palette.last ?? .white
        let archetype = Int.random(in: 0..<6, using: &rng)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(paper.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: side, height: side))
            cg.setFillColor(ink.cgColor)

            switch archetype {
            case 0:
                // A horizontal band, held off centre. ECM and Blue Note both
                // live here: one field, one edge, nothing else.
                let height = side * CGFloat.random(in: 0.28...0.46, using: &rng)
                let top = side * CGFloat.random(in: 0.12...0.44, using: &rng)
                cg.fill(CGRect(x: 0, y: top, width: side, height: height))

            case 1:
                // Concentric rings — structural, not scattered. A record is a
                // set of circles, so the circles are drawn as one object.
                let centre = CGPoint(x: side * CGFloat.random(in: 0.35...0.65, using: &rng),
                                     y: side * CGFloat.random(in: 0.35...0.65, using: &rng))
                let stroke = side * 0.045
                cg.setStrokeColor(ink.cgColor)
                cg.setLineWidth(stroke)
                for step in 1...5 {
                    let radius = side * 0.09 * CGFloat(step)
                    cg.strokeEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                                width: radius * 2, height: radius * 2))
                }

            case 2:
                // A diagonal, cut edge to edge. Two flat fields meeting on a
                // hard line.
                cg.beginPath()
                cg.move(to: CGPoint(x: 0, y: side * CGFloat.random(in: 0.2...0.6, using: &rng)))
                cg.addLine(to: CGPoint(x: side, y: side * CGFloat.random(in: 0.1...0.5, using: &rng)))
                cg.addLine(to: CGPoint(x: side, y: side))
                cg.addLine(to: CGPoint(x: 0, y: side))
                cg.closePath()
                cg.fillPath()

            case 3:
                // Bars in the app mark's own proportions, at sleeve scale. The
                // cover and the icon share a silhouette.
                let bars: [CGFloat] = [0.34, 0.62, 1.0, 0.70, 0.44]
                let width = side * 0.088
                let gap = side * 0.052
                let total = width * 5 + gap * 4
                var x = (side - total) / 2
                for scale in bars {
                    let height = side * 0.62 * scale
                    cg.fill(CGRect(x: x, y: (side - height) / 2, width: width, height: height))
                    x += width + gap
                }

            case 4:
                // A grid, one cell knocked out. Systematic, with one deliberate
                // fault — which is how a designed grid differs from a rendered
                // one.
                let cells = Int.random(in: 3...5, using: &rng)
                let unit = side / CGFloat(cells)
                let skip = Int.random(in: 0..<(cells * cells), using: &rng)
                for index in 0..<(cells * cells) where index != skip {
                    guard index % 2 == 0 else { continue }
                    let row = CGFloat(index / cells), column = CGFloat(index % cells)
                    cg.fill(CGRect(x: column * unit, y: row * unit, width: unit, height: unit))
                }

            case 5:
                // One disc, cropped by the sleeve's own edge.
                let radius = side * CGFloat.random(in: 0.42...0.62, using: &rng)
                let centre = CGPoint(x: side * CGFloat.random(in: 0.1...0.9, using: &rng),
                                     y: side * CGFloat.random(in: 0.1...0.9, using: &rng))
                cg.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                          width: radius * 2, height: radius * 2))

            default:
                break
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
