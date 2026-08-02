//
//  SubsonicParityTests.swift
//  SonavaTests
//
//  The server client could do five things: ping, random songs, starred,
//  search, scan status. That is enough to *find* music and not enough to
//  *browse* it — no shelf of albums, no artist with their records, no
//  server-side playlists, no stars that mean the same thing in every client.
//  Half the roadmap's community wins and the whole server half of a CarPlay
//  tree sit on this layer.
//
//  The decoding is pinned against real payloads: the fixtures below are
//  trimmed copies of what Navidrome 0.63.2 actually returned, not shapes
//  invented from the specification. Two of them contain fields the app does
//  not read, deliberately — a DTO that only decodes when the server sends
//  exactly what we imagined is a DTO that breaks on the next server.
//

import Testing
import Foundation
@testable import Sonava

struct SubsonicDecodingTests {

    // The shapes below were captured from a live server; the extra keys are
    // kept so the test proves the decoder tolerates them.
    private let albumListJSON = """
    {"subsonic-response":{"status":"ok","albumList2":{"album":[
      {"id":"al-1","name":"Kalimba","artist":"Dr. Quandary","artistId":"ar-1",
       "coverArt":"al-1","songCount":11,"duration":2456,"year":2019,
       "genres":[{"name":"Electronic"}],"isCompilation":false,"playCount":3,
       "starred":"2026-01-02T10:00:00Z","musicBrainzId":"abc"}]}}}
    """

    private let artistsJSON = """
    {"subsonic-response":{"status":"ok","artists":{"index":[
      {"name":"D","artist":[{"id":"ar-1","name":"Dr. Quandary","albumCount":3,
        "coverArt":"ar-1","roles":["artist"],"sortName":"Quandary, Dr."}]},
      {"name":"S","artist":[{"id":"ar-2","name":"Sventa","albumCount":1,"coverArt":"ar-2"}]}
    ]}}}
    """

    private let albumJSON = """
    {"subsonic-response":{"status":"ok","album":{"id":"al-1","name":"Kalimba",
      "artist":"Dr. Quandary","coverArt":"al-1","songCount":2,"year":2019,
      "song":[
        {"id":"s-1","title":"Opening","artist":"Dr. Quandary","album":"Kalimba",
         "coverArt":"al-1","duration":214,"track":1,"year":2019,"bitRate":320,
         "suffix":"mp3","replayGain":{"trackGain":-3.5,"albumGain":-3.2,"trackPeak":1},
         "artists":[{"id":"ar-1","name":"Dr. Quandary"},{"id":"ar-9","name":"Sventa"}],
         "starred":"2026-01-02T10:00:00Z","bitDepth":16,"channelCount":2},
        {"id":"s-2","title":"Closing","artist":"Dr. Quandary","album":"Kalimba",
         "coverArt":"al-1","duration":190,"track":2,"suffix":"flac"}
      ]}}}
    """

    private let playlistsJSON = """
    {"subsonic-response":{"status":"ok","playlists":{"playlist":[
      {"id":"pl-1","name":"Late night","songCount":42,"duration":9600,
       "coverArt":"pl-1","owner":"demo","public":true,"readonly":false,
       "created":"2025-01-01T00:00:00Z","changed":"2026-01-01T00:00:00Z"}]}}}
    """

    // MARK: - The service's own mapping

    private func service() -> SubsonicService {
        SubsonicService(baseURL: URL(string: "https://music.example.org")!,
                        username: "alice", password: "hunter2", libraryID: "LIB")
    }

    @Test("An album list decodes, keeping the fields a shelf needs")
    func decodesAlbumList() throws {
        let albums = try service().albumsForTesting(json: albumListJSON)
        let album = try #require(albums.first)
        #expect(album.title == "Kalimba")
        #expect(album.artist == "Dr. Quandary")
        #expect(album.year == 2019)
        #expect(album.trackCount == 11, "the count comes from the server before the tracks do")
        #expect(album.needsTracks, "a browse row is real but its songs are still to be fetched")
        #expect(album.serverID == "al-1")
        #expect(album.id == "subsonic:LIB:al-1", "ids are namespaced per library")
    }

    @Test("Artists arrive flattened out of the server's A–Z buckets")
    func decodesArtists() throws {
        let artists = try service().artistsForTesting(json: artistsJSON)
        #expect(artists.count == 2, "two buckets, two artists — the letters are not content")
        #expect(artists.map(\.name) == ["Dr. Quandary", "Sventa"])
        #expect(artists.first?.albumCount == 3)
    }

    @Test("An album's tracks keep their order, gain and credits")
    func decodesAlbumTracks() throws {
        let songs = try service().albumTracksForTesting(json: albumJSON)
        #expect(songs.count == 2)

        let first = try #require(songs.first)
        #expect(first.trackNumber == 1)
        #expect(first.durationSeconds == 214)
        #expect(first.replayGain == -3.5, "the server's own measurement saves us analysing the file")
        #expect(first.credits.map(\.name) == ["Dr. Quandary", "Sventa"],
                "a collaboration must stay two tappable people, not one invented performer")
        #expect(first.isStarredOnServer)

        // The second track omits half the fields — servers vary, and a DTO
        // that only decodes complete rows is a DTO that fails on the next one.
        let second = try #require(songs.last)
        #expect(second.replayGain == nil)
        #expect(second.credits.isEmpty)
        #expect(second.isStarredOnServer == false)
        #expect(second.year == nil)
    }

    @Test("Server playlists decode with a countable subtitle")
    func decodesPlaylists() throws {
        let playlists = try service().playlistsForTesting(json: playlistsJSON)
        let playlist = try #require(playlists.first)
        #expect(playlist.name == "Late night")
        #expect(playlist.songCount == 42)
        #expect(playlist.duration == 9600)
        #expect(playlist.subtitle.contains("42"))
        #expect(playlist.subtitle.contains("160"), "9600 seconds is 160 minutes")
    }

    @Test("A response with nothing in it yields nothing, not a crash")
    func decodesEmptyResponses() throws {
        let empty = """
        {"subsonic-response":{"status":"ok"}}
        """
        #expect(try service().albumsForTesting(json: empty).isEmpty)
        #expect(try service().artistsForTesting(json: empty).isEmpty)
        #expect(try service().playlistsForTesting(json: empty).isEmpty)
    }
}

struct SubsonicURLTests {

    private func service() -> SubsonicService {
        SubsonicService(baseURL: URL(string: "https://music.example.org")!,
                        username: "alice", password: "hunter2", libraryID: "LIB")
    }

    @Test("A stream URL is salted-token authenticated, never the raw password")
    func streamURLUsesTokenAuth() throws {
        let url = try #require(service().streamURL(id: "s-1"))
        let query = url.query ?? ""
        #expect(query.contains("u=alice"))
        #expect(query.contains("t="))
        #expect(query.contains("s="))
        #expect(!query.contains("hunter2"), "the password itself must never travel")
    }

    @Test("Each request gets a fresh salt")
    func saltsDiffer() throws {
        let first = try #require(service().streamURL(id: "s-1")).query ?? ""
        let second = try #require(service().streamURL(id: "s-1")).query ?? ""
        #expect(first != second, "a fixed salt makes the token a reusable password")
    }
}
