//
//  LocalFileStoreTests.swift
//  SonavaTests
//
//  The import path is the app's only source of local audio, so these cover
//  the whole round trip: copy in, read metadata, resolve a playable URL,
//  survive a relaunch, and delete.
//

import Testing
import Foundation
@testable import Sonava

extension LibrarySuite {

@MainActor
@Suite(.serialized)
struct LocalFileStoreTests {

    init() {
        TestAudioFile.clearMediaDirectory()
        JSONFileStore<[Song]>("local-library.json", default: []).write([])
    }

    @Test("Importing copies the file into the app's media directory")
    func importCopiesFile() async throws {
        let source = try TestAudioFile.makeTone(named: "imported.m4a")
        defer { TestAudioFile.cleanUp(source) }

        let store = LocalFileStore()
        let added = await store.importFiles(at: [source])

        #expect(added.count == 1)
        let song = try #require(added.first)
        let copied = try LocalFileStore.mediaDirectory.appendingPathComponent(#require(song.fileName))
        #expect(FileManager.default.fileExists(atPath: copied.path))

        // The original is only borrowed — deleting it must not break playback.
        try FileManager.default.removeItem(at: source)
        let playable = try #require(song.url)
        #expect(FileManager.default.fileExists(atPath: playable.path))
    }

    @Test("A file with no metadata falls back to its filename as the title")
    func fallsBackToFilename() async throws {
        let source = try TestAudioFile.makeTone(named: "My Field Recording.m4a")
        defer { TestAudioFile.cleanUp(source) }

        let store = LocalFileStore()
        let song = try #require(await store.importFiles(at: [source]).first)

        #expect(song.title == "My Field Recording")
        #expect(song.source == .local)
        #expect(song.isRemote == false)
    }

    @Test("Importing the same file twice adds it once")
    func importIsIdempotent() async throws {
        let source = try TestAudioFile.makeTone(named: "dupe.m4a")
        defer { TestAudioFile.cleanUp(source) }

        let store = LocalFileStore()
        _ = await store.importFiles(at: [source])
        let secondPass = await store.importFiles(at: [source])

        // The copy is disambiguated on disk, but the library must not grow a
        // duplicate entry for a file the user already has.
        #expect(secondPass.isEmpty)
        #expect(store.songs.count == 1)
    }

    @Test("Two different files with the same name both survive")
    func distinctFilesWithSameName() async throws {
        let first = try TestAudioFile.makeTone(named: "track01.m4a", seconds: 0.5)
        let second = try TestAudioFile.makeTone(named: "track01.m4a", seconds: 1.5)
        defer {
            TestAudioFile.cleanUp(first)
            TestAudioFile.cleanUp(second)
        }

        let store = LocalFileStore()
        _ = await store.importFiles(at: [first])
        _ = await store.importFiles(at: [second])

        #expect(store.songs.count == 2)
        #expect(Set(store.songs.map(\.id)).count == 2)
    }

    @Test("The library is restored on the next launch")
    func libraryPersists() async throws {
        let source = try TestAudioFile.makeTone(named: "persisted.m4a")
        defer { TestAudioFile.cleanUp(source) }

        _ = await LocalFileStore().importFiles(at: [source])

        let relaunched = LocalFileStore()
        #expect(relaunched.songs.count == 1)
        #expect(relaunched.songs.first?.title == "persisted")
    }

    @Test("Entries whose file vanished are dropped on launch")
    func prunesMissingFiles() async throws {
        let source = try TestAudioFile.makeTone(named: "ghost.m4a")
        defer { TestAudioFile.cleanUp(source) }

        let store = LocalFileStore()
        let song = try #require(await store.importFiles(at: [source]).first)

        // Simulate the user deleting it from the Files app behind our back.
        try FileManager.default.removeItem(at: #require(song.url))

        #expect(LocalFileStore().songs.isEmpty)
    }

    @Test("Removing a track deletes the file it copied in")
    func removeDeletesFile() async throws {
        let source = try TestAudioFile.makeTone(named: "removable.m4a")
        defer { TestAudioFile.cleanUp(source) }

        let store = LocalFileStore()
        let song = try #require(await store.importFiles(at: [source]).first)
        let copied = try #require(song.url)

        store.remove(song)

        #expect(store.songs.isEmpty)
        #expect(FileManager.default.fileExists(atPath: copied.path) == false)
    }
}
}
