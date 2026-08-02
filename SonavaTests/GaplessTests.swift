//
//  GaplessTests.swift
//  SonavaTests
//
//  Gapless playback is the credibility gate this app was failing: seven of
//  twelve competitors advertise it, and one of them collects explicit
//  "no gapless playback is a dealbreaker" reviews for lacking it. For a
//  player whose whole premise is the record as a unit, inserting half a
//  second of silence between the two halves of a segue is a contradiction of
//  the pitch.
//
//  What can be tested without ears: that the engine accepts a compatible
//  next track and refuses an incompatible one, that a stop invalidates what
//  was queued, and that the position clock reports the *new* track's time
//  rather than continuing the old one's — the bug that a naive implementation
//  ships with, because the node's own clock runs straight through the join.
//

import Testing
import Foundation
import AVFoundation
@testable import Sonava

@MainActor
struct GaplessTests {

    @Test("A matching next track is accepted for a seamless join")
    func acceptsMatchingFormat() throws {
        let first = try TestAudioFile.makeTone(named: "a.m4a", seconds: 0.6)
        let second = try TestAudioFile.makeTone(named: "b.m4a", seconds: 0.6)
        defer { TestAudioFile.cleanUp(first); TestAudioFile.cleanUp(second) }

        let engine = LocalAudioEngine()
        defer { engine.teardown() }
        #expect(engine.prepare(url: first, isLive: false, autoplay: false))
        #expect(engine.preloadNext(url: second), "same format — this must join")
    }

    @Test("A next track in another format is refused rather than played wrong")
    func refusesFormatChange() throws {
        let first = try TestAudioFile.makeTone(named: "a.m4a", seconds: 0.6)
        let other = try TestAudioFile.makeToneAtOtherFormat(named: "b.m4a", seconds: 0.4)
        defer { TestAudioFile.cleanUp(first); TestAudioFile.cleanUp(other) }

        let engine = LocalAudioEngine()
        defer { engine.teardown() }
        engine.prepare(url: first, isLive: false, autoplay: false)
        #expect(engine.preloadNext(url: other) == false,
                "the node renders one format; a rate change must fall back to a normal load")
    }

    @Test("Nothing is queued before a track is loaded")
    func refusesWithoutCurrentTrack() throws {
        let track = try TestAudioFile.makeTone(named: "a.m4a", seconds: 0.4)
        defer { TestAudioFile.cleanUp(track) }
        let engine = LocalAudioEngine()
        #expect(engine.preloadNext(url: track) == false)
    }

    @Test("Only one track is queued at a time")
    func queuesOnlyOne() throws {
        let first = try TestAudioFile.makeTone(named: "a.m4a", seconds: 0.6)
        let second = try TestAudioFile.makeTone(named: "b.m4a", seconds: 0.6)
        let third = try TestAudioFile.makeTone(named: "c.m4a", seconds: 0.6)
        defer { [first, second, third].forEach(TestAudioFile.cleanUp) }

        let engine = LocalAudioEngine()
        defer { engine.teardown() }
        engine.prepare(url: first, isLive: false, autoplay: false)
        #expect(engine.preloadNext(url: second))
        #expect(engine.preloadNext(url: third) == false,
                "queueing two deep would commit to an order the listener can still change")
    }

    @Test("A missing file is refused, not crashed on")
    func refusesMissingFile() throws {
        let first = try TestAudioFile.makeTone(named: "a.m4a", seconds: 0.4)
        defer { TestAudioFile.cleanUp(first) }
        let engine = LocalAudioEngine()
        defer { engine.teardown() }
        engine.prepare(url: first, isLive: false, autoplay: false)

        let ghost = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-here-\(UUID().uuidString).m4a")
        #expect(engine.preloadNext(url: ghost) == false)
    }

    @Test("Cancelling lets something else be queued")
    func cancelFreesTheSlot() throws {
        let first = try TestAudioFile.makeTone(named: "a.m4a", seconds: 0.6)
        let second = try TestAudioFile.makeTone(named: "b.m4a", seconds: 0.6)
        let third = try TestAudioFile.makeTone(named: "c.m4a", seconds: 0.6)
        defer { [first, second, third].forEach(TestAudioFile.cleanUp) }

        let engine = LocalAudioEngine()
        defer { engine.teardown() }
        engine.prepare(url: first, isLive: false, autoplay: false)
        #expect(engine.preloadNext(url: second))
        engine.cancelPreload()
        #expect(engine.preloadNext(url: third), "a reordered queue must be able to re-queue")
    }

    @Test("Seeking drops what was queued")
    func seekClearsTheQueue() throws {
        let first = try TestAudioFile.makeTone(named: "a.m4a", seconds: 1.0)
        let second = try TestAudioFile.makeTone(named: "b.m4a", seconds: 0.6)
        let third = try TestAudioFile.makeTone(named: "c.m4a", seconds: 0.6)
        defer { [first, second, third].forEach(TestAudioFile.cleanUp) }

        let engine = LocalAudioEngine()
        defer { engine.teardown() }
        engine.prepare(url: first, isLive: false, autoplay: false)
        engine.preloadNext(url: second)
        engine.seek(to: 0.2)
        // The seek restarted the schedule, so the slot is free again — and
        // must be, or the listener would hear the *old* next track after
        // scrubbing.
        #expect(engine.preloadNext(url: third))
    }

    @Test("Playing a gapless pair reports the new track's own position")
    func positionResetsAcrossTheJoin() async throws {
        // The node's clock runs straight through queued segments, so a naive
        // implementation shows the second track starting at the first one's
        // duration. Half a second of tone each keeps this quick.
        let first = try TestAudioFile.makeTone(named: "a.m4a", seconds: 0.5)
        let second = try TestAudioFile.makeTone(named: "b.m4a", seconds: 0.9)
        defer { TestAudioFile.cleanUp(first); TestAudioFile.cleanUp(second) }

        let engine = LocalAudioEngine()
        defer { engine.teardown() }
        // Sampled *inside* the hand-off. A first version polled and then read
        // the clock, which measured the test runner's scheduling latency as
        // much as the engine — under parallel load the poll landed half a
        // second late and the assertion failed on a mechanism that was right.
        var timeAtJoin: Double?
        var durationAtJoin: Double?
        engine.onAdvancedToNext = { [weak engine] in
            timeAtJoin = engine?.currentTime
            durationAtJoin = engine?.duration
        }
        engine.prepare(url: first, isLive: false, autoplay: true)
        engine.preloadNext(url: second)

        for _ in 0..<60 where timeAtJoin == nil {
            try? await Task.sleep(for: .milliseconds(25))
        }
        let joined = try #require(timeAtJoin, "the engine must report the hand-off it performed")
        #expect(joined < 0.3,
                "position must restart with the new track, not continue the old one's clock")
        #expect(abs((durationAtJoin ?? 0) - 0.9) < 0.2, "duration follows the new track")
    }
}
