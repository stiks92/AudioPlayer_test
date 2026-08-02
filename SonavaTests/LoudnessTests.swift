//
//  LoudnessTests.swift
//  SonavaTests
//
//  Volume levelling is the complaint an aggregator earns that a
//  single-source player never does: a 1978 transfer and a modern master in
//  one queue can differ by fifteen decibels. The analyser has to be right
//  about direction and roughly right about size — and, more importantly, it
//  has to refuse to guess when it cannot measure, because a wrong correction
//  is worse than none.
//

import Testing
import Foundation
import AVFoundation
@testable import Sonava

struct LoudnessAnalyzerTests {

    /// Writes a sine at a given amplitude, so two files differ by a known
    /// number of decibels and the measurement can be checked against
    /// arithmetic rather than against itself.
    private func tone(amplitude: Float, seconds: Double = 2.0,
                      named name: String = "tone.wav") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Loudness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)

        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(sampleRate * seconds))
        else { throw CocoaError(.fileWriteUnknown) }
        buffer.frameLength = buffer.frameCapacity
        let samples = buffer.floatChannelData![0]
        for frame in 0..<Int(buffer.frameLength) {
            samples[frame] = amplitude * sinf(2 * .pi * 1_000 * Float(frame) / Float(sampleRate))
        }
        // Lossless, so the measurement is of the signal and not of a codec.
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
        ])
        try file.write(from: buffer)
        return url
    }

    private func clean(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("A quiet track is told to get louder, a loud one to get quieter")
    func directionIsCorrect() throws {
        let quiet = try tone(amplitude: 0.02, named: "quiet.wav")
        let loud = try tone(amplitude: 0.8, named: "loud.wav")
        defer { clean(quiet); clean(loud) }

        let quietMeasurement = try #require(LoudnessAnalyzer.analyse(url: quiet))
        let loudMeasurement = try #require(LoudnessAnalyzer.analyse(url: loud))

        #expect(quietMeasurement.gain > 0, "a quiet transfer must come up")
        #expect(loudMeasurement.gain < 0, "a loudness-war master must come down")
        #expect(quietMeasurement.loudness < loudMeasurement.loudness)
    }

    @Test("Two files 20 dB apart measure about 20 dB apart")
    func differenceMatchesArithmetic() throws {
        // 0.05 and 0.5 amplitude is exactly 20 dB.
        let quiet = try tone(amplitude: 0.05, named: "a.wav")
        let loud = try tone(amplitude: 0.5, named: "b.wav")
        defer { clean(quiet); clean(loud) }

        let a = try #require(LoudnessAnalyzer.analyse(url: quiet))
        let b = try #require(LoudnessAnalyzer.analyse(url: loud))
        let measured = b.loudness - a.loudness
        #expect(abs(measured - 20) < 1.5,
                "measured \(measured) dB apart; the analyser is out by more than tolerance")
    }

    @Test("Levelling brings both to about the same place")
    func levellingConverges() throws {
        let quiet = try tone(amplitude: 0.05, named: "a.wav")
        let loud = try tone(amplitude: 0.5, named: "b.wav")
        defer { clean(quiet); clean(loud) }

        let a = try #require(LoudnessAnalyzer.analyse(url: quiet))
        let b = try #require(LoudnessAnalyzer.analyse(url: loud))
        // Whatever the absolute numbers, applying each gain must close the gap
        // — that is the entire user-visible promise.
        let after = abs((a.loudness + a.gain) - (b.loudness + b.gain))
        let before = abs(a.loudness - b.loudness)
        #expect(after < before / 2, "the gap must close, not merely move")
    }

    @Test("The correction is bounded — a field recording isn't rebalanced into a mix")
    func gainIsClamped() throws {
        let nearSilent = try tone(amplitude: 0.0005, named: "whisper.wav")
        defer { clean(nearSilent) }
        let measurement = try #require(LoudnessAnalyzer.analyse(url: nearSilent))
        #expect(measurement.gain <= LoudnessAnalyzer.maximumGain)
        #expect(measurement.gain >= LoudnessAnalyzer.minimumGain)
    }

    @Test("Silence is refused rather than assigned a huge gain")
    func silenceYieldsNothing() throws {
        let silence = try tone(amplitude: 0, named: "silence.wav")
        defer { clean(silence) }
        #expect(LoudnessAnalyzer.analyse(url: silence) == nil,
                "there is nothing to measure, and +12 dB of hiss is not the answer")
    }

    @Test("An unreadable file is refused, not guessed at")
    func missingFileYieldsNothing() {
        let ghost = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-such-\(UUID().uuidString).wav")
        #expect(LoudnessAnalyzer.analyse(url: ghost) == nil)
    }

    @Test("A ReplayGain tag maps onto the same scale as a measurement")
    func replayGainMapsToTheSameScale() {
        // ReplayGain targets −14 LUFS; the app targets −18, so a tag of 0 dB
        // means "already at −14" and needs −4 to sit with everything else.
        #expect(abs(LoudnessAnalyzer.gain(fromReplayGain: 0) - (-4)) < 0.001)
        #expect(abs(LoudnessAnalyzer.gain(fromReplayGain: 6) - 2) < 0.001)
        // And it obeys the same limits.
        #expect(LoudnessAnalyzer.gain(fromReplayGain: 40) == LoudnessAnalyzer.maximumGain)
    }
}

@MainActor
struct LoudnessStoreTests {

    private func song(_ id: String, replayGain: Double? = nil) -> Song {
        Song(id: id, title: "T", artist: "A", album: "B", source: .audius,
             gradientHex: Palette.hex(for: 0), replayGain: replayGain)
    }

    /// Its own cache file and its own defaults key: these cases run in
    /// parallel, and sharing either makes them fight.
    private func fresh(_ label: String = #function) -> LoudnessStore {
        let name = "loudness-test-\(label.replacingOccurrences(of: "()", with: ""))-\(UUID().uuidString).json"
        return LoudnessStore(store: JSONFileStore(name, default: [:]),
                             enabledKey: "loudness.enabled.test.\(UUID().uuidString)")
    }

    @Test("Switched off, nothing is corrected")
    func disabledMeansNoGain() {
        let store = fresh()
        store.isEnabled = false
        store.setMeasurementForTesting(.init(loudness: -30, gain: 12), id: "x")
        #expect(store.gain(for: song("x"), fileURL: nil) == 0)
    }

    @Test("A server's ReplayGain tag is used instead of analysing anything")
    func usesReplayGainTag() {
        let store = fresh()
        let tagged = song("subsonic:1", replayGain: 6)
        let gain = store.gain(for: tagged, fileURL: nil)
        #expect(abs(gain - 2) < 0.001)
        #expect(store.isMeasured(tagged), "the tag counts as a measurement — no re-analysis")
    }

    @Test("An unmeasured track plays at its own level rather than waiting")
    func unmeasuredPlaysFlat() {
        let store = fresh()
        #expect(store.gain(for: song("unknown"), fileURL: nil) == 0)
    }

    @Test("A measurement survives a relaunch")
    func measurementsPersist() {
        let name = "loudness-persist-\(UUID().uuidString).json"
        let file = JSONFileStore<[String: LoudnessAnalyzer.Measurement]>(name, default: [:])
        file.write(["kept": .init(loudness: -22, gain: 4)])

        let store = LoudnessStore(store: file,
                                  enabledKey: "loudness.enabled.test.\(UUID().uuidString)")
        #expect(abs(store.gain(for: song("kept"), fileURL: nil) - 4) < 0.001,
                "analysing a 60 MB FLAC on every launch is not acceptable")
    }
}
