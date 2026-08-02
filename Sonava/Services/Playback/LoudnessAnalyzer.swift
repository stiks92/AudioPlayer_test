//
//  LoudnessAnalyzer.swift
//  Sonava
//
//  Volume levelling: the loudest complaint an aggregator earns that a
//  single-source player never does.
//
//  Sonava plays a 2013 CD rip, a 1978 vinyl transfer, a modern loudness-war
//  master and an internet radio station from the same queue. Their levels can
//  differ by fifteen decibels, which means the listener spends the evening
//  reaching for the volume — and reaches for a different app next time.
//
//  ## What this measures, and what it deliberately does not
//
//  This computes the track's **integrated loudness** the way EBU R128
//  defines it: K-weighted (a shelving filter plus a high-pass, approximating
//  what the ear does), meaned over 400 ms blocks, with the quiet blocks
//  gated out so that a track with long silences is not judged by its silence.
//  The result is a gain in decibels that brings the track to a −18 LUFS
//  reference.
//
//  It is not a bit-exact R128 implementation: the two-stage relative gate is
//  simplified to a single pass, and true-peak limiting is not attempted. For
//  the job at hand — stopping a 1978 transfer from being eight decibels
//  quieter than the track after it — that is the honest amount of machinery.
//  Anything claiming more precision than it has would be worse than nothing.
//
//  Analysis runs off the main actor, once per file, and the answer is cached
//  by file. A track the app cannot analyse (a stream, a file that won't open)
//  gets no gain rather than a guessed one.
//

import Foundation
import AVFoundation

struct LoudnessAnalyzer {

    /// The level everything is brought to. −18 LUFS is the quiet end of the
    /// broadcast range: loud masters come down to meet it rather than quiet
    /// ones being pushed up into clipping.
    static let referenceLUFS: Double = -18

    /// How far the correction may go. Beyond this a track is not "quiet", it
    /// is something else — a field recording, a spoken intro — and lifting it
    /// twenty decibels would be the app inventing a mix.
    static let maximumGain: Double = 12
    static let minimumGain: Double = -12

    /// Measured loudness and the gain that brings it to the reference.
    struct Measurement: Codable, Equatable, Sendable {
        /// Integrated loudness, LUFS.
        let loudness: Double
        /// dB to apply. Clamped to the limits above.
        let gain: Double
    }

    // MARK: - Analysis

    /// Measures a file. Returns nil when it cannot be read — never a guess.
    ///
    /// Reads in blocks rather than loading the file: a 90-minute FLAC is
    /// gigabytes as float samples, and this runs on a phone.
    static func analyse(url: URL) -> Measurement? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0, file.length > 0 else { return nil }

        // 400 ms blocks, as R128 specifies.
        let blockFrames = AVAudioFrameCount(sampleRate * 0.4)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: blockFrames) else {
            return nil
        }

        var filters = (0..<Int(format.channelCount)).map { _ in KWeighting(sampleRate: sampleRate) }
        var blockLoudness: [Double] = []

        while true {
            buffer.frameLength = 0
            guard (try? file.read(into: buffer, frameCount: blockFrames)) != nil,
                  buffer.frameLength > 0 else { break }
            guard let channels = buffer.floatChannelData else { break }

            // Mean square of the K-weighted signal, summed across channels the
            // way R128 does (each channel weighted 1.0 for mono/stereo).
            var sum = 0.0
            let frames = Int(buffer.frameLength)
            for channel in 0..<Int(format.channelCount) {
                let samples = channels[channel]
                var channelSum = 0.0
                for frame in 0..<frames {
                    let filtered = filters[channel].process(Double(samples[frame]))
                    channelSum += filtered * filtered
                }
                sum += channelSum / Double(frames)
            }
            guard sum > 0 else { continue }
            blockLoudness.append(-0.691 + 10 * log10(sum))
        }

        guard !blockLoudness.isEmpty else { return nil }

        // Absolute gate: blocks below −70 LUFS are silence and must not drag
        // the average down.
        let audible = blockLoudness.filter { $0 > -70 }
        guard !audible.isEmpty else { return nil }

        // Relative gate: having found the ungated mean, drop everything more
        // than 10 LU below it, so a quiet intro doesn't define the record.
        let ungated = mean(audible)
        let gated = audible.filter { $0 > ungated - 10 }
        let loudness = mean(gated.isEmpty ? audible : gated)

        let gain = min(max(referenceLUFS - loudness, minimumGain), maximumGain)
        return Measurement(loudness: loudness, gain: gain)
    }

    private static func mean(_ values: [Double]) -> Double {
        // Loudness averages in the energy domain, not the log domain.
        let energy = values.reduce(0.0) { $0 + pow(10, $1 / 10) } / Double(values.count)
        return 10 * log10(energy)
    }

    /// Converts a ReplayGain tag (dB relative to 89 dB SPL) into the same
    /// correction this analyser produces, so a server that already publishes
    /// one costs no analysis at all.
    ///
    /// ReplayGain targets −14 LUFS in its modern form; the offset lines it up
    /// with our reference so tagged and analysed tracks sit at the same level.
    static func gain(fromReplayGain tag: Double) -> Double {
        min(max(tag + (referenceLUFS - (-14)), minimumGain), maximumGain)
    }
}

// MARK: - K-weighting

/// The two filters R128 puts in front of the measurement: a high-frequency
/// shelf standing in for the head's acoustics, then a high-pass that stops
/// sub-bass energy counting as loudness. Coefficients are the standard ones,
/// re-derived for the file's sample rate rather than assuming 48 kHz — which
/// is exactly the mistake that makes a 44.1 kHz rip measure a fraction of a
/// decibel off.
private struct KWeighting {
    private var shelf: Biquad
    private var highPass: Biquad

    init(sampleRate: Double) {
        // Stage 1 — high shelf, +4 dB above ~1.5 kHz.
        let f0 = 1681.974450955533
        let G = 3.999843853973347
        let Q = 0.7071752369554196
        let K = tan(.pi * f0 / sampleRate)
        let Vh = pow(10, G / 20)
        let Vb = pow(Vh, 0.4996667741545416)
        let a0 = 1 + K / Q + K * K
        shelf = Biquad(
            b0: (Vh + Vb * K / Q + K * K) / a0,
            b1: 2 * (K * K - Vh) / a0,
            b2: (Vh - Vb * K / Q + K * K) / a0,
            a1: 2 * (K * K - 1) / a0,
            a2: (1 - K / Q + K * K) / a0)

        // Stage 2 — high-pass at ~38 Hz.
        let f0hp = 38.13547087602444
        let Qhp = 0.5003270373238773
        let Khp = tan(.pi * f0hp / sampleRate)
        highPass = Biquad(
            b0: 1,
            b1: -2,
            b2: 1,
            a1: 2 * (Khp * Khp - 1) / (1 + Khp / Qhp + Khp * Khp),
            a2: (1 - Khp / Qhp + Khp * Khp) / (1 + Khp / Qhp + Khp * Khp))
    }

    mutating func process(_ sample: Double) -> Double {
        highPass.process(shelf.process(sample))
    }
}

private struct Biquad {
    let b0, b1, b2, a1, a2: Double
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }
}
