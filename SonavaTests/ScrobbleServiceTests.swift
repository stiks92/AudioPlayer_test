//
//  ScrobbleServiceTests.swift
//  SonavaTests
//
//  ListenBrainz is strict about payload shape, so the pure builder is pinned
//  down: the right listen_type, listened_at present only for real listens, and
//  the eligibility rules that stop radio/previews being scrobbled.
//

import Testing
import Foundation
@testable import Sonava

struct ScrobbleServiceTests {

    private func song(_ source: TrackSource = .audius, artist: String = "Bonobo", title: String = "Kerala") -> Song {
        Song(id: "\(source.rawValue):1", title: title, artist: artist, album: "Migration",
             source: source, streamURL: URL(string: "https://example.com/x"),
             gradientHex: Palette.hex(for: 0))
    }

    @Test("A real listen carries listened_at and the core metadata")
    func listenPayloadShape() throws {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let body = ScrobbleService.payload(listenType: .single, song: song(), listenedAt: when)

        #expect(body["listen_type"] as? String == "single")
        let payload = try #require(body["payload"] as? [[String: Any]])
        let listen = try #require(payload.first)
        #expect(listen["listened_at"] as? Int == 1_700_000_000)

        let meta = try #require(listen["track_metadata"] as? [String: Any])
        #expect(meta["artist_name"] as? String == "Bonobo")
        #expect(meta["track_name"] as? String == "Kerala")
        #expect(meta["release_name"] as? String == "Migration")
    }

    @Test("playing_now must NOT include listened_at (ListenBrainz rejects it otherwise)")
    func nowPlayingOmitsTimestamp() throws {
        let body = ScrobbleService.payload(listenType: .playingNow, song: song(), listenedAt: nil)
        #expect(body["listen_type"] as? String == "playing_now")
        let listen = try #require((body["payload"] as? [[String: Any]])?.first)
        #expect(listen["listened_at"] == nil)
    }

    @Test("The submission is identified as Sonava")
    func identifiesClient() throws {
        let body = ScrobbleService.payload(listenType: .single, song: song(), listenedAt: Date())
        let listen = try #require((body["payload"] as? [[String: Any]])?.first)
        let meta = try #require(listen["track_metadata"] as? [String: Any])
        let info = try #require(meta["additional_info"] as? [String: Any])
        #expect(info["submission_client"] as? String == "Sonava")
        #expect(info["music_service_name"] as? String == "audius")
    }

    @Test("Only full-length music with real metadata is scrobblable", arguments: [
        (TrackSource.audius, "A", "T", true),
        (TrackSource.subsonic, "A", "T", true),
        (TrackSource.local, "A", "T", true),
        (TrackSource.deezer, "A", "T", false),     // 30s preview
        (TrackSource.itunes, "A", "T", false),     // 30s preview
        (TrackSource.radio, "A", "T", false),      // live, no track
        (TrackSource.podcast, "A", "T", false),
        (TrackSource.audius, "", "T", false),      // missing artist
        (TrackSource.audius, "A", "", false),      // missing title
    ])
    func eligibility(source: TrackSource, artist: String, title: String, expected: Bool) {
        let s = Song(id: "x", title: title, artist: artist, album: "Al", source: source,
                     streamURL: URL(string: "https://example.com/x"), gradientHex: Palette.hex(for: 0))
        #expect(ScrobbleService.isScrobblable(s) == expected)
    }

    @Test("An album isn't required — a single with no release still builds")
    func albumOptional() throws {
        let s = Song(id: "x", title: "T", artist: "A", album: "", source: .audius,
                     gradientHex: Palette.hex(for: 0))
        let body = ScrobbleService.payload(listenType: .single, song: s, listenedAt: Date())
        let listen = try #require((body["payload"] as? [[String: Any]])?.first)
        let meta = try #require(listen["track_metadata"] as? [String: Any])
        #expect(meta["release_name"] == nil)
    }
}
