//
//  PlaylistImportTests.swift
//  SonavaTests
//
//  Playlist migration is the one acquisition lever no competitor claims, and
//  the official Spotify route is closed to indie developers by policy. So the
//  import has to work on what people can actually export — and the failure
//  that matters is not "it didn't parse", it is "it parsed and quietly lost a
//  fifth of the playlist". Every case here is a real shape from a real
//  exporter, including the ones with commas inside titles.
//

import Testing
import Foundation
@testable import Sonava

struct PlaylistParsingTests {

    // MARK: - CSV

    @Test("Exportify's CSV parses, columns in its own order")
    func parsesExportifyCSV() {
        let csv = """
        "Track URI","Track Name","Artist Name(s)","Album Name","Duration (ms)"
        "spotify:track:1","Weird Fishes","Radiohead","In Rainbows","307000"
        "spotify:track:2","Life, Death, Love and Freedom","John Mellencamp","Life, Death, Love and Freedom","240000"
        """
        let result = PlaylistImport.parse(csv, name: "Export")
        #expect(result.tracks.count == 2)
        #expect(result.tracks[0].title == "Weird Fishes")
        #expect(result.tracks[0].artist == "Radiohead")
        #expect(result.tracks[1].title == "Life, Death, Love and Freedom",
                "a comma inside a quoted title is not a column break")
    }

    @Test("A different exporter's column names still resolve")
    func parsesAlternateColumnNames() {
        let csv = """
        Title,Artist,Album
        Idioteque,Radiohead,Kid A
        Reckoner,Radiohead,In Rainbows
        """
        let result = PlaylistImport.parse(csv, name: "TuneMyMusic")
        #expect(result.tracks.count == 2)
        #expect(result.tracks[1].artist == "Radiohead")
        #expect(result.tracks[0].album == "Kid A")
    }

    @Test("Collaborators collapse to the lead artist for searching")
    func takesLeadArtist() {
        let csv = """
        "Track Name","Artist Name(s)"
        "Nothing","Burial, Four Tet, Thom Yorke"
        """
        let result = PlaylistImport.parse(csv, name: "x")
        #expect(result.tracks.first?.artist == "Burial",
                "searching for the whole credit list finds nothing anywhere")
    }

    // MARK: - M3U

    @Test("An M3U playlist parses from its EXTINF lines")
    func parsesM3U() {
        let m3u = """
        #EXTM3U
        #EXTINF:307,Radiohead - Weird Fishes
        /Users/me/Music/Radiohead/weird.mp3
        #EXTINF:245,Кино - Звезда по имени Солнце
        /Users/me/Music/Kino/zvezda.mp3
        """
        let result = PlaylistImport.parse(m3u, name: "Local")
        #expect(result.tracks.count == 2)
        #expect(result.tracks[0].artist == "Radiohead")
        #expect(result.tracks[1].title == "Звезда по имени Солнце")
        #expect(result.tracks[1].artist == "Кино")
    }

    @Test("An M3U with no metadata falls back to the file names")
    func parsesBareM3U() {
        let m3u = """
        #EXTM3U
        /music/Aphex Twin - Xtal.flac
        /music/Boards of Canada - Roygbiv.flac
        """
        let result = PlaylistImport.parse(m3u, name: "Bare")
        #expect(result.tracks.count == 2)
        #expect(result.tracks[0].artist == "Aphex Twin")
        #expect(result.tracks[0].title == "Xtal", "the extension is not part of the title")
    }

    // MARK: - Pasted text

    @Test("A pasted list parses, dashes and numbering and all")
    func parsesPlainText() {
        let text = """
        1. Massive Attack — Teardrop
        2. Portishead - Roads
        Tricky – Hell Is Round the Corner
        """
        let result = PlaylistImport.parse(text, name: "Pasted")
        #expect(result.tracks.count == 3)
        #expect(result.tracks[0].artist == "Massive Attack")
        #expect(result.tracks[0].title == "Teardrop", "the list number is not part of the artist")
        #expect(result.tracks[2].artist == "Tricky", "an en dash is a dash")
    }

    @Test("A line with no dash is still worth searching for")
    func handlesUnstructuredLines() {
        let result = PlaylistImport.parse("Just some song title", name: "x")
        #expect(result.tracks.count == 1)
        #expect(result.tracks[0].title == "Just some song title")
        #expect(result.tracks[0].artist.isEmpty)
    }

    @Test("Nothing in, nothing out — no phantom track")
    func handlesEmptyInput() {
        #expect(PlaylistImport.parse("", name: "x").tracks.isEmpty)
        #expect(PlaylistImport.parse("\n\n   \n", name: "x").tracks.isEmpty)
    }

    @Test("Windows line endings don't produce trailing rubbish")
    func handlesCRLF() {
        let result = PlaylistImport.parse("A — B\r\nC — D\r\n", name: "x")
        #expect(result.tracks.count == 2)
        #expect(result.tracks[1].title == "D")
    }
}

struct PlaylistMatchingTests {

    private func song(_ title: String, _ artist: String) -> Song {
        Song(id: "t:\(title)", title: title, artist: artist, album: "",
             source: .audius, gradientHex: Palette.hex(for: 0))
    }

    private func wanted(_ title: String, _ artist: String) -> PlaylistImport.ParsedTrack {
        .init(title: title, artist: artist, album: nil)
    }

    @Test("An exact match matches")
    func exactMatch() {
        #expect(PlaylistImport.matches(song("Weird Fishes", "Radiohead"),
                                       wanted("Weird Fishes", "Radiohead")))
    }

    @Test("A remaster is the same recording as far as a listener is concerned")
    func ignoresRemasterSuffixes() {
        #expect(PlaylistImport.matches(song("Karma Police - Remastered 2016", "Radiohead"),
                                       wanted("Karma Police", "Radiohead")))
        #expect(PlaylistImport.matches(song("Blue Monday", "New Order"),
                                       wanted("Blue Monday (Remastered)", "New Order")))
    }

    @Test("Punctuation and case don't decide a match")
    func ignoresPunctuation() {
        #expect(PlaylistImport.matches(song("Don't Look Back in Anger", "Oasis"),
                                       wanted("dont look back in anger", "oasis")))
    }

    @Test("A different song by the same artist is not a match")
    func rejectsWrongTitle() {
        #expect(!PlaylistImport.matches(song("Creep", "Radiohead"),
                                        wanted("Weird Fishes", "Radiohead")))
    }

    @Test("The same title by someone else is not a match")
    func rejectsWrongArtist() {
        #expect(!PlaylistImport.matches(song("Hurt", "Nine Inch Nails"),
                                        wanted("Hurt", "Johnny Cash")))
    }

    @Test("With no artist to check, the title alone may decide")
    func titleOnlyIsAllowed() {
        // Pasted lists often have no artist at all; refusing them outright
        // would make the paste path useless.
        #expect(PlaylistImport.matches(song("Teardrop", "Massive Attack"),
                                       wanted("Teardrop", "")))
    }

    @Test("An empty title never matches anything")
    func emptyTitleMatchesNothing() {
        #expect(!PlaylistImport.matches(song("Anything", "Anyone"), wanted("", "Anyone")))
    }

    @Test("Cyrillic titles match")
    func matchesCyrillic() {
        #expect(PlaylistImport.matches(song("Звезда по имени Солнце", "Кино"),
                                       wanted("Звезда по имени Солнце", "Кино")))
    }
}
