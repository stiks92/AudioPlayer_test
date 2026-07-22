//
//  MusicLibraryTests.swift
//  SonavaTests
//
//  Favourites and recents are the two things a listener would be genuinely
//  upset to lose, so they get covered properly — including persistence.
//

import Testing
import Foundation
@testable import Sonava

extension LibrarySuite {

@MainActor
@Suite(.serialized)
struct MusicLibraryTests {

    init() {
        TestAudioFile.clearMediaDirectory()
        JSONFileStore<[Song]>("favorites.json", default: []).write([])
        JSONFileStore<[Song]>("recents.json", default: []).write([])
        JSONFileStore<[Song]>("local-library.json", default: []).write([])
    }

    private func song(_ id: String, title: String = "Title", artist: String = "Artist") -> Song {
        Song(
            id: id, title: title, artist: artist, album: "Album",
            source: .audius,
            streamURL: URL(string: "https://example.com/\(id)"),
            gradientHex: Palette.hex(forSeed: id)
        )
    }

    // MARK: Favourites

    @Test("Favouriting is a toggle")
    func favoriteToggles() {
        let library = MusicLibrary()
        let track = song("a")

        #expect(library.isFavorite(track) == false)
        library.toggleFavorite(track)
        #expect(library.isFavorite(track))
        library.toggleFavorite(track)
        #expect(library.isFavorite(track) == false)
    }

    @Test("Newest favourite comes first")
    func favoritesAreNewestFirst() {
        let library = MusicLibrary()
        library.toggleFavorite(song("first"))
        library.toggleFavorite(song("second"))

        #expect(library.favorites.map(\.id) == ["second", "first"])
    }

    @Test("Favourites survive a relaunch")
    func favoritesPersist() {
        MusicLibrary().toggleFavorite(song("kept"))
        #expect(MusicLibrary().favorites.map(\.id) == ["kept"])
    }

    @Test("A favourited stream keeps everything needed to play it again")
    func favoritesStoreWholeSong() throws {
        let library = MusicLibrary()
        library.toggleFavorite(song("remote", title: "Remote Track"))

        // Only local files exist on disk, so a remote favourite has to carry
        // its own stream URL across launches or it becomes unplayable.
        let restored = try #require(MusicLibrary().favorites.first)
        #expect(restored.title == "Remote Track")
        #expect(restored.streamURL != nil)
    }

    // MARK: Recents

    @Test("Replaying a track moves it to the front instead of duplicating")
    func recentsDeduplicate() {
        let library = MusicLibrary()
        library.markPlayed(song("a"))
        library.markPlayed(song("b"))
        library.markPlayed(song("a"))

        #expect(library.recents.map(\.id) == ["a", "b"])
    }

    @Test("Recents are capped so the file cannot grow forever")
    func recentsAreCapped() {
        let library = MusicLibrary()
        for index in 0..<40 {
            library.markPlayed(song("track-\(index)"))
        }

        #expect(library.recents.count == 20)
        #expect(library.recents.first?.id == "track-39")
    }

    // MARK: Search

    @Test("Search matches title, artist and album, case-insensitively")
    func searchMatchesAllFields() async throws {
        let source = try TestAudioFile.makeTone(named: "Midnight Drive.m4a")
        defer { TestAudioFile.cleanUp(source) }

        let library = MusicLibrary()
        _ = await library.importFiles(at: [source])

        #expect(library.search("midnight").count == 1)
        #expect(library.search("MIDNIGHT").count == 1)
        #expect(library.search("nothing here").isEmpty)
    }

    @Test("Blank search returns nothing rather than everything")
    func blankSearchIsEmpty() {
        let library = MusicLibrary()
        #expect(library.search("").isEmpty)
        #expect(library.search("   ").isEmpty)
    }

    // MARK: Removal

    @Test("Removing a track also clears it from favourites and recents")
    func removeClearsEverywhere() async throws {
        let source = try TestAudioFile.makeTone(named: "doomed.m4a")
        defer { TestAudioFile.cleanUp(source) }

        let library = MusicLibrary()
        let track = try #require(await library.importFiles(at: [source]).first)
        library.toggleFavorite(track)
        library.markPlayed(track)

        library.remove(track)

        #expect(library.songs.isEmpty)
        #expect(library.favorites.isEmpty)
        #expect(library.recents.isEmpty)
    }
}
}
