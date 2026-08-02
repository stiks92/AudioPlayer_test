//
//  DownloadStoreTests.swift
//  SonavaTests
//
//  Offline downloads are a headline Pro feature, so the round trip — download,
//  resolve a local URL, survive a relaunch, remove — is covered end to end.
//  A file:// source stands in for the network so the test is deterministic.
//

import Testing
import Foundation
@testable import Sonava

@MainActor
@Suite(.serialized)
struct DownloadStoreTests {

    init() {
        // Clear any prior downloads + manifest.
        let dir = DownloadStore.directory
        for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: f)
        }
        JSONFileStore<[Song]>("downloads.json", default: []).write([])
        // The pending index too: an entry left by an earlier case would make
        // the store treat a fresh download as already in flight.
        JSONFileStore<[Song]>("downloads_pending.json", default: []).write([])
    }

    /// A downloadable song whose "stream" is a local file we just wrote.
    private func downloadableSong(id: String = "audius:1") throws -> Song {
        let source = try TestAudioFile.makeTone(named: "src.m4a", seconds: 0.5)
        return Song(id: id, title: "Tune", artist: "A", album: "B",
                    source: .audius, fileExtension: "m4a",
                    streamURL: source, gradientHex: Palette.hex(for: 0))
    }

    private func waitForDownload(_ store: DownloadStore, _ song: Song) async {
        for _ in 0..<50 where !store.isDownloaded(song) {
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    @Test("Downloading saves the file and resolves a local URL")
    func downloadResolvesLocalURL() async throws {
        let song = try downloadableSong()
        defer { TestAudioFile.cleanUp(song.streamURL!) }

        let store = DownloadStore(useBackgroundSession: false)
        store.download(song)
        await waitForDownload(store, song)

        #expect(store.isDownloaded(song))
        let local = try #require(store.localURL(for: song))
        #expect(local.isFileURL)
        #expect(FileManager.default.fileExists(atPath: local.path))
    }

    @Test("Previews and radio are never downloadable")
    func rejectsIneligibleSources() {
        for source in [TrackSource.deezer, .itunes, .radio, .podcast, .local] {
            let song = Song(id: "x:\(source.rawValue)", title: "T", artist: "A", album: "B",
                            source: source, streamURL: URL(string: "https://example.com/x"),
                            gradientHex: Palette.hex(for: 0))
            let store = DownloadStore(useBackgroundSession: false)
            store.download(song)
            #expect(store.state(for: song) == .none, "\(source) should not download")
        }
    }

    @Test("A downloaded track is listed and survives a relaunch")
    func persistsAcrossLaunch() async throws {
        let song = try downloadableSong(id: "audius:persist")
        defer { TestAudioFile.cleanUp(song.streamURL!) }

        let store = DownloadStore(useBackgroundSession: false)
        store.download(song)
        await waitForDownload(store, song)
        #expect(store.downloads.contains { $0.id == song.id })

        let relaunched = DownloadStore(useBackgroundSession: false)
        #expect(relaunched.isDownloaded(song))
        #expect(relaunched.downloads.contains { $0.id == song.id })
    }

    @Test("Removing a download deletes the file and de-lists it")
    func removeDeletesFile() async throws {
        let song = try downloadableSong(id: "audius:remove")
        defer { TestAudioFile.cleanUp(song.streamURL!) }

        let store = DownloadStore(useBackgroundSession: false)
        store.download(song)
        await waitForDownload(store, song)
        let local = try #require(store.localURL(for: song))

        store.remove(song)

        #expect(store.isDownloaded(song) == false)
        #expect(store.downloads.isEmpty)
        #expect(FileManager.default.fileExists(atPath: local.path) == false)
    }

    @Test("An entry whose file vanished is pruned on relaunch")
    func prunesMissingFile() async throws {
        let song = try downloadableSong(id: "audius:ghost")
        defer { TestAudioFile.cleanUp(song.streamURL!) }

        let store = DownloadStore(useBackgroundSession: false)
        store.download(song)
        await waitForDownload(store, song)
        try FileManager.default.removeItem(at: #require(store.localURL(for: song)))

        #expect(DownloadStore(useBackgroundSession: false).isDownloaded(song) == false)
    }
}
