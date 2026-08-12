//
//  CrateMixPlanner.swift
//  Sonava
//
//  Stage 3 of the Backroom, part one: the queue planner.
//
//  The assassin's condition was blunt: without tempo-stretch (patent-frozen
//  until 2027-07-10), a random queue almost never contains mixable adjacent
//  pairs — so the planner IS the feature. It reorders a party queue so that
//  neighbours are close in tempo and compatible in key, which is what a
//  human selector does with a crate before touching a fader.
//
//  Method:
//  * Key compatibility is the Camelot wheel (harmonic mixing's standard
//    notation of the circle of fifths): same slot, the relative
//    major/minor, or one step around the circle in the same mode.
//  * Tempo bands, honest about the no-stretch constraint: within 0.5% a
//    long beat-matched overlap stays tight for 16 beats; within 2% a short
//    4-beat overlap works; beyond that the transition falls back to a
//    plain fade and the planner says so.
//  * Route: greedy nearest-neighbour from the anchor track. Optimal TSP is
//    NP-hard and inaudible; greedy is what a DJ's instinct approximates.
//  * Tracks without passports cannot be planned — they sink to the end in
//    their original order rather than being guessed about.
//
//  Nothing here touches audio. It reads passports and returns an order
//  with per-transition annotations; the engine work (dual players, aligned
//  overlaps) is the second half of the stage.
//

import Foundation

enum CrateMix {

    /// How the engine may join two neighbours, given no tempo conversion.
    enum Transition: String, Equatable, Sendable {
        /// ≤0.5% apart: long overlap, downbeat-aligned, stays tight.
        case beatMatched
        /// ≤2% apart: short 4-beat overlap on the downbeat.
        case shortBlend
        /// Anything else: an ordinary crossfade, honestly unsynced.
        case plainFade
    }

    struct PlannedStep: Equatable, Sendable {
        var song: Song
        /// How this song is entered FROM the previous one; nil for the first.
        var transition: Transition?
        /// 0…1, higher is smoother — drives the UI chip.
        var quality: Double
    }

    // MARK: - Key distance (Camelot wheel)

    /// Camelot number 1…12 for a pitch class + mode. Minor keys are the "A"
    /// ring, majors the "B" ring; +1 slot = up a perfect fifth. 8B = C major,
    /// 8A = A minor, so a relative pair shares its number across rings.
    ///
    /// Moving up a fifth adds 7 semitones, so the slot index is the number
    /// of fifths from the reference: 7·x ≡ Δ (mod 12) → x ≡ 7·Δ (mod 12),
    /// because 7 is its own inverse mod 12.
    static func camelot(tonic: Int, isMinor: Bool) -> Int {
        let reference = isMinor ? 9 : 0            // A minor / C major
        let delta = ((tonic - reference) % 12 + 12) % 12
        let fifths = (7 * delta) % 12
        return (8 + fifths - 1) % 12 + 1
    }

    /// 0 = perfect (same slot or relative), 1 = one step on the wheel,
    /// 2 = anything else.
    static func keyDistance(_ a: MusicalKey, _ b: MusicalKey) -> Int {
        let slotA = camelot(tonic: a.tonic, isMinor: a.isMinor)
        let slotB = camelot(tonic: b.tonic, isMinor: b.isMinor)
        if slotA == slotB { return 0 }                      // same or relative
        if a.isMinor == b.isMinor {
            let around = min(abs(slotA - slotB), 12 - abs(slotA - slotB))
            if around == 1 { return 1 }                     // neighbour fifths
        }
        return 2
    }

    // MARK: - Tempo

    /// Relative tempo distance of the folded BPMs — the octave fold in the
    /// passport means 85 and 170 already compare as equals.
    static func tempoRatioDistance(_ a: Double, _ b: Double) -> Double {
        guard a > 0, b > 0 else { return 1 }
        return abs(a / b - 1)
    }

    static func transition(bpmA: Double?, bpmB: Double?, keyA: MusicalKey?, keyB: MusicalKey?) -> (Transition, Double) {
        guard let bpmA, let bpmB else { return (.plainFade, 0.2) }
        let tempoDistance = tempoRatioDistance(bpmA, bpmB)
        let keyPenalty: Double
        switch (keyA, keyB) {
        case let (a?, b?): keyPenalty = Double(keyDistance(a, b)) / 2   // 0, 0.5, 1
        default: keyPenalty = 0.5
        }
        if tempoDistance <= 0.005 {
            return (.beatMatched, max(0, 1 - keyPenalty * 0.4))
        }
        if tempoDistance <= 0.02 {
            return (.shortBlend, max(0, 0.75 - keyPenalty * 0.35))
        }
        return (.plainFade, max(0.05, 0.45 - tempoDistance - keyPenalty * 0.2))
    }

    // MARK: - The route

    /// Reorders `songs` (after the fixed `anchor`, usually the playing
    /// track) into the smoothest greedy path. Songs without passports keep
    /// their relative order at the tail.
    static func plan(anchor: Song?, songs: [Song],
                     passport: (Song) -> TrackPassport?) -> [PlannedStep] {
        var plannable: [(song: Song, passport: TrackPassport)] = []
        var tail: [Song] = []
        for song in songs {
            if let p = passport(song), p.bpm != nil {
                plannable.append((song, p))
            } else {
                tail.append(song)
            }
        }

        var steps: [PlannedStep] = []
        var currentBPM: Double?
        var currentKey: MusicalKey?
        if let anchor, let anchorPassport = passport(anchor) {
            currentBPM = anchorPassport.bpm
            currentKey = anchorPassport.musicalKey
        }

        var remaining = plannable
        while !remaining.isEmpty {
            let scored = remaining.enumerated().map { index, candidate -> (Int, Transition, Double) in
                let (kind, quality) = transition(
                    bpmA: currentBPM, bpmB: candidate.passport.bpm,
                    keyA: currentKey, keyB: candidate.passport.musicalKey)
                return (index, kind, quality)
            }
            // Highest quality wins; ties resolve to the earlier original
            // position so the plan is deterministic.
            let best = scored.max { a, b in
                a.2 == b.2 ? a.0 > b.0 : a.2 < b.2
            }!
            let chosen = remaining.remove(at: best.0)
            steps.append(PlannedStep(
                song: chosen.song,
                transition: (steps.isEmpty && currentBPM == nil) ? nil : best.1,
                quality: best.2))
            currentBPM = chosen.passport.bpm
            currentKey = chosen.passport.musicalKey
        }

        for song in tail {
            steps.append(PlannedStep(song: song,
                                     transition: steps.isEmpty ? nil : .plainFade,
                                     quality: 0.1))
        }
        return steps
    }
}
