//
//  ScrobbleQueueTests.swift
//  SonavaTests
//
//  Scrobbling promises a complete listening history, so the listens that
//  happen away from a network — the underground, a flight, the minutes a
//  phone spends between cells — are exactly the ones that must not vanish.
//  They used to: submission was fire-and-forget. These pin the queue's
//  contract without touching the network.
//

import Testing
import Foundation
@testable import Sonava

@MainActor
struct ScrobbleQueueTests {

    /// A queue file per test, so runs can't see each other's backlog.
    private func freshStore() -> ScrobbleStore {
        JSONFileStore<[ScrobbleStore.PendingListen]>("scrobble_queue.json", default: []).write([])
        return ScrobbleStore()
    }

    private func listen(_ title: String, minutesAgo: Double = 0) -> ScrobbleStore.PendingListen {
        ScrobbleStore.PendingListen(title: title, artist: "Artist", album: "Album",
                                    source: TrackSource.audius.rawValue,
                                    listenedAt: Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60))
    }

    @Test("A queued listen survives a relaunch")
    func queuePersists() {
        let store = JSONFileStore<[ScrobbleStore.PendingListen]>("scrobble_queue.json", default: [])
        store.write([listen("Undertow"), listen("First Light")])

        let reloaded = ScrobbleStore()
        #expect(reloaded.pendingCount == 2, "the backlog must outlive the process")
    }

    @Test("A pending listen keeps the time it actually happened")
    func timestampIsPreserved() throws {
        let original = listen("Halcyon Drift", minutesAgo: 90)
        let store = JSONFileStore<[ScrobbleStore.PendingListen]>("scrobble_queue.json", default: [])
        store.write([original])

        let round = try #require(store.read().first)
        #expect(round.listenedAt == original.listenedAt,
                "a listen queued today must still land on the right day")
        #expect(round == original)
    }

    @Test("The source travels, because it decides whether a listen scrobbles at all")
    func sourceSurvives() throws {
        // `ScrobbleService.isScrobblable` rejects previews by source. A queued
        // listen is rebuilt from these fields, so losing the source would turn
        // a legitimate Audius play into an unscrobblable one on flush.
        let store = JSONFileStore<[ScrobbleStore.PendingListen]>("scrobble_queue.json", default: [])
        store.write([listen("Roman Candle")])
        let round = try #require(store.read().first)

        let rebuilt = Song(id: "queued:1", title: round.title, artist: round.artist,
                           album: round.album,
                           source: TrackSource(rawValue: round.source) ?? .local,
                           gradientHex: Palette.hex(for: 0))
        #expect(ScrobbleService.isScrobblable(rebuilt))
    }

    @Test("Nothing is queued while scrobbling is switched off")
    func disabledQueuesNothing() {
        let store = freshStore()
        store.isEnabled = false
        store.scrobbleListen(Song(id: "audius:1", title: "T", artist: "A", album: "B",
                                  source: .audius, gradientHex: Palette.hex(for: 0)))
        #expect(store.pendingCount == 0, "a listener who turned it off is not owed a backlog")
    }

    @Test("A preview is never queued — it was never scrobblable")
    func previewsAreNotQueued() {
        let store = freshStore()
        store.scrobbleListen(Song(id: "deezer:1", title: "T", artist: "A", album: "B",
                                  source: .deezer, gradientHex: Palette.hex(for: 0)))
        #expect(store.pendingCount == 0)
    }

    @Test("Flushing an empty queue is a no-op, not a crash")
    func flushEmpty() {
        let store = freshStore()
        store.flush()
        #expect(store.pendingCount == 0)
    }
}
