//
//  CrateMixTests.swift
//  SonavaTests
//
//  The queue planner's arithmetic. Camelot slots are checked against the
//  published wheel (any DJ chart is ground truth); the route tests encode
//  what a human selector would do with the same crate.
//

import Foundation
import Testing
@testable import Sonava

struct CrateMixTests {

    // MARK: - Camelot wheel

    @Test func camelotMatchesThePublishedWheel() {
        // Majors (B ring): C=8, G=9, D=10, F=7, B♭=6.
        #expect(CrateMix.camelot(tonic: 0, isMinor: false) == 8)
        #expect(CrateMix.camelot(tonic: 7, isMinor: false) == 9)
        #expect(CrateMix.camelot(tonic: 2, isMinor: false) == 10)
        #expect(CrateMix.camelot(tonic: 5, isMinor: false) == 7)
        #expect(CrateMix.camelot(tonic: 10, isMinor: false) == 6)
        // Minors (A ring): Am=8, Em=9, Dm=7, F♯m=11.
        #expect(CrateMix.camelot(tonic: 9, isMinor: true) == 8)
        #expect(CrateMix.camelot(tonic: 4, isMinor: true) == 9)
        #expect(CrateMix.camelot(tonic: 2, isMinor: true) == 7)
        #expect(CrateMix.camelot(tonic: 6, isMinor: true) == 11)
    }

    private func key(_ tonic: Int, minor: Bool) -> MusicalKey {
        MusicalKey(tonic: tonic, isMinor: minor, confidence: 1)
    }

    @Test func relativeKeysArePerfectNeighboursAreClose() {
        // C major ↔ A minor: relative pair, distance 0.
        #expect(CrateMix.keyDistance(key(0, minor: false), key(9, minor: true)) == 0)
        // C major ↔ G major: one fifth, distance 1.
        #expect(CrateMix.keyDistance(key(0, minor: false), key(7, minor: false)) == 1)
        // C major ↔ F♯ major: tritone, the wheel's far side.
        #expect(CrateMix.keyDistance(key(0, minor: false), key(6, minor: false)) == 2)
    }

    // MARK: - Transition bands

    @Test func transitionBandsFollowTheNoStretchTruth() {
        let c = key(0, minor: false)
        // 124.0 vs 124.4 → 0.3%: long beat-matched overlap.
        #expect(CrateMix.transition(bpmA: 124, bpmB: 124.4, keyA: c, keyB: c).0 == .beatMatched)
        // 124 vs 126 → 1.6%: short blend only.
        #expect(CrateMix.transition(bpmA: 124, bpmB: 126, keyA: c, keyB: c).0 == .shortBlend)
        // 124 vs 140 → 13%: an honest plain fade.
        #expect(CrateMix.transition(bpmA: 124, bpmB: 140, keyA: c, keyB: c).0 == .plainFade)
        // No tempo data at all: never pretend.
        #expect(CrateMix.transition(bpmA: nil, bpmB: 124, keyA: nil, keyB: nil).0 == .plainFade)
    }

    // MARK: - The route

    private func song(_ id: String) -> Song {
        Song(id: id, title: id, artist: "A", album: "L", gradientHex: [0, 1])
    }

    private func passport(bpm: Double?, tonic: Int? = nil, minor: Bool = false) -> TrackPassport {
        TrackPassport(contentKey: "k", durationSeconds: 200,
                      loudnessLUFS: nil, bpm: bpm, bpmConfidence: bpm == nil ? nil : 0.9,
                      beatGrid: nil,
                      musicalKey: tonic.map { MusicalKey(tonic: $0, isMinor: minor, confidence: 0.6) },
                      analyzedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func plannerWalksTheSmoothestPath() {
        // Anchor at 124 C-major. Crate: 140 (far), 124.2 (twin), 126 (near).
        let songs = [song("far140"), song("twin124"), song("near126")]
        let passports: [String: TrackPassport] = [
            "far140": passport(bpm: 140, tonic: 0),
            "twin124": passport(bpm: 124.2, tonic: 9, minor: true),   // relative key too
            "near126": passport(bpm: 126, tonic: 0),
        ]
        let steps = CrateMix.plan(anchor: song("anchor"), songs: songs) { s in
            s.id == "anchor" ? passport(bpm: 124, tonic: 0) : passports[s.id]
        }
        #expect(steps.map(\.song.id) == ["twin124", "near126", "far140"],
                "greedy path: twin first, near second, far last — got \(steps.map(\.song.id))")
        #expect(steps[0].transition == .beatMatched)
        #expect(steps[1].transition == .shortBlend)
    }

    @Test func passportlessTracksSinkToTheTailInOrder() {
        let songs = [song("unscanned1"), song("scanned"), song("unscanned2")]
        let steps = CrateMix.plan(anchor: nil, songs: songs) { s in
            s.id == "scanned" ? passport(bpm: 120, tonic: 0) : nil
        }
        #expect(steps.map(\.song.id) == ["scanned", "unscanned1", "unscanned2"],
                "unplannable tracks keep their own order at the end, never guessed about")
    }

    // MARK: - Overlap arithmetic

    private func gridPassport(bpm: Double, first: Double, duration _: Double,
                              sections: [Double]? = nil) -> TrackPassport {
        TrackPassport(contentKey: "k", durationSeconds: 0, loudnessLUFS: nil,
                      bpm: bpm, bpmConfidence: 0.9,
                      beatGrid: BeatGrid(firstBeatOffset: first, interval: 60.0 / bpm, confidence: 0.8),
                      musicalKey: nil, sectionBounds: sections,
                      analyzedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func overlapStartsOnTheGridAtTheLastUsableSection() {
        let outgoing = gridPassport(bpm: 120, first: 0.25, duration: 240,
                                    sections: [60, 120, 200, 232])
        let incoming = gridPassport(bpm: 120.3, first: 0.4, duration: 200)
        let plan = CrateMix.overlapPlan(outgoing: outgoing, incoming: incoming,
                                        outgoingDuration: 240, transition: .beatMatched)
        #expect(plan != nil)
        guard let plan else { return }
        // 16 beats at 120 BPM = 8 s of fade.
        #expect(abs(plan.fadeDuration - 8.0) < 1e-9)
        // The 232 s boundary leaves no room (232+8.4 > 240); 200 s does.
        // Beats fall at 0.25+k·0.5 — the boundary at 200 sits between
        // 199.75 and 200.25, and the plan snaps DOWN: arriving on the beat
        // just BEFORE a section change is musical; overshooting it is not.
        #expect(abs(plan.startInOutgoing - 199.75) < 1e-9,
                "snap to the beat instant at/below the 200 s boundary, got \(plan.startInOutgoing)")
        // Exactly on the outgoing grid.
        let phase = (plan.startInOutgoing - 0.25) / 0.5
        #expect(abs(phase - phase.rounded()) < 1e-9)
        // The incoming enters at its own first beat.
        #expect(plan.incomingOffset == 0.4)
    }

    @Test func overlapWithoutSectionsLeavesRoomBeforeTheEnd() {
        let outgoing = gridPassport(bpm: 124, first: 0.1, duration: 180)
        let incoming = gridPassport(bpm: 124, first: 0.0, duration: 200)
        let plan = CrateMix.overlapPlan(outgoing: outgoing, incoming: incoming,
                                        outgoingDuration: 180, transition: .shortBlend)
        #expect(plan != nil)
        guard let plan else { return }
        #expect(plan.startInOutgoing + plan.fadeDuration <= 180 - 0.4 + 1e-9,
                "the fade must finish before the file's final samples")
    }

    @Test func noGridMeansNoOverlapPlan() {
        let gridless = TrackPassport(contentKey: "k", durationSeconds: 200,
                                     analyzedAt: Date(timeIntervalSince1970: 0))
        let incoming = gridPassport(bpm: 120, first: 0, duration: 200)
        #expect(CrateMix.overlapPlan(outgoing: gridless, incoming: incoming,
                                     outgoingDuration: 200, transition: .beatMatched) == nil,
                "an unmeasured ending cannot be aligned to, only faded from")
    }

    @Test func planIsDeterministic() {
        let songs = (0..<8).map { song("s\($0)") }
        let table: [String: TrackPassport] = Dictionary(uniqueKeysWithValues:
            songs.enumerated().map { ($1.id, passport(bpm: 118 + Double($0), tonic: $0 % 12)) })
        let a = CrateMix.plan(anchor: nil, songs: songs) { table[$0.id] }
        let b = CrateMix.plan(anchor: nil, songs: songs.reversed()) { table[$0.id] }
        #expect(a.map(\.song.id).sorted() == b.map(\.song.id).sorted())
        let c = CrateMix.plan(anchor: nil, songs: songs) { table[$0.id] }
        #expect(a.map(\.song.id) == c.map(\.song.id), "same crate, same plan, every time")
    }
}

/// The crossing, live: a real engine, two real files, the roles swapping.
/// Same regime as GaplessTests — sampled in callbacks and asserted on
/// invariants between snapshots, never against the wall clock.
struct OverlapEngineTests {

    @Test @MainActor func overlapAdvancesAndSwapsTheClock() async throws {
        let first = try TestAudioFile.makeTone(named: "out.m4a", seconds: 3.0)
        let second = try TestAudioFile.makeTone(named: "in.m4a", seconds: 3.0)
        defer { TestAudioFile.cleanUp(first); TestAudioFile.cleanUp(second) }

        let engine = LocalAudioEngine()
        defer { engine.teardown() }

        var advancedDuration: Double?
        var advancedTime: Double?
        var finishedTooEarly = false
        engine.onAdvancedToNext = { [weak engine] in
            advancedDuration = engine?.duration
            advancedTime = engine?.currentTime
        }
        engine.onFinish = { if advancedDuration == nil { finishedTooEarly = true } }

        engine.prepare(url: first, isLive: false, autoplay: true)
        let accepted = engine.scheduleOverlap(.init(
            url: second, startInOutgoing: 1.2, incomingOffset: 0.2, fadeDuration: 0.8))
        #expect(accepted, "a mid-track overlap 1.2 s out must be schedulable")
        #expect(engine.hasScheduledOverlap)

        for _ in 0..<200 where advancedDuration == nil {   // up to 5 s of slack
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(advancedDuration != nil, "the crossing must hand the app its advance")
        #expect(!finishedTooEarly, "the outgoing end must not masquerade as a finish")
        if let advancedDuration {
            #expect(abs(advancedDuration - 3.0) < 0.3, "duration follows the incoming track")
        }
        if let advancedTime {
            // Sampled inside the callback: the new clock begins at the
            // incoming offset, not at the outgoing track's elapsed time.
            #expect(advancedTime >= 0.1 && advancedTime < 1.0,
                    "incoming clock starts near its 0.2 s offset, got \(advancedTime)")
        }

        // After the crossing the position lives inside the new track's own
        // clock — the same latency-immune invariant the gapless test keeps.
        var worstOverrun = -Double.infinity
        for _ in 0..<80 {
            try? await Task.sleep(for: .milliseconds(25))
            worstOverrun = max(worstOverrun, engine.currentTime - engine.duration)
            if !engine.isPlaying { break }
        }
        #expect(worstOverrun < 0.35, "position must never overrun the incoming duration")
    }

    @Test @MainActor func tooCloseAMomentIsRefusedNotBotched() throws {
        let first = try TestAudioFile.makeTone(named: "out.m4a", seconds: 1.0)
        let second = try TestAudioFile.makeTone(named: "in.m4a", seconds: 1.0)
        defer { TestAudioFile.cleanUp(first); TestAudioFile.cleanUp(second) }

        let engine = LocalAudioEngine()
        defer { engine.teardown() }
        engine.prepare(url: first, isLive: false, autoplay: true)
        // 0.05 s of lead is not enough to align anything.
        let accepted = engine.scheduleOverlap(.init(
            url: second, startInOutgoing: 0.05, incomingOffset: 0, fadeDuration: 0.5))
        #expect(!accepted, "an unschedulable overlap must refuse, so the caller can fall back")
        #expect(!engine.hasScheduledOverlap)
    }

    @Test @MainActor func pauseCancelsThePlannedCrossing() throws {
        let first = try TestAudioFile.makeTone(named: "out.m4a", seconds: 3.0)
        let second = try TestAudioFile.makeTone(named: "in.m4a", seconds: 3.0)
        defer { TestAudioFile.cleanUp(first); TestAudioFile.cleanUp(second) }

        let engine = LocalAudioEngine()
        defer { engine.teardown() }
        engine.prepare(url: first, isLive: false, autoplay: true)
        _ = engine.scheduleOverlap(.init(
            url: second, startInOutgoing: 2.0, incomingOffset: 0, fadeDuration: 0.5))
        engine.pause()
        #expect(!engine.hasScheduledOverlap,
                "a paused primary must not let the incoming start over silence")
    }
}
