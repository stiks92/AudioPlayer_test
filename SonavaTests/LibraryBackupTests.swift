//
//  LibraryBackupTests.swift
//  SonavaTests
//
//  The backup exists because "I changed phones and everything was gone" is
//  the most damaging review a music app can collect. So the contract it has
//  to keep is narrow and absolute: what goes in comes out, restoring never
//  destroys, passwords never travel, and the file says which audio files the
//  new phone is still missing rather than pretending the library is whole.
//

import Testing
import Foundation
@testable import Sonava

struct LibraryBackupCodecTests {

    private func song(_ id: String, source: TrackSource = .local, file: String? = nil) -> Song {
        Song(id: id, title: "Track \(id)", artist: "Artist", album: "Album",
             source: source, fileName: file, gradientHex: Palette.hex(forSeed: id))
    }

    /// Distinct dates per case: the exported filename is derived from the
    /// timestamp, so a shared one makes parallel tests fight over one path.
    private func sample(at date: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> LibraryBackup {
        LibraryBackup(
            version: LibraryBackup.currentVersion,
            createdAt: date,
            appVersion: "1.0",
            playlists: [UserPlaylist(name: "Road", tracks: [song("a")])],
            favorites: [song("b")],
            recents: [song("c")],
            localFiles: [song("d", file: "track-d.mp3")],
            servers: [ServerConnection(id: "s1", label: "Home",
                                       urlString: "https://music.home.arpa", username: "alice")],
            equalizer: EqualizerSettings(),
            downloadedIDs: ["a"])
    }

    @Test("A backup round-trips through a real file")
    func roundTripsThroughDisk() throws {
        let original = sample()
        let url = try #require(original.writeToFile())
        defer { try? FileManager.default.removeItem(at: url) }

        let read = try #require(LibraryBackup.read(from: url))
        #expect(read.playlists.map(\.name) == ["Road"])
        #expect(read.favorites.map(\.id) == ["b"])
        #expect(read.servers.map(\.urlString) == ["https://music.home.arpa"])
        #expect(read.localFiles.compactMap(\.fileName) == ["track-d.mp3"])
        #expect(read.downloadedIDs == ["a"])
        #expect(read.createdAt == original.createdAt)
    }

    @Test("The file carries no passwords")
    func noPasswordsInFile() throws {
        let url = try #require(sample(at: Date(timeIntervalSince1970: 1_800_000_100)).writeToFile())
        defer { try? FileManager.default.removeItem(at: url) }
        let raw = try String(contentsOf: url, encoding: .utf8)

        // `ServerConnection` deliberately has no password field; this pins it,
        // because a backup a listener emails themselves is exactly the file
        // that must not contain one.
        #expect(!raw.lowercased().contains("password"))
        #expect(raw.contains("alice"))   // the username does travel
    }

    @Test("A file from a newer version is refused rather than half-restored")
    func refusesFutureVersions() throws {
        var future = sample(at: Date(timeIntervalSince1970: 1_800_000_200))
        future = LibraryBackup(version: LibraryBackup.currentVersion + 1,
                               createdAt: future.createdAt, appVersion: "99",
                               playlists: future.playlists, favorites: future.favorites,
                               recents: future.recents, localFiles: future.localFiles,
                               servers: future.servers, equalizer: future.equalizer,
                               downloadedIDs: future.downloadedIDs)
        let url = try #require(future.writeToFile())
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(LibraryBackup.read(from: url) == nil,
                "a partial restore that looks like success is worse than a refusal")
    }

    @Test("A file that isn't ours is refused, not crashed on")
    func refusesForeignFiles() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-backup-\(UUID().uuidString).json")
        try "{\"hello\":\"world\"}".data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(LibraryBackup.read(from: url) == nil)
    }
}

@MainActor
struct LibraryBackupRestoreTests {

    private func song(_ id: String, file: String? = nil) -> Song {
        Song(id: id, title: "Track \(id)", artist: "Artist", album: "Album",
             source: .local, fileName: file, gradientHex: Palette.hex(forSeed: id))
    }

    private func freshPlaylistStore() -> PlaylistStore {
        JSONFileStore<[UserPlaylist]>("user_playlists.json", default: []).write([])
        return PlaylistStore()
    }

    private func backup(playlists: [UserPlaylist] = [],
                        favorites: [Song] = [],
                        localFiles: [Song] = [],
                        servers: [ServerConnection] = []) -> LibraryBackup {
        LibraryBackup(version: LibraryBackup.currentVersion, createdAt: Date(),
                      appVersion: "1.0", playlists: playlists, favorites: favorites,
                      recents: [], localFiles: localFiles, servers: servers,
                      equalizer: EqualizerSettings(), downloadedIDs: [])
    }

    @Test("Restoring adds playlists")
    func restoresPlaylists() {
        let store = freshPlaylistStore()
        let outcome = backup(playlists: [UserPlaylist(name: "From the old phone", tracks: [song("a")])])
            .restore(library: MusicLibrary(), playlists: store,
                     servers: ServerStore(store: JSONFileStore("servers-test.json", default: [])),
                     effects: AudioEffects(store: JSONFileStore("eq-test.json", default: EqualizerSettings())))

        #expect(outcome.playlistsAdded == 1)
        #expect(store.playlists.contains { $0.name == "From the old phone" })
    }

    @Test("Restoring twice doesn't duplicate — a nervous listener may tap it again")
    func restoreIsIdempotent() {
        let store = freshPlaylistStore()
        let file = backup(playlists: [UserPlaylist(name: "Road", tracks: [song("a")])])
        let servers = ServerStore(store: JSONFileStore("servers-test2.json", default: []))
        let effects = AudioEffects(store: JSONFileStore("eq-test2.json", default: EqualizerSettings()))

        _ = file.restore(library: MusicLibrary(), playlists: store, servers: servers, effects: effects)
        let second = file.restore(library: MusicLibrary(), playlists: store, servers: servers, effects: effects)

        #expect(second.playlistsAdded == 0)
        #expect(store.playlists.filter { $0.name == "Road" }.count == 1)
    }

    @Test("Restoring never deletes what is already on this phone")
    func restoreOnlyMerges() {
        let store = freshPlaylistStore()
        store.create("Mine, made here")
        _ = backup(playlists: [UserPlaylist(name: "Theirs", tracks: [song("a")])])
            .restore(library: MusicLibrary(), playlists: store,
                     servers: ServerStore(store: JSONFileStore("servers-test3.json", default: [])),
                     effects: AudioEffects(store: JSONFileStore("eq-test3.json", default: EqualizerSettings())))

        #expect(store.playlists.contains { $0.name == "Mine, made here" },
                "a mistaken tap must never cost the listener their own playlists")
    }

    @Test("The restore names the audio files this phone is missing")
    func reportsMissingFiles() {
        let outcome = backup(localFiles: [song("d", file: "rumours.flac"),
                                          song("e", file: "currents.flac")])
            .restore(library: MusicLibrary(), playlists: freshPlaylistStore(),
                     servers: ServerStore(store: JSONFileStore("servers-test4.json", default: [])),
                     effects: AudioEffects(store: JSONFileStore("eq-test4.json", default: EqualizerSettings())))

        #expect(outcome.missingFiles == ["currents.flac", "rumours.flac"],
                "the listener needs the list to finish the move")
    }

    @Test("A restored server arrives without a password, ready to be asked for one")
    func serversArriveWithoutPasswords() {
        // Store files outlive a test run, so a second run would find the
        // server already there and legitimately add nothing.
        let file = JSONFileStore<[ServerConnection]>("servers-test5.json", default: [])
        file.write([])
        let servers = ServerStore(store: file)
        let outcome = backup(servers: [ServerConnection(id: "s1", label: "Home",
                                                        urlString: "https://music.home.arpa",
                                                        username: "alice")])
            .restore(library: MusicLibrary(), playlists: freshPlaylistStore(),
                     servers: servers,
                     effects: AudioEffects(store: JSONFileStore("eq-test5.json", default: EqualizerSettings())))

        #expect(outcome.serversAdded == 1)
        #expect(servers.servers.first?.username == "alice")
        // No Keychain entry was created, so the service can't be built yet —
        // which is exactly the state the UI explains.
        #expect(servers.service == nil)
    }
}
