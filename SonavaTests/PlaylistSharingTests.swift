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
