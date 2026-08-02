//
//  JSONFileStoreTests.swift
//  SonavaTests
//
//  Every list the app owns — favourites, playlists, downloads, servers, the
//  imported library — is stored through this one type, so its failure modes
//  are the app's failure modes. Two of them used to be silent, and silent
//  data loss is the single loudest complaint in the competitor review
//  corpora. These tests exist so neither can come back.
//
//  The plain round-trip and missing-file cases live with the other model
//  tests; this file is only about what happens when the disk misbehaves.
//

import Testing
import Foundation
@testable import Sonava

struct JSONFileStoreResilienceTests {

    private struct Fixture: Codable, Equatable, Sendable {
        var tracks: [String]
    }

    /// A distinct filename per test so the cases can't see each other's files
    /// (they share one Application Support directory).
    private func store(_ label: String = #function) -> JSONFileStore<Fixture> {
        let name = "test-\(label.replacingOccurrences(of: "()", with: ""))-\(UUID().uuidString).json"
        return JSONFileStore(name, default: Fixture(tracks: []))
    }

    private func write(_ raw: String, to url: URL) throws {
        try raw.data(using: .utf8)!.write(to: url)
    }

    @Test("A damaged file is recovered from the backup, not silently emptied")
    func recoversFromBackup() throws {
        let store = store()
        store.write(Fixture(tracks: ["keep", "these"]))

        // Simulate a truncated write — the classic full-disk / crash artefact.
        try write("{\"tracks\": [\"kee", to: store.url)

        #expect(store.read() == Fixture(tracks: ["keep", "these"]),
                "the last saved value must come back instead of an empty list")
    }

    @Test("A damaged file is never destroyed by the act of reading it")
    func corruptFileIsQuarantined() throws {
        let store = store()
        store.write(Fixture(tracks: ["one"]))
        try write("not json at all", to: store.url)

        _ = store.read()

        let quarantined = try FileManager.default
            .contentsOfDirectory(atPath: JSONFileStore<Fixture>.directory.path)
            .filter { $0.hasPrefix(store.url.lastPathComponent) && $0.contains(".corrupt-") }
        #expect(!quarantined.isEmpty, "the unreadable bytes must be kept, not overwritten")
        for name in quarantined {
            try? FileManager.default.removeItem(
                at: JSONFileStore<Fixture>.directory.appendingPathComponent(name))
        }
    }

    @Test("A file lost between writes comes back from the backup")
    func recoversFromMissingMainFile() throws {
        let store = store()
        store.write(Fixture(tracks: ["first"]))
        store.write(Fixture(tracks: ["second"]))
        try FileManager.default.removeItem(at: store.url)

        #expect(store.read() == Fixture(tracks: ["second"]),
                "recovery returns the newest saved value, not a stale one")
    }

    @Test("A store stays recoverable even after the main file has gone bad once")
    func staysRecoverableAfterCorruption() throws {
        // The first design rolled the *previous file* into the backup slot,
        // which meant that once the main file was garbage every later write
        // skipped the roll — and the store quietly lost its only safety net.
        let store = store()
        store.write(Fixture(tracks: ["good"]))
        try write("garbage", to: store.url)
        store.write(Fixture(tracks: ["newer"]))        // must refresh the backup
        try write("garbage again", to: store.url)

        #expect(store.read() == Fixture(tracks: ["newer"]),
                "recovery must land on the last value actually saved")
    }

    @Test("A write reports success so callers can react")
    func writeReportsOutcome() {
        #expect(store().write(Fixture(tracks: ["x"])) == true)
    }

    @MainActor
    @Test("A read failure is recorded where the UI can see it")
    func failuresAreVisible() async throws {
        StorageDiagnostics.shared.clear()
        let store = store()
        store.write(Fixture(tracks: ["a"]))
        try write("{{{", to: store.url)
        _ = store.read()

        // The report hops to the main actor through a Task; yielding lets it
        // land. (Pumping a RunLoop here does not: the test already owns the
        // main actor, so the hop never gets a turn.)
        for _ in 0..<10 where StorageDiagnostics.shared.failures.isEmpty {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(!StorageDiagnostics.shared.failures.isEmpty,
                "silent data loss is the failure this whole file exists to prevent")
        StorageDiagnostics.shared.clear()
    }
}
