//
//  JamendoServiceTests.swift
//  SonavaTests
//
//  The Jamendo mapping against its documented v3.0 payload shape, plus two
//  error envelopes captured live from api.jamendo.com (2026-08-30): the API
//  answers HTTP 200 even when refusing, so the refusal detection *is* the
//  error handling and deserves its own proof.
//

import Foundation
import Testing
@testable import Sonava

struct JamendoServiceTests {

    // The documented /v3.0/tracks response shape (developer.jamendo.com),
    // ids and durations in the string/number mix real responses use.
    private static let tracksJSON = #"""
    {
      "headers": {
        "status": "success",
        "code": 0,
        "error_message": "",
        "warnings": "",
        "results_count": 2
      },
      "results": [
        {
          "id": "168",
          "name": "J'm'e FPM",
          "duration": 183,
          "artist_id": "7",
          "artist_name": "TriFace",
          "artist_idstr": "triface",
          "album_name": "Premiers Jets",
          "album_id": "24",
          "license_ccurl": "http://creativecommons.org/licenses/by-nc/2.0/",
          "position": 1,
          "releasedate": "2004-12-17",
          "album_image": "https://usercontent.jamendo.com?type=album&id=24&width=300",
          "audio": "https://prod-1.storage.jamendo.com/?trackid=168&format=mp32&from=app-devsite",
          "audiodownload": "https://prod-1.storage.jamendo.com/download/track/168/mp32/",
          "prourl": "",
          "shorturl": "https://jamen.do/t/168",
          "shareurl": "https://www.jamendo.com/track/168",
          "image": "https://usercontent.jamendo.com?type=track&id=168&width=300",
          "audiodownload_allowed": true
        },
        {
          "id": "169",
          "name": "Trackless",
          "duration": "201",
          "artist_name": "Someone",
          "album_name": null,
          "album_image": null,
          "image": "https://usercontent.jamendo.com?type=track&id=169&width=300",
          "audio": "",
          "audiodownload_allowed": false
        }
      ]
    }
    """#

    // Captured live 2026-08-30: HTTP 200, empty results, warning about
    // usage limits — a degenerate success, not an error.
    private static let rateLimitedJSON = #"""
    { "headers":{"status":"success","code":0,"error_message":"","warnings":"Usage limits are exceeded for this request, please contact Jamendo before we block your access to this request","results_count":0},"results":[]}
    """#

    // Captured live 2026-08-30: HTTP 200, status "failed" — a suspended
    // client id. This must throw, not show an empty shelf.
    private static let suspendedJSON = #"""
    {"headers":{"status":"failed","code":11,"error_message":"Jamendo Api Suspended Application Error: Your application has been suspended, please contact Jamendo","warnings":"","results_count":0},"results":[]}
    """#

    @Test func documentedPayloadMapsToSongs() throws {
        let songs = try JamendoService.songs(fromJSON: Data(Self.tracksJSON.utf8))
        #expect(songs.count == 1, "a track with an empty audio URL has nothing to play and must not pretend")
        let song = try #require(songs.first)
        #expect(song.id == "jamendo:168")
        #expect(song.title == "J'm'e FPM")
        #expect(song.artist == "TriFace")
        #expect(song.album == "Premiers Jets")
        #expect(song.source == .jamendo)
        #expect(song.durationSeconds == 183)
        #expect(song.streamURL?.absoluteString
            == "https://prod-1.storage.jamendo.com/?trackid=168&format=mp32&from=app-devsite")
        #expect(song.artworkURL?.absoluteString
            == "https://usercontent.jamendo.com?type=album&id=24&width=300")
    }

    @Test func jamendoTracksMayBeSavedOffline() throws {
        // Creative Commons, full-length: the downloadable set already
        // included `.jamendo` — the case just had no producer until now.
        let songs = try JamendoService.songs(fromJSON: Data(Self.tracksJSON.utf8))
        #expect(songs.allSatisfy { $0.isDownloadable })
    }

    @Test func rateLimitedSuccessIsAnEmptyListNotAnError() throws {
        let songs = try JamendoService.songs(fromJSON: Data(Self.rateLimitedJSON.utf8))
        #expect(songs.isEmpty)
    }

    @Test func suspendedApplicationThrowsInsteadOfShowingAnEmptyShelf() {
        #expect(throws: URLError.self) {
            try JamendoService.songs(fromJSON: Data(Self.suspendedJSON.utf8))
        }
    }
}
