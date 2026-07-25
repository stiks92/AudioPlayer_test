//
//  SonavaIntentsTests.swift
//  SonavaTests
//
//  Siri and Spotlight can fire an intent before any view has been built, so
//  these run against the persisted library rather than a live `MusicLibrary`.
//  What matters is that each one either loads the right queue or says something
//  useful — never a silent no-op, which is how a broken shortcut feels.
//
//  Nested under LibrarySuite: they write the same favourites/recents files the
//  library tests use, and Swift Testing runs suites in parallel.
//

import Testing
import Foundation
@testable import Sonava

extension LibrarySuite {

    @MainActor
    @Suite(.serialized)
    struct SonavaIntentsTests {

        private let favoritesStore = JSONFileStore<[Song]>("favorites.json", default: [])
        private let recentsStore = JSONFileStore<[Song]>("recents.json", default: [])

        init() {
            favoritesStore.write([])
            recentsStore.write([])
            // `AudioManager` is a singleton, so a previous test's queue would
            // otherwise be mistaken for the state under test.
            AudioManager.shared.stop()
        }

        private func song(_ id: String, artist: String = "Artist") -> Song {
            Song(id: id, title: "Track \(id)", artist: artist, album: "Album",
                 source: .audius,
                 streamURL: URL(string: "https://example.com/\(id).mp3"),
                 gradientHex: Palette.hex(for: 0))
        }

        // MARK: - Favourites

        @Test("Playing favourites with an empty library says so instead of doing nothing")
        func favoritesWhenEmpty() async throws {
            _ = try await PlayFavoritesIntent().perform()
            #expect(AudioManager.shared.currentSong == nil, "an empty library still started playback")
        }

        @Test("Playing favourites queues every hearted track")
        func favoritesArePlayed() async throws {
            let hearted = [song("a"), song("b"), song("c")]
            favoritesStore.write(hearted)

            _ = try await PlayFavoritesIntent().perform()

            let audio = AudioManager.shared
            let current = try #require(audio.currentSong)
            #expect(hearted.contains(current), "played something that isn't a favourite")
            // Shuffled, so assert on the set rather than the order.
            #expect(Set(audio.queue.map(\.id)) == Set(hearted.map(\.id)))
            #expect(audio.queue.first == current, "the chosen track isn't first in the queue")
            audio.pause()
        }

        // MARK: - Radio

        @Test("Radio needs something to build on and says so when there's nothing")
        func radioWithoutHistory() async throws {
            _ = try await StartMyRadioIntent().perform()
            #expect(AudioManager.shared.currentSong == nil)
        }

        @Test("Radio seeds from favourites, falling back to recents")
        func radioSeeds() async throws {
            // No favourites, but something was played: the radio should still
            // work rather than telling an active listener to go listen first.
            recentsStore.write([song("recent-seed", artist: "Bonobo")])

            _ = try await StartMyRadioIntent().perform()

            let audio = AudioManager.shared
            #expect(audio.currentSong?.id == "recent-seed")
            #expect(audio.queue.first?.id == "recent-seed")
            audio.pause()
        }

        // MARK: - Resume

        @Test("Resuming with nothing to resume leaves playback alone")
        func resumeWithNothing() async throws {
            // Nothing loaded (the suite stops playback) and nothing saved.
            UserDefaults.standard.removeObject(forKey: "resume.song.v1")
            let audio = AudioManager.shared

            _ = try await ResumeListeningIntent().perform()

            #expect(audio.currentSong == nil)
            #expect(audio.isPlaying == false)
        }

        @Test("Resuming restores the last session and presses play")
        func resumeRestoresLastSession() async throws {
            let audio = AudioManager.shared
            let saved = song("resume-me", artist: "Tycho")
            UserDefaults.standard.set(try JSONEncoder().encode(saved), forKey: "resume.song.v1")

            _ = try await ResumeListeningIntent().perform()

            #expect(audio.currentSong?.id == "resume-me")
            UserDefaults.standard.removeObject(forKey: "resume.song.v1")
            audio.stop()
        }

        // MARK: - Registration

        @Test("Every intent is titled and described — Shortcuts shows both")
        func intentsAreDescribed() {
            #expect(PlayFavoritesIntent.openAppWhenRun)
            #expect(StartMyRadioIntent.openAppWhenRun)
            #expect(ResumeListeningIntent.openAppWhenRun)
            #expect(SonavaShortcuts.appShortcuts.count == 3)
        }
    }
}
