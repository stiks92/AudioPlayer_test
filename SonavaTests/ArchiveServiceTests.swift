//
//  ArchiveServiceTests.swift
//  SonavaTests
//
//  The Internet Archive mapping, proven against payloads captured live from
//  archive.org (advancedsearch + metadata APIs, 2026-08-30) — not against
//  fakes. The mapping is where a catalogue client actually breaks: creators
//  arriving as arrays, years as strings, lengths in three formats.
//

import Foundation
import Testing
@testable import Sonava

struct ArchiveServiceTests {

    // Captured live: advancedsearch over (etree OR netlabels OR 78rpm),
    // trimmed to 5 docs. One doc has no year at all.
    private static let searchJSON = #"""
    {"responseHeader":{"status":0,"QTime":16197,"params":{"query":"(collection:etree OR collection:netlabels OR collection:78rpm) AND format:MP3","wt":"json","rows":5,"start":0}},"response":{"numFound":673813,"start":0,"docs":[{"creator":"Umphreys McGee","downloads":12803,"identifier":"um2005-04-02.flac16","title":"Umphrey's McGee Live at La Zona Rosa on 2005-04-02","year":2005},{"creator":"Lemoness","downloads":943453,"identifier":"2014-02-12Bigwords","title":"2014-02-12 Bigwords","year":2014},{"creator":"Grateful Dead","downloads":4504,"identifier":"gd1983-09-04.aud.morris.111032..sbeok.flac24","title":"Grateful Dead Live at Park West Ski Resort on 1983-09-04","year":1983},{"creator":"The Popular Jazz Archive","downloads":26463,"identifier":"HaroldScrappyLambertCollection1927-1930","title":"Harold Scrappy Lambert Collection 1925-1935"},{"creator":"Grahame Lesh and Friends","downloads":2969,"identifier":"glf1402026-03-15","title":"Grahame Lesh and Friends Live at Capitol Theatre Port Chester N.Y on 2026-03-15","year":2026}]}}
    """#

    // Captured live: metadata for the Cornell '77 tape, trimmed to a
    // representative file list — a text file, five VBR MP3 derivatives, two
    // FLAC originals and the item thumbnail.
    private static let metadataJSON = #"""
    {
     "server": "ia600405.us.archive.org",
     "dir": "/2/items/gd1977-05-08.shure57.stevenson.29303.flac16",
     "metadata": {
      "identifier": "gd1977-05-08.shure57.stevenson.29303.flac16",
      "title": "Grateful Dead Live at Barton Hall - Cornell University on 1977-05-08",
      "creator": "Grateful Dead",
      "year": "1977",
      "date": "1977-05-08",
      "collection": ["GratefulDead", "etree"]
     },
     "files": [
      {"name": "gd1977-05-08.29303.txt", "source": "original", "format": "Text", "size": "1138"},
      {"name": "gd1977-05-08d01t01.mp3", "source": "derivative", "creator": "Grateful Dead", "title": "Turning", "track": "01", "album": "1977-05-08 - Barton Hall - Cornell University", "bitrate": "190", "length": "00:39", "format": "VBR MP3", "size": "948224"},
      {"name": "gd1977-05-08d01t02.mp3", "source": "derivative", "creator": "Grateful Dead", "title": "Minglewood Blues", "track": "02", "album": "1977-05-08 - Barton Hall - Cornell University", "bitrate": "197", "length": "05:23", "format": "VBR MP3", "size": "7966720"},
      {"name": "gd1977-05-08d01t03.mp3", "source": "derivative", "creator": "Grateful Dead", "title": "Loser", "track": "03", "album": "1977-05-08 - Barton Hall - Cornell University", "bitrate": "192", "length": "08:48", "format": "VBR MP3", "size": "12690432"},
      {"name": "gd1977-05-08d01t04.mp3", "source": "derivative", "creator": "Grateful Dead", "title": "El Paso", "track": "04", "album": "1977-05-08 - Barton Hall - Cornell University", "bitrate": "190", "length": "05:22", "format": "VBR MP3", "size": "7636480"},
      {"name": "gd1977-05-08d01t05.mp3", "source": "derivative", "creator": "Grateful Dead", "title": "They Love Each Other", "track": "05", "album": "1977-05-08 - Barton Hall - Cornell University", "bitrate": "189", "length": "08:46", "format": "VBR MP3", "size": "12453376"},
      {"name": "gd1977-05-08d01t01.flac", "source": "original", "format": "Flac", "title": "Turning", "creator": "Grateful Dead", "album": "1977-05-08 - Barton Hall - Cornell University", "track": "01", "length": "39.8"},
      {"name": "gd1977-05-08d01t02.flac", "source": "original", "format": "Flac", "title": "Minglewood Blues", "creator": "Grateful Dead", "album": "1977-05-08 - Barton Hall - Cornell University", "track": "02", "length": "323.81"},
      {"name": "__ia_thumb.jpg", "source": "original", "format": "Item Tile", "rotation": "0"}
     ]
    }
    """#

    // MARK: - Search docs

    @Test func searchDocsDecodeFromCapturedPayload() throws {
        let docs = try ArchiveService.docs(fromSearchJSON: Data(Self.searchJSON.utf8))
        #expect(docs.count == 5)
        #expect(docs[0].identifier == "um2005-04-02.flac16")
        #expect(docs[2].creator == "Grateful Dead")
        #expect(docs[2].year == 1983)
        #expect(docs[3].year == nil, "an item without a year stays without one — never invented")
    }

    @Test func creatorArrivingAsAnArrayStillDecodes() throws {
        // The search index really does this for multi-artist items.
        let json = #"""
        {"response":{"docs":[{"identifier":"duo1","title":"A Split Single","creator":["Artist One","Artist Two"],"year":"1959"}]}}
        """#
        let docs = try ArchiveService.docs(fromSearchJSON: Data(json.utf8))
        #expect(docs.count == 1)
        #expect(docs[0].creator == "Artist One", "the first credited name leads")
        #expect(docs[0].year == 1959, "a year sent as a string is still a year")
    }

    // MARK: - Metadata → Song

    @Test func onlyMP3DerivativesBecomeSongs() throws {
        let songs = try ArchiveService.songs(fromMetadataJSON: Data(Self.metadataJSON.utf8))
        #expect(songs.count == 5, "text files, FLAC originals and thumbnails are not tracks — and FLACs would double every song")
        #expect(songs.allSatisfy { $0.source == .archive })
    }

    @Test func songFieldsMapFromTheCapturedTape() throws {
        let songs = try ArchiveService.songs(fromMetadataJSON: Data(Self.metadataJSON.utf8))
        let first = try #require(songs.first)
        #expect(first.id == "archive:gd1977-05-08.shure57.stevenson.29303.flac16/gd1977-05-08d01t01.mp3")
        #expect(first.title == "Turning")
        #expect(first.artist == "Grateful Dead")
        #expect(first.album == "1977-05-08 - Barton Hall - Cornell University")
        #expect(first.durationSeconds == 39, "\"00:39\" is 39 seconds")
        #expect(first.trackNumber == 1)
        #expect(first.bitRate == 190)
        #expect(first.year == 1977, "the item's year covers files that have none")
        #expect(first.streamURL?.absoluteString
            == "https://archive.org/download/gd1977-05-08.shure57.stevenson.29303.flac16/gd1977-05-08d01t01.mp3")
        #expect(first.artworkURL?.absoluteString
            == "https://archive.org/services/img/gd1977-05-08.shure57.stevenson.29303.flac16")
    }

    @Test func archiveTracksMayBeSavedOffline() throws {
        // Freely-streamable collections, so the conservative call is yes —
        // and `.archive` was already in the downloadable set, waiting.
        let songs = try ArchiveService.songs(fromMetadataJSON: Data(Self.metadataJSON.utf8))
        #expect(songs.allSatisfy { $0.isDownloadable })
    }

    @Test func fileWithoutItsOwnTitleFallsBackToItsName() throws {
        let json = #"""
        {"metadata":{"identifier":"untagged78","title":"Some Shellac Side","creator":"Old Band"},
         "files":[{"name":"side-a.mp3","format":"128Kbps MP3","length":"180.2"}]}
        """#
        let songs = try ArchiveService.songs(fromMetadataJSON: Data(json.utf8))
        let song = try #require(songs.first)
        #expect(song.title == "side-a", "the file name minus its extension beats an empty row")
        #expect(song.artist == "Old Band", "the item's creator covers untagged files")
        #expect(song.album == "Some Shellac Side")
        #expect(song.durationSeconds == 180.2, "decimal-seconds lengths parse too")
    }

    @Test func fileNamesWithSpacesProduceValidStreamURLs() throws {
        let json = #"""
        {"metadata":{"identifier":"spacey","title":"T","creator":"C"},
         "files":[{"name":"01 - First Song.mp3","format":"VBR MP3"}]}
        """#
        let songs = try ArchiveService.songs(fromMetadataJSON: Data(json.utf8))
        let url = try #require(songs.first?.streamURL)
        #expect(url.absoluteString == "https://archive.org/download/spacey/01%20-%20First%20Song.mp3")
    }

    // MARK: - The three length formats

    @Test func lengthParsingHandlesEveryFormatTheAPIShips() {
        #expect(ArchiveService.seconds(fromLength: "05:23") == 323)
        #expect(ArchiveService.seconds(fromLength: "00:39") == 39)
        #expect(ArchiveService.seconds(fromLength: "1:02:33") == 3753, "hours happen — a whole concert set in one file")
        #expect(ArchiveService.seconds(fromLength: "39.8") == 39.8)
        #expect(ArchiveService.seconds(fromLength: nil) == nil)
        #expect(ArchiveService.seconds(fromLength: "") == nil)
        #expect(ArchiveService.seconds(fromLength: "not a length") == nil)
        #expect(ArchiveService.seconds(fromLength: "0") == nil, "zero is unknown, not a zero-second track")
    }

    @Test func trackNumbersParseWithAndWithoutTheDiscArithmetic() {
        #expect(ArchiveService.trackNumber(from: "01") == 1)
        #expect(ArchiveService.trackNumber(from: "5") == 5)
        #expect(ArchiveService.trackNumber(from: "5/12") == 5)
        #expect(ArchiveService.trackNumber(from: nil) == nil)
        #expect(ArchiveService.trackNumber(from: "A") == nil)
    }
}
