//
//  YouTubeImportTests.swift
//  SonavaTests
//
//  The YouTube playlist importer: the link parser (what people actually
//  paste), and the title→track mapping against the documented
//  playlistItems response shape. Composition only — there is deliberately
//  no playback surface here to test.
//

import Foundation
import Testing
@testable import Sonava

struct YouTubeLinkParsingTests {

    @Test func canonicalPlaylistLinksParse() {
        #expect(YouTubePlaylistImporter.playlistID(
            from: "https://www.youtube.com/playlist?list=PLdU2XZ8ZoSNQBjNzYm5rWt1jEjEsy9Gho")
            == "PLdU2XZ8ZoSNQBjNzYm5rWt1jEjEsy9Gho")
        #expect(YouTubePlaylistImporter.playlistID(
            from: "https://music.youtube.com/playlist?list=OLAK5uy_kg8DPKgL1COVQtVJb1kluakEz0Op2ArUY")
            == "OLAK5uy_kg8DPKgL1COVQtVJb1kluakEz0Op2ArUY")
        #expect(YouTubePlaylistImporter.playlistID(
            from: "https://m.youtube.com/playlist?list=PLdU2XZ8ZoSNQBjNzYm5rWt1jEjEsy9Gho")
            == "PLdU2XZ8ZoSNQBjNzYm5rWt1jEjEsy9Gho")
    }

    @Test func watchLinksCarryingAListParse() {
        #expect(YouTubePlaylistImporter.playlistID(
            from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLdU2XZ8ZoSNQBjNzYm5rWt1jEjEsy9Gho&index=3")
            == "PLdU2XZ8ZoSNQBjNzYm5rWt1jEjEsy9Gho")
        #expect(YouTubePlaylistImporter.playlistID(
            from: "https://youtu.be/dQw4w9WgXcQ?list=PLdU2XZ8ZoSNQBjNzYm5rWt1jEjEsy9Gho")
            == "PLdU2XZ8ZoSNQBjNzYm5rWt1jEjEsy9Gho")
    }

    @Test func aBareIDPastedFromAChatParses() {
        #expect(YouTubePlaylistImporter.playlistID(from: "  PLdU2XZ8ZoSNQBjNzYm5rWt1jEjEsy9Gho  ")
            == "PLdU2XZ8ZoSNQBjNzYm5rWt1jEjEsy9Gho")
    }

    @Test func whatIsNotAPlaylistIsRefused() {
        // A video link with no list is not a playlist.
        #expect(YouTubePlaylistImporter.playlistID(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ") == nil)
        // Another site entirely, even carrying a list param.
        #expect(YouTubePlaylistImporter.playlistID(
            from: "https://example.com/playlist?list=PLdU2XZ8ZoSNQBjNzYm5rWt1jEjEsy9Gho") == nil)
        // Prose, emptiness.
        #expect(YouTubePlaylistImporter.playlistID(from: "просто текст из чата") == nil)
        #expect(YouTubePlaylistImporter.playlistID(from: "") == nil)
    }

    @Test func sessionMixesAreRefusedUpFront() {
        // "RD…" radio mixes are generated per-session; the Data API cannot
        // read them, so refusing beats a confusing failure later.
        #expect(YouTubePlaylistImporter.playlistID(
            from: "https://www.youtube.com/watch?v=abc&list=RDdQw4w9WgXcQ") == nil)
    }
}

struct YouTubePageMappingTests {

    // The documented playlistItems?part=snippet response shape (Data API
    // v3 reference), with the row shapes that matter: a dashed title, an
    // auto-generated "Topic" upload with no dash, and the tombstones the
    // API leaves where videos used to be.
    private static let pageJSON = #"""
    {
      "kind": "youtube#playlistItemListResponse",
      "etag": "hzSF9EsD3dTC-zpAGCJWtnPo1RM",
      "nextPageToken": "EAAaBlBUOkNBVQ",
      "items": [
        {
          "kind": "youtube#playlistItem",
          "etag": "a1",
          "id": "UEwtRDBt",
          "snippet": {
            "publishedAt": "2024-03-01T10:00:00Z",
            "channelId": "UCowner",
            "title": "Massive Attack - Teardrop (Official Video) [HD]",
            "description": "…",
            "channelTitle": "playlist owner",
            "videoOwnerChannelTitle": "Massive Attack",
            "videoOwnerChannelId": "UCma",
            "playlistId": "PLdU2XZ8ZoSNQ",
            "position": 0,
            "resourceId": { "kind": "youtube#video", "videoId": "u7K72X4eo_s" }
          }
        },
        {
          "kind": "youtube#playlistItem",
          "etag": "a2",
          "id": "UEwtRDBu",
          "snippet": {
            "publishedAt": "2024-03-01T10:01:00Z",
            "channelId": "UCowner",
            "title": "Roygbiv",
            "channelTitle": "playlist owner",
            "videoOwnerChannelTitle": "Boards of Canada - Topic",
            "videoOwnerChannelId": "UCboc",
            "playlistId": "PLdU2XZ8ZoSNQ",
            "position": 1,
            "resourceId": { "kind": "youtube#video", "videoId": "yT0gRc2c2wQ" }
          }
        },
        {
          "kind": "youtube#playlistItem",
          "etag": "a3",
          "id": "UEwtRDBv",
          "snippet": {
            "publishedAt": "2024-03-01T10:02:00Z",
            "channelId": "UCowner",
            "title": "Private video",
            "channelTitle": "playlist owner",
            "playlistId": "PLdU2XZ8ZoSNQ",
            "position": 2,
            "resourceId": { "kind": "youtube#video", "videoId": "xxxxxxxxxxx" }
          }
        },
        {
          "kind": "youtube#playlistItem",
          "etag": "a4",
          "id": "UEwtRDBw",
          "snippet": {
            "publishedAt": "2024-03-01T10:03:00Z",
            "channelId": "UCowner",
            "title": "Deleted video",
            "channelTitle": "playlist owner",
            "playlistId": "PLdU2XZ8ZoSNQ",
            "position": 3,
            "resourceId": { "kind": "youtube#video", "videoId": "yyyyyyyyyyy" }
          }
        }
      ],
      "pageInfo": { "totalResults": 54, "resultsPerPage": 50 }
    }
    """#

    @Test func documentedPageMapsToParsedTracks() throws {
        let tracks = try YouTubePlaylistImporter.parsedTracks(fromJSON: Data(Self.pageJSON.utf8))
        #expect(tracks.count == 2, "private and deleted tombstones are not tracks")
        #expect(tracks[0].artist == "Massive Attack")
        #expect(tracks[0].title == "Teardrop", "the video dressing is not part of the title")
        #expect(tracks[1].title == "Roygbiv")
        #expect(tracks[1].artist == "Boards of Canada",
                "on a Topic channel the channel is the credit, minus the suffix")
    }

    @Test func nextPageTokenSurvivesDecoding() throws {
        let page = try JSONDecoder().decode(YouTubePlaylistPage.self, from: Data(Self.pageJSON.utf8))
        #expect(page.nextPageToken == "EAAaBlBUOkNBVQ")
        #expect(page.items.count == 4)
    }

    @Test func titleCleaningStripsDressingAndKeepsMeaning() {
        #expect(YouTubePlaylistImporter.cleanTitle("Artist - Song (Official Music Video)")
            == "Artist - Song")
        #expect(YouTubePlaylistImporter.cleanTitle("Artist - Song [Official Audio]")
            == "Artist - Song")
        #expect(YouTubePlaylistImporter.cleanTitle("Кино — Кукушка (клип)") == "Кино — Кукушка")
        #expect(YouTubePlaylistImporter.cleanTitle("Artist - Song (Acoustic)")
            == "Artist - Song (Acoustic)",
            "brackets carrying real information survive")
        #expect(YouTubePlaylistImporter.cleanTitle("Song (Lyrics) [4K]") == "Song")
    }

    @Test func aVideoTitleWithNoDashLeansOnItsChannel() throws {
        let track = try #require(YouTubePlaylistImporter.parsedTrack(
            title: "Xtal", channel: "Aphex Twin - Topic"))
        #expect(track.title == "Xtal")
        #expect(track.artist == "Aphex Twin")

        let orphan = try #require(YouTubePlaylistImporter.parsedTrack(
            title: "Some upload", channel: nil))
        #expect(orphan.artist.isEmpty, "no channel, no invented credit")
    }
}
