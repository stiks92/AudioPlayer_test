//
//  ListeningHistoryTests.swift
//  SonavaTests
//
//  The log is written from a timer while a track plays, so the thing most
//  likely to break is double-counting: 40 minutes of listening must be one
//  event of 40 minutes, not 160 events of 15 seconds.
//

import Testing
import Foundation
@testable import Sonava

@MainActor
@Suite(.serialized)
struct ListeningHistoryTests {

    private static let filename = "listening.test.json"

    /// A fresh, isolated store — never the file the real app uses.
    private func makeHistory() -> ListeningHistory {
        let store = JSONFileStore<[PlayEvent]>(Self.filename, default: [])
        store.write([])
        return ListeningHistory(store: store)
    }

    private func song(_ id: String = "audius:1", artist: String = "A") -> Song {
        Song(id: id, title: "Tune", artist: artist, album: "Album",
             source: .audius, gradientHex: Palette.hex(for: 0))
    }

    @Test("A skip is not a listen")
    func skipsAreIgnored() {
        let history = makeHistory()
        history.record(song: song(), seconds: 5, session: UUID())
        #expect(history.events.isEmpty)
        #expect(history.hasHistory == false)
    }

    @Test("Repeated reports for one session update that listen instead of appending")
    func sessionUpdatesInPlace() {
        let history = makeHistory()
        let session = UUID()
        history.record(song: song(), seconds: 30, session: session)
        history.record(song: song(), seconds: 45, session: session)
        history.record(song: song(), seconds: 600, session: session)

        #expect(history.events.count == 1)
        #expect(history.events.first?.seconds == 600)
    }

    @Test("A new session for the same track is a separate listen")
    func newSessionAppends() {
        let history = makeHistory()
        history.record(song: song(), seconds: 60, session: UUID())
        history.record(song: song(), seconds: 60, session: UUID())
        #expect(history.events.count == 2)
        #expect(history.stats(range: .week).totalSeconds == 120)
    }

    @Test("An interleaved session still updates its own event")
    func interleavedSessions() {
        let history = makeHistory()
        let first = UUID(), second = UUID()
        history.record(song: song("a", artist: "A"), seconds: 30, session: first)
        history.record(song: song("b", artist: "B"), seconds: 30, session: second)
        // The user came back to the first track's session (e.g. a resumed play).
        history.record(song: song("a", artist: "A"), seconds: 300, session: first)

        #expect(history.events.count == 2)
        #expect(history.events.first?.seconds == 300)
        #expect(history.events.last?.seconds == 30)
    }

    @Test("The log survives a relaunch")
    func persistsAcrossRelaunch() {
        let history = makeHistory()
        history.record(song: song(), seconds: 120, session: UUID())

        let reopened = ListeningHistory(store: JSONFileStore(Self.filename, default: []))
        #expect(reopened.events.count == 1)
        #expect(reopened.events.first?.seconds == 120)
        #expect(reopened.hasHistory)
    }

    @Test("Clearing wipes both memory and disk")
    func clearing() {
        let history = makeHistory()
        history.record(song: song(), seconds: 120, session: UUID())
        history.clear()

        #expect(history.events.isEmpty)
        let reopened = ListeningHistory(store: JSONFileStore(Self.filename, default: []))
        #expect(reopened.events.isEmpty)
    }

    @Test("Events older than the retention window are dropped on load")
    func prunesAncientEvents() {
        let store = JSONFileStore<[PlayEvent]>(Self.filename, default: [])
        let ancient = PlayEvent(session: UUID(), songID: "old", title: "T", artist: "A",
                                source: .audius,
                                date: Date(timeIntervalSinceNow: -500 * 86_400), seconds: 300)
        let recent = PlayEvent(session: UUID(), songID: "new", title: "T", artist: "A",
                               source: .audius, date: Date(), seconds: 300)
        store.write([ancient, recent])

        let history = ListeningHistory(store: store)
        #expect(history.events.map(\.songID) == ["new"])
    }

    @Test("Stats come straight off the log")
    func statsFromLog() {
        let history = makeHistory()
        history.record(song: song("a", artist: "Nils"), seconds: 600, session: UUID())
        history.record(song: song("b", artist: "Ólafur"), seconds: 120, session: UUID())

        let stats = history.stats(range: .week)
        #expect(stats.totalSeconds == 720)
        #expect(stats.topArtists.first?.name == "Nils")
        #expect(stats.streak == 1)
    }
}
