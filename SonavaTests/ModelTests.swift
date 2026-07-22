//
//  ModelTests.swift
//  SonavaTests
//
//  Invariants the whole app leans on: how a Song resolves to something
//  playable, how identity works, and that persistence degrades safely.
//

import Testing
import Foundation
import SwiftUI
@testable import Sonava

struct SongTests {

    @Test("A local track resolves to a file in the app's media directory")
    @MainActor
    func localTrackResolvesToMediaDirectory() throws {
        let song = Song(
            id: "local:tune.m4a", title: "Tune", artist: "Someone", album: "Files",
            source: .local, fileName: "tune.m4a", gradientHex: Palette.hex(for: 0)
        )

        let url = try #require(song.url)
        #expect(url.isFileURL)
        #expect(url.deletingLastPathComponent() == LocalFileStore.mediaDirectory)
    }

    @Test("A remote track plays from its stream URL")
    func remoteTrackUsesStreamURL() throws {
        let stream = URL(string: "https://example.com/track.mp3")!
        let song = Song(
            id: "audius:1", title: "T", artist: "A", album: "B",
            source: .audius, streamURL: stream, gradientHex: Palette.hex(for: 1)
        )

        #expect(song.url == stream)
        #expect(song.isRemote)
    }

    @Test("Identity is the id, so the same track from two feeds is one track")
    func identityIsTheID() {
        let base = Song(id: "audius:9", title: "One", artist: "A", album: "B",
                        source: .audius, gradientHex: Palette.hex(for: 2))
        let sameIDDifferentMetadata = Song(id: "audius:9", title: "Renamed", artist: "Z", album: "Y",
                                           source: .audius, gradientHex: Palette.hex(for: 7))

        #expect(base == sameIDDifferentMetadata)
        #expect(Set([base, sameIDDifferentMetadata]).count == 1)
    }

    @Test("A track survives a JSON round trip")
    func songIsCodable() throws {
        let original = Song(
            id: "deezer:5", title: "Preview", artist: "A", album: "B",
            source: .deezer,
            artworkURL: URL(string: "https://example.com/art.jpg"),
            streamURL: URL(string: "https://example.com/p.mp3"),
            gradientHex: [0x112233, 0x445566]
        )

        let decoded = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(original))

        #expect(decoded == original)
        #expect(decoded.gradientHex == original.gradientHex)
        #expect(decoded.source == .deezer)
    }

    @Test("Preview sources are badged so they cannot be mistaken for full tracks")
    func previewSourcesAreBadged() {
        #expect(TrackSource.deezer.badge == "PREVIEW")
        #expect(TrackSource.itunes.badge == "PREVIEW")
        #expect(TrackSource.radio.badge == "LIVE")
        // The user's own files carry no badge — nothing to disclaim.
        #expect(TrackSource.local.badge == nil)
    }
}

struct JSONFileStoreTests {

    @Test("Values survive a write/read round trip")
    func roundTrips() {
        let store = JSONFileStore<[String]>("test-roundtrip.json", default: [])
        store.write(["a", "b"])
        #expect(store.read() == ["a", "b"])
    }

    @Test("A missing file yields the default rather than failing")
    func missingFileYieldsDefault() {
        let store = JSONFileStore<[String]>("test-does-not-exist-\(UUID().uuidString).json", default: ["fallback"])
        #expect(store.read() == ["fallback"])
    }

    @Test("A corrupt file yields the default rather than crashing the app")
    func corruptFileYieldsDefault() throws {
        let store = JSONFileStore<[String]>("test-corrupt.json", default: ["fallback"])
        try Data("this is not json".utf8).write(to: store.url)

        // Losing a cache of user state is bad; refusing to launch is worse.
        #expect(store.read() == ["fallback"])
    }
}

struct PaletteTests {

    @Test("The same seed always produces the same colours")
    func seedIsStable() {
        #expect(Palette.hex(forSeed: "audius:42") == Palette.hex(forSeed: "audius:42"))
    }

    @Test("Indexes wrap instead of trapping")
    func indexWraps() {
        #expect(Palette.hex(for: Palette.gradientsHex.count) == Palette.hex(for: 0))
        #expect(Palette.hex(for: -1).isEmpty == false)
    }
}

struct FilterChipTests {

    @Test("A chip is identified by the value it queries, not its label")
    func identityIsTheQueryValue() {
        let english = FilterChip<String>("Jazz", "jazz")
        let translatedLabel = FilterChip<String>("Джаз", "jazz")

        #expect(english == translatedLabel)
        #expect(Set([english, translatedLabel]).count == 1)
    }

    @Test("The shorthand uses the English term as both label and query")
    func shorthandUsesTermForBoth() {
        #expect(FilterChip("Comedy").value == "Comedy")
    }
}

struct DurationFormattingTests {

    @Test("Durations format as m:ss", arguments: [
        (0.0, "0:00"), (5.0, "0:05"), (65.0, "1:05"), (3599.0, "59:59"),
    ])
    func formatsAsClock(seconds: Double, expected: String) {
        #expect(seconds.asClock == expected)
    }

    @Test("Non-finite and negative durations do not produce nonsense")
    func handlesGarbage() {
        // Live radio reports an indefinite duration; the scrubber must not
        // render "-9223372036854775808:00".
        #expect(Double.infinity.asClock == "0:00")
        #expect(Double.nan.asClock == "0:00")
        #expect((-10.0).asClock == "0:00")
    }
}
