//
//  ProGateMatrixTests.swift
//  SonavaTests
//
//  The free/Pro matrix for the gates the paid zone gained in 2026-08:
//  Crate Mix and headphone correction. Same style as the palette, icon,
//  stats-range and server assertions — the machine-readable table of what
//  is free, so moving a line is a decision and never an accident.
//
//  Both features follow the anti-confiscation rule the servers set: a lapse
//  locks the door, it never deletes what is behind it.
//

import Testing
import Foundation
@testable import Sonava

@MainActor
struct CrateMixGateTests {

    private func song(_ id: String) -> Song {
        Song(id: "crate-gate-\(id)", title: "Track \(id)", artist: "Artist", album: "Album",
             source: .audius, gradientHex: Palette.hex(forSeed: id))
    }

    @Test("Crate Mix is Pro: free cannot activate, a lapse unwinds the plan but keeps the queue")
    func crateMixMatrix() {
        let audio = AudioManager.shared
        audio.stop()   // the singleton inherits whatever the last test queued
        audio.setQueueForTesting([song("a"), song("b"), song("c")])

        audio.isPro = false
        audio.toggleCrateMix()
        #expect(!audio.isCrateMixActive, "a free listener activated Crate Mix")
        #expect(audio.queue.count == 3, "the refused gate touched the queue")

        audio.isPro = true
        audio.toggleCrateMix()
        #expect(audio.isCrateMixActive, "a Pro listener could not activate Crate Mix")

        // The lapse: access locks, data stays.
        audio.isPro = false
        #expect(!audio.isCrateMixActive, "a lapse left the Pro planner running")
        #expect(audio.crateMixTransitions.isEmpty, "a lapse left the plan's chips behind")
        #expect(audio.queue.count == 3, "a lapse deleted queue entries — that is confiscation")

        audio.stop()   // leave the singleton the way the intents tests expect it
    }

    @Test("Switching an active mix off is never gated — locking the exit would be confiscation")
    func deactivationStaysFree() {
        let audio = AudioManager.shared
        audio.stop()
        audio.setQueueForTesting([song("x"), song("y")])

        audio.isPro = true
        audio.toggleCrateMix()
        #expect(audio.isCrateMixActive)

        // Keep Pro, toggle off: plain deactivation works…
        audio.toggleCrateMix()
        #expect(!audio.isCrateMixActive)

        audio.isPro = false
        audio.stop()
    }
}

@MainActor
struct CorrectionGateTests {

    private let filename = "correction-gate-test.json"
    private let tiltFilename = "correction-gate-test-tilt.json"

    private func fresh() -> CorrectionStore {
        // Store files outlive runs and suites run in parallel, so this test
        // writes its own files under its own names first — the tilt file
        // included, or another suite's voicing would leak into the matrix.
        JSONFileStore<CorrectionProfile?>(filename, default: nil).write(nil)
        JSONFileStore<VoicingTilt>(tiltFilename, default: VoicingTilt()).write(VoicingTilt())
        return CorrectionStore(filename: filename, tiltFilename: tiltFilename)
    }

    private var profile: CorrectionProfile {
        CorrectionProfile(name: "HD 650", preampDB: -6.4, bands: [
            CorrectionBand(kind: .peaking, frequency: 105, gainDB: -2.4, q: 0.7)
        ])
    }

    @Test("Headphone correction is Pro: the profile is only effective while Pro")
    func correctionMatrix() {
        let store = fresh()
        store.install(profile)

        store.isPro = false
        #expect(store.effectiveProfile == nil, "a free listener's engine received the correction")

        store.isPro = true
        #expect(store.effectiveProfile == profile, "a Pro listener's correction was withheld")
    }

    @Test("A lapse withholds the correction but never deletes the installed profile")
    func lapseKeepsTheProfile() {
        let store = fresh()
        store.isPro = true
        store.install(profile)
        #expect(store.effectiveProfile != nil)

        store.isPro = false
        #expect(store.effectiveProfile == nil, "the lapse did not lock the gate")
        #expect(store.profile == profile,
                "the lapse deleted the listener's own imported profile — that is confiscation")

        // And Pro returning finds everything where it was left.
        store.isPro = true
        #expect(store.effectiveProfile == profile)
    }

    @Test("The voicing tilt rides the same Pro gate as the profile")
    func voicingIsGated() {
        let store = fresh()
        store.setTilt(VoicingPreset.deep.tilt)

        store.isPro = false
        #expect(store.effectiveProfile == nil, "a free listener's engine received the voicing")

        store.isPro = true
        #expect(store.effectiveProfile?.bands == VoicingPreset.deep.tilt.bands,
                "a Pro listener's voicing was withheld")

        // The lapse keeps the tilt on disk, exactly like the profile.
        store.isPro = false
        #expect(store.tilt == VoicingPreset.deep.tilt,
                "a lapse reset the listener's voicing — that is confiscation")
    }
}
