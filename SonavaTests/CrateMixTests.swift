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
