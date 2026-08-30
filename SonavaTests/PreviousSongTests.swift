//
//  PreviousSongTests.swift
//  SonavaTests
//
//  `previousSong` is what the player's left-hand peek shows behind the lens,
//  and it must agree with what `previous()` would actually do — including the
//  wrap from the first track to the tail. A peek that promises one record and
//  a swipe that delivers another is worse than no peek.
//
//  Nested under LibrarySuite: it drives the shared `AudioManager` singleton,
//  and Swift Testing runs suites in parallel. The fixture songs deliberately
//  have no URL, so `load` sets the queue and current index and then stops —
//  no engine, no audio session, nothing for GaplessTests to fight over.
//

import Testing
import Foundation
@testable import Sonava

extension LibrarySuite {

    @MainActor
    @Suite(.serialized)
    struct PreviousSongTests {

        init() {
            // A singleton: a previous test's queue would otherwise be
            // mistaken for the state under test.
            AudioManager.shared.stop()
        }

        /// A song with no URL at all: `AudioManager.load` records it as
        /// current and returns before touching any engine.
        private func song(_ id: String) -> Song {
            Song(id: id, title: "Track \(id)", artist: "Artist", album: "Album",
                 source: .local, gradientHex: Palette.hex(for: 0))
        }

        @Test("An empty queue has no previous track")
        func emptyQueue() {
            let audio = AudioManager.shared
            audio.stop()
            #expect(audio.previousSong == nil)
        }

        @Test("From the first track, previous wraps to the tail of the queue")
        func firstTrackWraps() {
            let audio = AudioManager.shared
            let queue = [song("a"), song("b"), song("c")]
            audio.play(queue[0], in: queue)
            #expect(audio.previousSong?.id == "c",
                    "the peek must wrap exactly the way previous() steps")
            audio.stop()
        }

        @Test("Mid-queue, previous is simply the track before")
        func middleOfQueue() {
            let audio = AudioManager.shared
            let queue = [song("a"), song("b"), song("c")]
            audio.play(queue[1], in: queue)
            #expect(audio.previousSong?.id == "a")
            audio.stop()
        }

        @Test("A single-track queue wraps onto itself, like previous() does")
        func singleTrackQueue() {
            let audio = AudioManager.shared
            let only = song("solo")
            audio.play(only, in: [only])
            #expect(audio.previousSong?.id == "solo")
            audio.stop()
        }
    }
}
