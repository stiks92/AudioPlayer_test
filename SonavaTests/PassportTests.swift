//
//  PassportTests.swift
//  SonavaTests
//
//  The Backroom's stage-0 measurements, proven on synthesized signals with
//  known ground truth. This is the QA rig the consilium demanded: the gate
//  for analysis quality is arithmetic against signals we constructed, never
//  one person's ears on one evening.
//

import AVFoundation
import Foundation
import Testing
@testable import Sonava

struct PassportTests {

    // MARK: - Signal builders (ground truth by construction)

    /// A click track: 10 ms noise bursts at exact BPM over silence.
    private func clickTrack(bpm: Double, seconds: Double, offset: Double = 0,
                            rate: Double = PassportAnalyzer.workRate) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(seconds * rate))
        let interval = 60.0 / bpm * rate
        let burst = Int(0.01 * rate)
        var position = offset * rate
        var seed: UInt64 = 0x9E3779B97F4A7C15
        while Int(position) + burst < samples.count {
            for index in 0..<burst {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                let noise = Float(Int64(bitPattern: seed) % 1000) / 1000
                samples[Int(position) + index] = noise * 0.8
            }
            position += interval
        }
        return samples
    }

    /// A looping arpeggio of pure tones — an unambiguous key.
    private func arpeggio(midiNotes: [Int], seconds: Double,
                          rate: Double = PassportAnalyzer.workRate) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(seconds * rate))
        let noteLength = Int(0.25 * rate)
        for index in samples.indices {
            let note = midiNotes[(index / noteLength) % midiNotes.count]
            let frequency = 440 * pow(2, (Double(note) - 69) / 12)
            samples[index] = Float(0.5 * sin(2 * .pi * frequency * Double(index) / rate))
        }
        return samples
    }

    // MARK: - Tempo

    @Test func clickTrackAt120IsMeasuredAt120() {
        let flux = PassportAnalyzer.onsetEnvelope(samples: clickTrack(bpm: 120, seconds: 30))
        let tempo = PassportAnalyzer.tempoEstimate(flux: flux)
        #expect(tempo != nil)
        if let tempo { #expect(abs(tempo.bpm - 120) < 1.0, "got \(tempo.bpm)") }
    }

    @Test func clickTrackAt87StaysAt87NotItsOctave() {
        let flux = PassportAnalyzer.onsetEnvelope(samples: clickTrack(bpm: 87, seconds: 30))
        let tempo = PassportAnalyzer.tempoEstimate(flux: flux)
        #expect(tempo != nil)
        if let tempo { #expect(abs(tempo.bpm - 87) < 1.0, "got \(tempo.bpm) — octave folding must land in 80–160") }
    }

    @Test func slowTempoFoldsIntoTheCanonicalOctave() {
        // 70 BPM folds to 140: the grid is equally true at both, and the
        // canonical octave is what downstream comparisons rely on.
        let flux = PassportAnalyzer.onsetEnvelope(samples: clickTrack(bpm: 70, seconds: 30))
        let tempo = PassportAnalyzer.tempoEstimate(flux: flux)
        #expect(tempo != nil)
        if let tempo { #expect(abs(tempo.bpm - 140) < 1.5, "got \(tempo.bpm)") }
    }

    @Test func noiseGetsNoTempo() {
        var seed: UInt64 = 42
        let noise: [Float] = (0..<Int(PassportAnalyzer.workRate * 20)).map { _ in
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Float(Int64(bitPattern: seed) % 1000) / 2000
        }
        let flux = PassportAnalyzer.onsetEnvelope(samples: noise)
        let tempo = PassportAnalyzer.tempoEstimate(flux: flux)
        #expect(tempo == nil, "unpitched noise must not receive a confident BPM")
    }

    // MARK: - Beat grid

    @Test func gridFindsTheClickOffset() {
        let offset = 0.25
        let samples = clickTrack(bpm: 120, seconds: 30, offset: offset)
        let flux = PassportAnalyzer.onsetEnvelope(samples: samples)
        guard let tempo = PassportAnalyzer.tempoEstimate(flux: flux),
              let grid = PassportAnalyzer.beatGrid(flux: flux, bpm: tempo.bpm) else {
            Issue.record("expected tempo and grid on a clean click track")
            return
        }
        // The comb's phase is modulo one interval (0.5 s at 120 BPM).
        let phase = grid.firstBeatOffset.truncatingRemainder(dividingBy: grid.interval)
        let target = offset.truncatingRemainder(dividingBy: 60.0 / tempo.bpm)
        let distance = min(abs(phase - target), grid.interval - abs(phase - target))
        #expect(distance < 0.05, "grid phase \(phase) should sit at the click offset \(target)")
    }

    // MARK: - Key

    @Test func cMajorArpeggioReadsAsCMajor() {
        // C E G C — the least ambiguous statement of C major there is.
        let key = PassportAnalyzer.keyEstimate(samples: arpeggio(midiNotes: [60, 64, 67, 72], seconds: 20))
        #expect(key != nil)
        if let key {
            #expect(key.tonic == 0 && !key.isMinor, "got \(key.label)")
        }
    }

    @Test func aMinorArpeggioReadsAsAMinor() {
        let key = PassportAnalyzer.keyEstimate(samples: arpeggio(midiNotes: [57, 60, 64, 69], seconds: 20))
        #expect(key != nil)
        if let key {
            #expect(key.tonic == 9 && key.isMinor, "got \(key.label)")
        }
    }

    @Test func keyLabelsSpellLikeMusicians() {
        #expect(MusicalKey(tonic: 6, isMinor: true, confidence: 1).label == "F♯m")
        #expect(MusicalKey(tonic: 3, isMinor: false, confidence: 1).label == "E♭")
    }

    // MARK: - Sections

    @Test func boundaryIsFoundWhereTheArrangementTurns() {
        // 40 s of a C-major arpeggio, then 40 s of an F-minor one an octave
        // up: harmony, register and texture all change at exactly 40 s.
        let a = arpeggio(midiNotes: [48, 52, 55, 60], seconds: 40)
        let b = arpeggio(midiNotes: [65, 68, 72, 77], seconds: 40)
        let bounds = PassportAnalyzer.sectionBoundaries(samples: a + b)
        #expect(!bounds.isEmpty, "a hard section change must be reported")
        if let nearest = bounds.min(by: { abs($0 - 40) < abs($1 - 40) }) {
            #expect(abs(nearest - 40) <= 3, "boundary should sit at the 40 s turn, got \(bounds)")
        }
    }

    @Test func uniformMaterialReportsNoForest() {
        // One texture throughout: whatever is reported must be sparse —
        // an 80-second loop is not an eight-section suite.
        let uniform = arpeggio(midiNotes: [60, 64, 67, 72], seconds: 80)
        let bounds = PassportAnalyzer.sectionBoundaries(samples: uniform)
        #expect(bounds.count <= 2, "uniform material grew \(bounds.count) sections")
    }

    // MARK: - Content key

    @Test func contentKeyIsDeterministic() {
        let samples = arpeggio(midiNotes: [60, 64, 67], seconds: 5)
        #expect(PassportAnalyzer.contentKey(samples: samples) == PassportAnalyzer.contentKey(samples: samples))
    }

    @Test func contentKeySeparatesDifferentAudio() {
        let a = PassportAnalyzer.contentKey(samples: arpeggio(midiNotes: [60, 64, 67], seconds: 5))
        let b = PassportAnalyzer.contentKey(samples: arpeggio(midiNotes: [62, 65, 69], seconds: 5))
        #expect(a != b)
    }

    // MARK: - Store

    private func temporaryStore() -> PassportStore {
        PassportStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("passports-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func passportRoundTrips() {
        let store = temporaryStore()
        let passport = TrackPassport(
            contentKey: "abc", durationSeconds: 200, loudnessLUFS: -12.5,
            bpm: 124, bpmConfidence: 0.8,
            beatGrid: BeatGrid(firstBeatOffset: 0.31, interval: 0.4839, confidence: 0.7),
            musicalKey: MusicalKey(tonic: 6, isMinor: true, confidence: 0.4),
            analyzedAt: Date())
        store.save(passport, for: "local:song1")
        #expect(store.passport(for: "local:song1") == passport)
        #expect(store.passport(for: "local:other") == nil)
    }

    @Test func corruptPassportIsRemovedNotTrusted() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("passports-\(UUID().uuidString)", isDirectory: true)
        let store = PassportStore(directory: directory)
        store.save(TrackPassport(contentKey: "x", durationSeconds: 1, analyzedAt: Date()),
                   for: "local:song1")
        // Corrupt every file in the shelf.
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try Data("not json".utf8).write(to: file)
        }
        #expect(store.passport(for: "local:song1") == nil)
    }

    // MARK: - The whole pass, against a real file

    @Test func analyzeProducesAFullPassportFromAWAV() throws {
        // 30 s of 120 BPM clicks mixed over a quiet C-major pad, written as
        // a real file — the full decode → analyze path.
        let rate = 44_100.0
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("passport-\(UUID().uuidString).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        // Scoped writer: AVAudioFile finalises the WAV header on deinit, and
        // reading a file whose writer is still alive sees a zero-length
        // stream. The first version of this test did exactly that.
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let frames = Int(rate * 30)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
            buffer.frameLength = AVAudioFrameCount(frames)
            let interval = Int(60.0 / 120 * rate)
            for frame in 0..<frames {
                let pad = 0.08 * (sin(2 * .pi * 261.63 * Double(frame) / rate)
                                + sin(2 * .pi * 329.63 * Double(frame) / rate)
                                + sin(2 * .pi * 392.0 * Double(frame) / rate))
                let click: Double = (frame % interval) < Int(0.01 * rate) ? 0.6 : 0
                let sample = Float(pad + click)
                buffer.floatChannelData![0][frame] = sample
                buffer.floatChannelData![1][frame] = sample
            }
            try file.write(from: buffer)
        }
        defer { try? FileManager.default.removeItem(at: url) }

        let passport = PassportAnalyzer.analyze(url: url)
        #expect(passport != nil)
        if let passport {
            #expect(abs(passport.durationSeconds - 30) < 0.5)
            #expect(passport.contentKey.count == 64)
            #expect(passport.loudnessLUFS != nil)
            if let bpm = passport.bpm { #expect(abs(bpm - 120) < 2.0, "got \(bpm)") }
            else { Issue.record("expected a tempo on a click-driven signal") }
            if let key = passport.musicalKey { #expect(key.tonic == 0 && !key.isMinor, "got \(key.label)") }
        }
    }
}
