//
//  PlaylistSharingTests.swift
//  SonavaTests
//
//  The share link is the viral loop, so the codec has to round-trip exactly
//  and reject anything that isn't ours — a malformed link must never crash the
//  app on open.
//

import Testing
import Foundation
@testable import Sonava

struct PlaylistSharingTests {

    private func song(_ id: String) -> Song {
        Song(id: id, title: "Track \(id)", artist: "Artist", album: "Album",
             source: .audius, streamURL: URL(string: "https://example.com/\(id)"),
             gradientHex: Palette.hex(forSeed: id))
    }

    private func playlist(_ name: String, _ ids: [String]) -> UserPlaylist {
        UserPlaylist(name: name, tracks: ids.map(song))
    }

    @Test("A playlist round-trips through a link unchanged")
    func roundTrips() throws {
        let original = playlist("Road Trip", ["a", "b", "c"])
        let link = try #require(PlaylistSharing.link(for: original))
        let decoded = try #require(PlaylistSharing.playlist(from: link))

        #expect(decoded.name == original.name)
        #expect(decoded.tracks == original.tracks)
    }

    @Test("The link uses the sonava:// scheme so iOS routes it to the app")
    func linkSchemeIsCorrect() throws {
        let link = try #require(PlaylistSharing.link(for: playlist("Mix", ["x"])))
        #expect(link.scheme == "sonava")
        #expect(link.host == "playlist")
    }

    @Test("Decoding assigns a fresh id so an import can't collide with the sender")
    func importGetsFreshID() throws {
        let original = playlist("Focus", ["a"])
        let link = try #require(PlaylistSharing.link(for: original))
        let decoded = try #require(PlaylistSharing.playlist(from: link))
        #expect(decoded.id != original.id)
    }

    @Test("An empty playlist still round-trips")
    func emptyRoundTrips() throws {
        let link = try #require(PlaylistSharing.link(for: playlist("Empty", [])))
        let decoded = try #require(PlaylistSharing.playlist(from: link))
        #expect(decoded.tracks.isEmpty)
        #expect(decoded.name == "Empty")
    }

    @Test("Foreign or malformed links are rejected, not force-imported", arguments: [
        "https://example.com/playlist?d=abc",   // wrong scheme
        "sonava://other?d=abc",                 // wrong host
        "sonava://playlist",                    // no payload
        "sonava://playlist?d=!!!notbase64!!!",  // garbage payload
        "sonava://playlist?d=" ,                // empty payload
    ])
    func rejectsBadLinks(raw: String) {
        let url = URL(string: raw)
        #expect(url == nil || PlaylistSharing.playlist(from: url!) == nil)
    }

    @Test("Emoji and unicode names survive the base64url trip")
    func unicodeNames() throws {
        let original = playlist("Ночная поездка 🌙", ["a", "b"])
        let link = try #require(PlaylistSharing.link(for: original))
        let decoded = try #require(PlaylistSharing.playlist(from: link))
        #expect(decoded.name == "Ночная поездка 🌙")
    }

    // MARK: - Credentials never travel

    /// A Subsonic track exactly as `SubsonicService.map` builds one: the
    /// stream and cover URLs carry `u` (username), `t` (salted MD5 of the
    /// password) and `s` (salt), and that token replays forever.
    private func serverSong() -> Song {
        let auth = "u=alice&t=6f1ed002ab5595859014ebf0951522d9&s=abc123&v=1.16.1&c=Sonava&f=json"
        return Song(
            id: "subsonic:F1E2-LOCAL-UUID:842",
            title: "Rumours", artist: "Fleetwood Mac", album: "Rumours",
            source: .subsonic,
            artworkURL: URL(string: "https://music.home.arpa/rest/getCoverArt?id=842&\(auth)"),
            streamURL: URL(string: "https://music.home.arpa/rest/stream?id=842&\(auth)"),
            gradientHex: Palette.hex(for: 0),
            durationSeconds: 257)
    }

    @Test("A share link never carries server credentials")
    func linkCarriesNoCredentials() throws {
        let link = try #require(PlaylistSharing.link(for:
            UserPlaylist(name: "Home server", tracks: [serverSong()])))
        // The whole link, decoded — the payload is base64url, so a substring
        // check on the URL alone would miss the leak it is meant to catch.
        let raw = link.absoluteString
        let encoded = try #require(URLComponents(url: link, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "d" })?.value)
        var padded = encoded.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded.append("=") }
        let payload = String(data: try #require(Data(base64Encoded: padded)), encoding: .utf8) ?? ""

        for secret in ["6f1ed002ab5595859014ebf0951522d9", "abc123", "u=alice", "/rest/stream"] {
            #expect(!payload.contains(secret), "the payload leaks \(secret)")
            #expect(!raw.contains(secret), "the link leaks \(secret)")
        }
        // Identity still travels, or the link would be pointless.
        #expect(payload.contains("Fleetwood Mac"))
        #expect(payload.contains("music.home.arpa"))   // host only, no auth
    }

    /// A Jellyfin track exactly as `JellyfinService.map` builds one: the same
    /// `.subsonic` source (their own server), a `jellyfin:` id prefix, and a
    /// stream URL that carries the session token in `api_key`.
    private func jellyfinSong() -> Song {
        Song(
            id: "jellyfin:F1E2-LOCAL-UUID:842",
            title: "Dreams", artist: "Fleetwood Mac", album: "Rumours",
            source: .subsonic,
            artworkURL: URL(string: "https://jf.home.arpa/Items/842/Images/Primary?fillWidth=512&api_key=tok-SECRET"),
            streamURL: URL(string: "https://jf.home.arpa/Audio/842/universal?UserId=user-1&api_key=tok-SECRET"),
            gradientHex: Palette.hex(for: 0),
            durationSeconds: 257)
    }

    @Test("A Jellyfin track travels as identity only — the session token never leaves")
    func jellyfinLinkCarriesNoToken() throws {
        let link = try #require(PlaylistSharing.link(for:
            UserPlaylist(name: "Media box", tracks: [jellyfinSong()])))
        let encoded = try #require(URLComponents(url: link, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "d" })?.value)
        var padded = encoded.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded.append("=") }
        let payload = String(data: try #require(Data(base64Encoded: padded)), encoding: .utf8) ?? ""

        for secret in ["tok-SECRET", "api_key", "user-1", "/Audio/"] {
            #expect(!payload.contains(secret), "the payload leaks \(secret)")
        }
        // Identity still travels: host + the server's own track id, so the
        // recipient's own connection to that box can rebuild it.
        #expect(payload.contains("jf.home.arpa"))
        #expect(payload.contains("842"))
        #expect(payload.contains("Fleetwood Mac"))
    }

    @Test("A Jellyfin track re-resolves through the recipient's own connection")
    func jellyfinTrackWithResolver() throws {
        let link = try #require(PlaylistSharing.link(for:
            UserPlaylist(name: "Media box", tracks: [jellyfinSong()])))
        var seenHost: String?
        var seenID: String?
        let decoded = try #require(PlaylistSharing.playlist(from: link, resolver: {
            host, trackID, title, artist, album, duration in
            seenHost = host; seenID = trackID
            // What `ServerStore.resolveSharedTrack` mints for a Jellyfin
            // connection to that host.
            return Song(id: "jellyfin:MY-UUID:\(trackID)", title: title, artist: artist,
                        album: album, source: .subsonic,
                        streamURL: URL(string: "https://jf.home.arpa/Audio/\(trackID)/universal?api_key=my-own"),
                        gradientHex: Palette.hex(for: 1), durationSeconds: duration)
        }))

        #expect(seenHost == "jf.home.arpa")
        #expect(seenID == "842")
        let track = try #require(decoded.tracks.first)
        #expect(track.id == "jellyfin:MY-UUID:842")
        #expect(track.streamURL?.absoluteString.contains("my-own") == true)
    }

    @Test("A server track imports unplayable when the recipient has no such server")
    func serverTrackWithoutResolver() throws {
        let link = try #require(PlaylistSharing.link(for:
            UserPlaylist(name: "Home server", tracks: [serverSong()])))
        let decoded = try #require(PlaylistSharing.playlist(from: link))
        let track = try #require(decoded.tracks.first)

        #expect(track.streamURL == nil, "a stranger's server track must not resolve")
        #expect(track.artworkURL == nil)
        #expect(track.title == "Rumours")       // still shows in the list
        #expect(track.durationSeconds == 257)
    }

    @Test("A server track is rebuilt with the recipient's own credentials")
    func serverTrackWithResolver() throws {
        let link = try #require(PlaylistSharing.link(for:
            UserPlaylist(name: "Home server", tracks: [serverSong()])))
        var seenHost: String?
        var seenID: String?
        let decoded = try #require(PlaylistSharing.playlist(from: link, resolver: {
            host, trackID, title, artist, album, duration in
            seenHost = host; seenID = trackID
            return Song(id: "subsonic:MY-UUID:\(trackID)", title: title, artist: artist,
                        album: album, source: .subsonic,
                        streamURL: URL(string: "https://music.home.arpa/rest/stream?id=\(trackID)&u=bob"),
                        gradientHex: Palette.hex(for: 1), durationSeconds: duration)
        }))

        #expect(seenHost == "music.home.arpa")
        #expect(seenID == "842")
        let track = try #require(decoded.tracks.first)
        #expect(track.streamURL?.absoluteString.contains("u=bob") == true)
        #expect(track.id == "subsonic:MY-UUID:842")
    }

    @Test("A legacy link's embedded credentials are stripped on the way in")
    func legacyLinkIsRedacted() throws {
        // The v1 wire format: the whole `Song`, auth token and all.
        struct LegacyPayload: Codable { let name: String; let tracks: [Song] }
        let data = try JSONEncoder().encode(
            LegacyPayload(name: "Old link", tracks: [serverSong(), song("a")]))
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let url = try #require(URL(string: "sonava://playlist?d=\(encoded)"))

        let decoded = try #require(PlaylistSharing.playlist(from: url))
        #expect(decoded.name == "Old link")
        #expect(decoded.tracks.count == 2)
        let server = try #require(decoded.tracks.first)
        #expect(server.streamURL == nil, "a legacy link must not inject a borrowed session")
        // The public track in the same playlist keeps working.
        #expect(decoded.tracks[1].streamURL?.absoluteString == "https://example.com/a")
    }
}

@MainActor
struct PlaylistImportTests {

    private func store() -> PlaylistStore {
        // Isolate on-disk state by clearing the shared file first.
        JSONFileStore<[UserPlaylist]>("user_playlists.json", default: []).write([])
        return PlaylistStore()
    }

    private func shared(_ name: String) -> UserPlaylist {
        UserPlaylist(name: name, tracks: [
            Song(id: "audius:1", title: "T", artist: "A", album: "B",
                 source: .audius, gradientHex: Palette.hex(for: 0))
        ])
    }

    @Test("Importing a shared playlist adds it to the top")
    func importAdds() {
        let store = store()
        let before = store.playlists.count
        store.importShared(shared("From a friend"))
        #expect(store.playlists.count == before + 1)
        #expect(store.playlists.first?.name == "From a friend")
    }

    @Test("Importing the same playlist twice is idempotent")
    func importIsIdempotent() {
        let store = store()
        let playlist = shared("Dupe")
        store.importShared(playlist)
        store.importShared(playlist)
        #expect(store.playlists.filter { $0.name == "Dupe" }.count == 1)
    }
}
