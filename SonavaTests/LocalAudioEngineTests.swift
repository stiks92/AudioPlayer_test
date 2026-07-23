//
//  LocalAudioEngineTests.swift
//  SonavaTests
//
//  Exercises the real AVAudioEngine graph — player → EQ → timePitch → mixer —
//  against a generated file, so a broken connection or a bad band configuration
//  surfaces here rather than as silence on a device.
//

import Testing
import Foundation
@testable import Sonava

@MainActor
@Suite(.serialized)
struct LocalAudioEngineTests {

    @Test("Preparing a real file connects the graph and reads its duration")
    func prepareReportsDuration() throws {
        let file = try TestAudioFile.makeTone(named: "engine.m4a", seconds: 2.0)
        defer { TestAudioFile.cleanUp(file) }

        let engine = LocalAudioEngine()
        defer { engine.teardown() }

        #expect(engine.prepare(url: file, isLive: false, autoplay: false))
        #expect(engine.isLive == false)
        #expect(abs(engine.duration - 2.0) < 0.2, "duration \(engine.duration) is not ~2s")
        #expect(engine.isPlaying == false)
    }

    @Test("A missing file fails cleanly instead of throwing out of prepare")
    func missingFileFailsGracefully() {
        let engine = LocalAudioEngine()
        defer { engine.teardown() }
        let ghost = FileManager.default.temporaryDirectory.appendingPathComponent("nope.m4a")

        #expect(engine.prepare(url: ghost, isLive: false, autoplay: false) == false)
    }

    @Test("Play then pause flips the playing flag")
    func playPause() throws {
        let file = try TestAudioFile.makeTone(named: "pp.m4a", seconds: 2.0)
        defer { TestAudioFile.cleanUp(file) }

        let engine = LocalAudioEngine()
        defer { engine.teardown() }
        _ = engine.prepare(url: file, isLive: false, autoplay: true)

        #expect(engine.isPlaying)
        engine.pause()
        #expect(engine.isPlaying == false)
    }

    @Test("Applying an EQ curve to a live graph does not crash")
    func applyEqualizerIsSafe() throws {
        let file = try TestAudioFile.makeTone(named: "eq-live.m4a", seconds: 1.0)
        defer { TestAudioFile.cleanUp(file) }

        let engine = LocalAudioEngine()
        defer { engine.teardown() }
        _ = engine.prepare(url: file, isLive: false, autoplay: false)

        var settings = EqualizerSettings()
        settings.apply(.bassBoost)
        settings.isEnabled = true
        engine.apply(settings)          // enabled

        settings.isEnabled = false
        engine.apply(settings)          // bypassed

        // The real assertion is that neither call trapped the audio unit.
        #expect(engine.duration > 0)
    }

    @Test("Seeking past the end clamps instead of trapping")
    func seekClamps() throws {
        let file = try TestAudioFile.makeTone(named: "seek.m4a", seconds: 2.0)
        defer { TestAudioFile.cleanUp(file) }

        let engine = LocalAudioEngine()
        defer { engine.teardown() }
        _ = engine.prepare(url: file, isLive: false, autoplay: false)

        engine.seek(to: 999)
        #expect(engine.currentTime <= engine.duration + 0.01)
        engine.seek(to: -5)
        #expect(engine.currentTime >= 0)
    }

    @Test("Playing a file for real runs the metering tap without trapping")
    func sustainedPlaybackDrivesMetering() async throws {
        let file = try TestAudioFile.makeTone(named: "play.m4a", seconds: 2.0)
        defer { TestAudioFile.cleanUp(file) }

        let engine = LocalAudioEngine()
        defer { engine.teardown() }
        #expect(engine.prepare(url: file, isLive: false, autoplay: true))

        // Let the realtime render thread actually run. The metering tap fires
        // there; a main-actor-isolated tap closure would trap Swift 6's
        // executor check the moment audio flows — this is the regression guard.
        try? await Task.sleep(for: .milliseconds(300))

        engine.refresh()
        #expect(engine.currentTime > 0, "playback did not advance")
        #expect(engine.isPlaying)
    }

    @Test("Podcast speed is clamped to a sane range")
    func rateIsClamped() throws {
        let file = try TestAudioFile.makeTone(named: "rate.m4a", seconds: 1.0)
        defer { TestAudioFile.cleanUp(file) }

        let engine = LocalAudioEngine()
        defer { engine.teardown() }
        _ = engine.prepare(url: file, isLive: false, autoplay: false)

        // Out-of-range values must not reach AVAudioUnitTimePitch, which traps.
        engine.setRate(10)
        engine.setRate(0.01)
        #expect(engine.duration > 0)
    }
}
