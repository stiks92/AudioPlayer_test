//
//  JellyfinServiceTests.swift
//  SonavaTests
//
//  The mapping from Jellyfin's JSON to the app's models, pinned against
//  payloads shaped exactly as a 10.9+ server sends them — PascalCase keys,
//  tick-based durations, bit rates in bits per second, and plenty of fields
//  the app has no use for. The extra keys are kept deliberately: a DTO that
//  only decodes when the server sends exactly what we imagined is a DTO that
//  breaks on the next server.
//
//  No test here touches the network. The auth header and the auth-response
//  parser are pure functions for precisely that reason.
//

import Testing
import Foundation
@testable import Sonava

struct JellyfinServiceTests {

    private func service() -> JellyfinService {
        JellyfinService(baseURL: URL(string: "https://jf.home.arpa")!,
                        username: "alice",
                        userID: "user-1",
                        accessToken: "tok-123",
                        libraryID: "LIB-1")
    }

    // MARK: - Fixtures (shape: Jellyfin 10.9+, /Items envelope)

    private let songsJSON = """
    {"Items":[
      {"Name":"Opening","ServerId":"9f4e21c0a1b2","Id":"song-1","CanDelete":false,
       "CanDownload":true,"Container":"flac","SortName":"opening",
       "DateCreated":"2025-11-02T18:03:22.79Z","PremiereDate":"2019-01-01T00:00:00Z",
       "MediaSources":[{"Protocol":"File","Id":"song-1","Type":"Default",
         "Container":"flac","Size":31834412,"Name":"01 - Opening","IsRemote":false,
         "ETag":"c9d8","RunTimeTicks":2140000000,"ReadAtNativeFramerate":false,
         "SupportsTranscoding":true,"SupportsDirectStream":true,"SupportsDirectPlay":true,
         "Bitrate":911000,"DefaultAudioStreamIndex":0,
         "MediaStreams":[{"Codec":"flac","Type":"Audio","Index":0,"SampleRate":44100,
           "Channels":2,"BitDepth":16,"IsDefault":true}]}],
       "RunTimeTicks":2140000000,"ProductionYear":2019,"IndexNumber":1,
       "ParentIndexNumber":1,"IsFolder":false,"Type":"Audio",
       "UserData":{"PlaybackPositionTicks":0,"PlayCount":4,"IsFavorite":true,
         "Played":true,"Key":"Kalimba-1-1"},
       "Artists":["Dr. Quandary","Sventa"],
       "ArtistItems":[{"Name":"Dr. Quandary","Id":"artist-1"},{"Name":"Sventa","Id":"artist-9"}],
       "Album":"Kalimba","AlbumId":"album-1","AlbumPrimaryImageTag":"albumtag1",
       "AlbumArtist":"Dr. Quandary","AlbumArtists":[{"Name":"Dr. Quandary","Id":"artist-1"}],
       "ImageTags":{"Primary":"tagsong1"},"BackdropImageTags":[],
       "LocationType":"FileSystem","MediaType":"Audio"},
      {"Name":"Closing","ServerId":"9f4e21c0a1b2","Id":"song-2","Type":"Audio",
       "RunTimeTicks":1900000000,"IndexNumber":2,"IsFolder":false,
       "UserData":{"PlaybackPositionTicks":0,"PlayCount":0,"IsFavorite":false,
         "Played":false,"Key":"Kalimba-1-2"},
       "Artists":["Dr. Quandary"],
       "ArtistItems":[{"Name":"Dr. Quandary","Id":"artist-1"}],
       "Album":"Kalimba","AlbumId":"album-1","AlbumPrimaryImageTag":"albumtag1",
       "AlbumArtist":"Dr. Quandary","ImageTags":{},"BackdropImageTags":[],
       "MediaType":"Audio"}
    ],"TotalRecordCount":2,"StartIndex":0}
    """

    private let albumsJSON = """
    {"Items":[
      {"Name":"Kalimba","ServerId":"9f4e21c0a1b2","Id":"album-1","CanDelete":false,
       "SortName":"kalimba","RunTimeTicks":40400000000,"ProductionYear":2019,
       "IsFolder":true,"Type":"MusicAlbum","UserData":{"PlaybackPositionTicks":0,
         "PlayCount":0,"IsFavorite":false,"Played":false,"Key":"album-1"},
       "ChildCount":11,"Artists":["Dr. Quandary"],
       "ArtistItems":[{"Name":"Dr. Quandary","Id":"artist-1"}],
       "AlbumArtist":"Dr. Quandary",
       "AlbumArtists":[{"Name":"Dr. Quandary","Id":"artist-1"}],
       "ImageTags":{"Primary":"albumtag1"},"BackdropImageTags":[],
       "LocationType":"FileSystem","MediaType":"Unknown"}
    ],"TotalRecordCount":1,"StartIndex":0}
    """

    private let artistsJSON = """
    {"Items":[
      {"Name":"Dr. Quandary","ServerId":"9f4e21c0a1b2","Id":"artist-1",
       "SortName":"dr. quandary","Type":"MusicArtist","IsFolder":true,
       "ImageTags":{"Primary":"artisttag1"},"BackdropImageTags":[],
       "AlbumCount":3,"LocationType":"FileSystem"},
      {"Name":"Sventa","ServerId":"9f4e21c0a1b2","Id":"artist-9",
       "SortName":"sventa","Type":"MusicArtist","IsFolder":true,
       "ImageTags":{},"BackdropImageTags":[],"LocationType":"FileSystem"}
    ],"TotalRecordCount":2,"StartIndex":0}
    """

    private let playlistsJSON = """
    {"Items":[
      {"Name":"Late night","ServerId":"9f4e21c0a1b2","Id":"pl-1","CanDelete":true,
       "SortName":"late night","RunTimeTicks":96000000000,"IsFolder":true,
       "Type":"Playlist","ChildCount":42,"ImageTags":{"Primary":"pltag"},
       "BackdropImageTags":[],"MediaType":"Audio","LocationType":"FileSystem"}
    ],"TotalRecordCount":1,"StartIndex":0}
    """

    // MARK: - Songs

    @Test("A Jellyfin audio item becomes a fully described Song")
    func songMapping() throws {
        let songs = try service().songsForTesting(json: songsJSON)
        #expect(songs.count == 2)

        let song = try #require(songs.first)
        #expect(song.id == "jellyfin:LIB-1:song-1")
        #expect(song.title == "Opening")
        #expect(song.artist == "Dr. Quandary")
        #expect(song.album == "Kalimba")
        // The listener's own server — the same case Subsonic uses, so every
        // switch on "their own box" answers the same for both protocols.
        #expect(song.source == .subsonic)
        #expect(song.durationSeconds == 214)          // 2_140_000_000 ticks
        #expect(song.trackNumber == 1)
        #expect(song.year == 2019)
        #expect(song.bitRate == 911)                  // 911_000 bit/s → kbit/s
        #expect(song.fileExtension == "flac")
        #expect(song.isStarredOnServer)
        #expect(song.credits.map(\.name) == ["Dr. Quandary", "Sventa"])
        #expect(song.credits.map(\.id) == ["artist-1", "artist-9"])
    }

    @Test("A minimal item still maps — nothing is invented for absent fields")
    func sparseSongMapping() throws {
        let songs = try service().songsForTesting(json: songsJSON)
        let sparse = try #require(songs.last)
        #expect(sparse.id == "jellyfin:LIB-1:song-2")
        #expect(sparse.bitRate == nil)
        #expect(sparse.year == nil)
        #expect(sparse.fileExtension.isEmpty)
        #expect(sparse.isStarredOnServer == false)
        #expect(sparse.durationSeconds == 190)
    }

    @Test("The stream URL is the universal endpoint with the token in the query")
    func songStreamURL() throws {
        let song = try #require(service().songsForTesting(json: songsJSON).first)
        let url = try #require(song.streamURL)
        #expect(url.path == "/Audio/song-1/universal")
        let query = url.query ?? ""
        #expect(query.contains("api_key=tok-123"))
        #expect(query.contains("UserId=user-1"))
        // Direct play for real audio containers, HLS only as the escape hatch.
        #expect(query.contains("TranscodingProtocol=hls"))
        #expect(query.contains("flac"))
    }

    @Test("A track with its own primary image uses it; one without borrows the album's")
    func artworkFallsBackToAlbum() throws {
        let songs = try service().songsForTesting(json: songsJSON)
        #expect(songs[0].artworkURL?.path == "/Items/song-1/Images/Primary")
        #expect(songs[1].artworkURL?.path == "/Items/album-1/Images/Primary")
    }

    // MARK: - Shelves

    @Test("An album row carries what the browse grid needs before any track is fetched")
    func albumMapping() throws {
        let album = try #require(service().albumsForTesting(json: albumsJSON).first)
        #expect(album.id == "jellyfin:LIB-1:album-1")
        #expect(album.title == "Kalimba")
        #expect(album.artist == "Dr. Quandary")
        #expect(album.year == 2019)
        #expect(album.serverID == "album-1")
        #expect(album.trackCountHint == 11)
        #expect(album.songs.isEmpty)
        #expect(album.artworkURL?.path == "/Items/album-1/Images/Primary")
    }

    @Test("Artists map with their counts, and a missing count stays zero rather than guessed")
    func artistMapping() throws {
        let artists = try service().artistsForTesting(json: artistsJSON)
        #expect(artists.count == 2)
        #expect(artists[0].id == "artist-1")
        #expect(artists[0].name == "Dr. Quandary")
        #expect(artists[0].albumCount == 3)
        #expect(artists[0].artworkURL?.path == "/Items/artist-1/Images/Primary")
        #expect(artists[1].albumCount == 0)
        #expect(artists[1].artworkURL == nil)
    }

    @Test("Playlists map with tick durations turned into seconds")
    func playlistMapping() throws {
        let playlist = try #require(service().playlistsForTesting(json: playlistsJSON).first)
        #expect(playlist.id == "pl-1")
        #expect(playlist.name == "Late night")
        #expect(playlist.songCount == 42)
        #expect(playlist.duration == 9600)
        #expect(playlist.artworkURL?.path == "/Items/pl-1/Images/Primary")
    }

    // MARK: - Auth

    @Test("The MediaBrowser header is assembled exactly as the spec wants it")
    func authorizationHeader() {
        let anonymous = JellyfinService.authorizationHeader(token: nil, deviceID: "dev-1")
        #expect(anonymous.hasPrefix("MediaBrowser "))
        #expect(anonymous.contains("Client=\"Sonava\""))
        #expect(anonymous.contains("Device=\"iPhone\""))
        #expect(anonymous.contains("DeviceId=\"dev-1\""))
        #expect(anonymous.contains("Version=\"1.0\""))
        #expect(!anonymous.contains("Token="))

        let signed = JellyfinService.authorizationHeader(token: "tok-123", deviceID: "dev-1")
        #expect(signed.contains("Token=\"tok-123\""))
        // Comma-separated pairs — the parser on the server splits on them.
        #expect(signed.components(separatedBy: ", ").count == 5)
    }

    @Test("The sign-in response yields the token and user id every request rides on")
    func authResponseParsing() throws {
        let json = """
        {"User":{"Name":"alice","ServerId":"9f4e21c0a1b2","Id":"user-1",
          "HasPassword":true,"HasConfiguredPassword":true,
          "EnableAutoLogin":false,"LastLoginDate":"2026-08-30T09:00:00Z",
          "Configuration":{"PlayDefaultAudioTrack":true,"SubtitleMode":"Default"},
          "Policy":{"IsAdministrator":false,"EnableMediaPlayback":true}},
         "SessionInfo":{"Id":"sess-1","UserId":"user-1","Client":"Sonava"},
         "AccessToken":"tok-123","ServerId":"9f4e21c0a1b2"}
        """
        let session = try JellyfinService.parseAuthResponse(Data(json.utf8))
        #expect(session.accessToken == "tok-123")
        #expect(session.userID == "user-1")
    }

    @Test("A response without a token fails loudly rather than minting a broken service")
    func authResponseWithoutToken() {
        #expect(throws: (any Error).self) {
            _ = try JellyfinService.parseAuthResponse(Data(#"{"ServerId":"x"}"#.utf8))
        }
    }

    // MARK: - URLs

    @Test("Cover art URLs point at the primary image with a bounded size")
    func coverArtURL() throws {
        let url = try #require(service().coverArtURL(id: "album-1"))
        #expect(url.path == "/Items/album-1/Images/Primary")
        let query = url.query ?? ""
        #expect(query.contains("fillWidth=512"))
        #expect(query.contains("api_key=tok-123"))
        #expect(service().coverArtURL(id: nil) == nil)
    }
}
