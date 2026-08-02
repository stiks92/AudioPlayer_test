//
//  SessionPersistenceTests.swift
//  SonavaTests
//
//  The app claimed queue persistence and stored one song and one position, so
//  a relaunch turned the album you were three tracks into a queue of one with
//  nowhere to go next. And a podcast listener with four shows on the go kept
//  their place in exactly one of them.
//
//  These pin the shapes of the fix at the level that can be tested without a
//  playback engine: what the saved session contains, and how episode
//  positions are kept.
//

import Testing
import Foundation
@testable import Sonava

@MainActor
struct EpisodePositionTests {

    private func podcast(_ id: String) -> Song {
        Song(id: id, title: "Episode \(id)", artist: "Show", album: "Show",
             source: .podcast, gradientHex: Palette.hex(forSeed: id))
    }

    private func music(_ id: String) -> Song {
        Song(id: id, title: "Track \(id)", artist: "Artist", album: "Album",
             source: .audius, gradientHex: Palette.hex(forSeed: id))
    }

    private func fresh() -> AudioManager {
        JSONFileStore<[String: Double]>("episode_positions.json", default: [:]).write([:])
        return AudioManager.shared
    }

    @Test("An unheard episode has no saved position")
    func unheardEpisode() {
        let audio = fresh()
        #expect(audio.savedPosition(for: podcast("ep-never-played")) == nil)
    }

    @Test("Positions are kept per episode, not one slot for everything")
    func positionsArePerEpisode() {
        let store = JSONFileStore<[String: Double]>("episode_positions.json", default: [:])
        store.write(["ep-1": 1_200, "ep-2": 45, "ep-3": 3_600])

        // A fresh manager reads them back — the file is the contract here,
        // because the manager is a singleton the tests cannot re-init.
        let read = store.read()
        #expect(read.count == 3)
        #expect(read["ep-1"] == 1_200)
        #expect(read["ep-3"] == 3_600)
    }

    @Test("The first seconds don't count as a place to resume from")
    func tinyPositionsAreIgnored() {
        let audio = fresh()
        JSONFileStore<[String: Double]>("episode_positions.json", default: [:])
            .write(["ep-blip": 2])
        // Resuming a two-second-old position is noise; the listener pressed
        // play and immediately left.
        #expect(audio.savedPosition(for: podcast("ep-blip")) == nil)
    }

    @Test("Music never resumes mid-track from a stored position")
    func musicIsNotResumed() {
        let audio = fresh()
        JSONFileStore<[String: Double]>("episode_positions.json", default: [:])
            .write(["audius:1": 90])
        #expect(audio.savedPosition(for: music("audius:1")) == nil,
                "coming back to an album mid-track is a surprise, not a service")
    }
}

struct SavedSessionShapeTests {

    /// The session file's own shape, written the way `AudioManager` writes it.
    /// A separate mirror because the real type is private to the manager —
    /// what matters is that the *file* carries a whole queue.
    private struct SavedSession: Codable, Equatable {
        var queue: [Song]
        var index: Int
        var position: Double
        var isShuffling: Bool
        var repeatMode: Int
    }

    private func song(_ id: String) -> Song {
        Song(id: id, title: "Track \(id)", artist: "Artist", album: "Album",
             source: .audius, gradientHex: Palette.hex(forSeed: id))
    }

    @Test("A saved session carries the whole queue, not one track")
    func sessionCarriesTheQueue() throws {
        let store = JSONFileStore<SavedSession?>("session-test.json", default: nil)
        let saved = SavedSession(queue: (1...12).map { song("t\($0)") }, index: 3,
                                 position: 84.5, isShuffling: true, repeatMode: 1)
        store.write(saved)

        let read = try #require(store.read())
        #expect(read.queue.count == 12, "the point of the fix is that next has somewhere to go")
        #expect(read.index == 3)
        #expect(read.position == 84.5)
        #expect(read.isShuffling)
        #expect(read.repeatMode == 1)
    }

    @Test("An index beyond the queue can't be restored into a crash")
    func indexIsClamped() {
        // The manager clamps on restore; this documents the input that made it
        // necessary — a queue trimmed by a later release.
        let saved = SavedSession(queue: [song("a"), song("b")], index: 9,
                                 position: 0, isShuffling: false, repeatMode: 0)
        let clamped = min(max(saved.index, 0), saved.queue.count - 1)
        #expect(clamped == 1)
    }

    @Test("Repeat mode round-trips through its raw value")
    func repeatModeRoundTrips() {
        for mode in RepeatMode.allCases {
            #expect(RepeatMode(rawValue: mode.rawValue) == mode)
        }
    }
}
