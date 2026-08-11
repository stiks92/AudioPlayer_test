//
//  PassportAnalyzer.swift
//  Sonava
//
//  The one measurement pass behind every Backroom feature: tempo, beat
//  grid, key, loudness and a content digest, computed offline from the
//  decoded audio.
//
//  Method notes, because DSP without stated method rots into folklore:
//
//  * Everything runs on a mono stream decimated to 11 025 Hz behind a
//    5 kHz low-pass. Onset energy and chroma both live below 5 kHz, and a
//    quarter of the samples means a quarter of the battery.
//  * Tempo: spectral-flux onset envelope (1024-point DFT, hop 128 →
//    ~86 fps) → autocorrelation over the 60–200 BPM lag range → parabolic
//    peak interpolation → folded into the 80–160 octave. Confidence is the
//    peak's prominence over the median of the field.
//  * Beat grid: comb alignment of the winning interval against the onset
//    envelope; the phase that collects the most onset energy wins. A grid
//    that explains too little of the energy is discarded — rubato and
//    ambient get nil, never a fabricated grid.
//  * Key: magnitudes summed into 12 pitch classes across all frames
//    (60 Hz – 5 kHz), correlated against the Krumhansl–Schmuckler major and
//    minor profiles in all 12 rotations. Confidence is the winner's margin
//    over the runner-up.
//  * Loudness reuses LoudnessAnalyzer verbatim — one R128 implementation in
//    the app, not two drifting ones. It re-reads the file; at analysis-time
//    (background, once per track, phone idle) that trade is fine.
//
//  Patent posture: this file measures. It does not time-stretch, does not
//  resample toward a target tempo, and does not compute equal-loudness
//  compensation. See TrackPassport.swift for why that is a design line,
//  not a missing feature.
//

import Accelerate
import AVFoundation
import CryptoKit
import Foundation

enum PassportAnalyzer {

    // MARK: - Entry

    /// Analyses one audio file into a passport. Returns nil only when the
    /// file cannot be decoded at all — partial knowledge is a passport with
    /// nil fields, not a failure.
    static func analyze(url: URL) -> TrackPassport? {
        guard let decoded = decodeMono11k(url: url) else { return nil }
        let samples = decoded.samples

        let key = contentKey(samples: samples)
        let flux = onsetEnvelope(samples: samples)
        let tempo = tempoEstimate(flux: flux)
        var grid: BeatGrid?
        if let tempo { grid = beatGrid(flux: flux, bpm: tempo.bpm) }
        let musicalKey = keyEstimate(samples: samples)
        let loudness = LoudnessAnalyzer.analyse(url: url)?.loudness

        return TrackPassport(
            contentKey: key,
            durationSeconds: decoded.duration,
            loudnessLUFS: loudness,
            bpm: tempo?.bpm,
            bpmConfidence: tempo?.confidence,
            beatGrid: grid,
            musicalKey: musicalKey,
            analyzedAt: Date()
        )
    }

    // MARK: - Decode

    static let workRate: Double = 11_025
    /// Analysis window: the first four minutes describe a track's tempo and
    /// key as well as all forty of a DJ mix would — better, in fact.
    private static let maxAnalysisSeconds: Double = 240

    private struct Decoded {
        var samples: [Float]
        var duration: Double
    }

    /// Mono, 11 025 Hz, low-passed. Reads in blocks; never holds the file.
    private static func decodeMono11k(url: URL) -> Decoded? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let sourceRate = format.sampleRate
        guard sourceRate > 0, file.length > 0 else { return nil }
        let duration = Double(file.length) / sourceRate

        let ratio = max(1, Int((sourceRate / workRate).rounded()))
        var lowpass = SimpleLowpass(cutoff: 5_000, sampleRate: sourceRate)

        let blockFrames = AVAudioFrameCount(65_536)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: blockFrames) else { return nil }

        var output: [Float] = []
        output.reserveCapacity(Int(min(duration, maxAnalysisSeconds) * workRate) + 1)
        var phase = 0
        var accumulator: Float = 0
        let framesWanted = AVAudioFramePosition(min(duration, maxAnalysisSeconds) * sourceRate)
        var framesRead: AVAudioFramePosition = 0

        while framesRead < framesWanted {
            buffer.frameLength = 0
            guard (try? file.read(into: buffer)) != nil, buffer.frameLength > 0 else { break }
            let frames = Int(buffer.frameLength)
            let channels = Int(format.channelCount)
            guard let data = buffer.floatChannelData else { return nil }

            for frame in 0..<frames {
                var mono: Float = 0
                for channel in 0..<channels { mono += data[channel][frame] }
                mono /= Float(channels)
                let filtered = lowpass.process(mono)
                accumulator += filtered
                phase += 1
                if phase == ratio {
                    output.append(accumulator / Float(ratio))
                    accumulator = 0
                    phase = 0
                }
            }
            framesRead += AVAudioFramePosition(frames)
        }
        guard output.count > Int(workRate) else { return nil }   // under a second is noise
        return Decoded(samples: output, duration: duration)
    }

    /// One biquad low-pass (RBJ), enough anti-aliasing for onset and chroma
    /// work — this is analysis, not mastering.
    private struct SimpleLowpass {
        private var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
        private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

        init(cutoff: Double, sampleRate: Double) {
            let omega = 2 * .pi * min(cutoff, sampleRate * 0.45) / sampleRate
            let alpha = sin(omega) / (2 * 0.707)
            let cosO = cos(omega)
            let a0 = 1 + alpha
            b0 = Float((1 - cosO) / 2 / a0)
            b1 = Float((1 - cosO) / a0)
            b2 = Float((1 - cosO) / 2 / a0)
            a1 = Float(-2 * cosO / a0)
            a2 = Float((1 - alpha) / a0)
        }

        mutating func process(_ x: Float) -> Float {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }
    }

    // MARK: - Content key

    /// SHA-256 over the first 60 s of the decoded (mono, 11 025 Hz,
    /// 16-bit-quantised) audio. Survives retagging and container moves;
    /// does NOT survive transcodes — see `TrackPassport.keyKind`.
    static func contentKey(samples: [Float]) -> String {
        let count = min(samples.count, Int(workRate * 60))
        var quantised = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            quantised[index] = Int16(max(-1, min(1, samples[index])) * 32_767)
        }
        let digest = quantised.withUnsafeBytes { SHA256.hash(data: $0) }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Onset envelope

    static let fftSize = 1_024
    static let hop = 128
    /// Frames per second of the onset envelope.
    static var envelopeRate: Double { workRate / Double(hop) }

    /// Half-wave-rectified spectral flux per hop — "how much new energy
    /// arrived", the raw material of both tempo and grid.
    static func onsetEnvelope(samples: [Float]) -> [Float] {
        guard samples.count >= fftSize,
              let dft = vDSP.DFT(count: fftSize, direction: .forward,
                                 transformType: .complexReal, ofType: Float.self) else { return [] }
        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                                 count: fftSize, isHalfWindow: false)
        let bins = fftSize / 2
        var previous = [Float](repeating: 0, count: bins)
        var flux: [Float] = []
        flux.reserveCapacity((samples.count - fftSize) / hop + 1)

        var real = [Float](repeating: 0, count: fftSize)
        var imaginary = [Float](repeating: 0, count: fftSize)
        var outReal = [Float](repeating: 0, count: fftSize)
        var outImaginary = [Float](repeating: 0, count: fftSize)
        var magnitudes = [Float](repeating: 0, count: bins)

        var start = 0
        while start + fftSize <= samples.count {
            for index in 0..<fftSize { real[index] = samples[start + index] * window[index] }
            for index in 0..<fftSize { imaginary[index] = 0 }
            dft.transform(inputReal: real, inputImaginary: imaginary,
                          outputReal: &outReal, outputImaginary: &outImaginary)
            for bin in 0..<bins {
                magnitudes[bin] = sqrt(outReal[bin] * outReal[bin] + outImaginary[bin] * outImaginary[bin])
            }
            var sum: Float = 0
            for bin in 1..<bins {
                let difference = magnitudes[bin] - previous[bin]
                if difference > 0 { sum += difference }
            }
            flux.append(sum)
            swap(&previous, &magnitudes)
            start += hop
        }
        // Remove the slow-moving mean so autocorrelation sees rhythm, not
        // arrangement dynamics.
        if !flux.isEmpty {
            let mean = flux.reduce(0, +) / Float(flux.count)
            for index in flux.indices { flux[index] = max(0, flux[index] - mean) }
        }
        return flux
    }

    // MARK: - Tempo

    struct Tempo { var bpm: Double; var confidence: Double }

    /// Autocorrelation of the onset envelope over 60–200 BPM, parabolic
    /// interpolation, folded to 80–160. Returns nil when no lag stands out —
    /// ambient and rubato must not get a number.
    static func tempoEstimate(flux: [Float]) -> Tempo? {
        let rate = envelopeRate
        let minLag = Int(rate * 60 / 200)   // 200 BPM
        let maxLag = Int(rate * 60 / 60)    // 60 BPM
        guard flux.count > maxLag * 3, minLag > 4 else { return nil }

        var correlation = [Double](repeating: 0, count: maxLag + 2)
        for lag in minLag...maxLag {
            var sum: Double = 0
            for index in 0..<(flux.count - lag) {
                sum += Double(flux[index]) * Double(flux[index + lag])
            }
            correlation[lag] = sum / Double(flux.count - lag)
        }

        let field = correlation[minLag...maxLag].sorted()
        let median = field[field.count / 2]
        guard let peakLag = (minLag...maxLag).max(by: { correlation[$0] < correlation[$1] }) else { return nil }
        let peak = correlation[peakLag]
        guard peak > 0, median >= 0 else { return nil }

        // Parabolic refinement around the winning lag.
        var refinedLag = Double(peakLag)
        if peakLag > minLag && peakLag < maxLag {
            let left = correlation[peakLag - 1], centre = peak, right = correlation[peakLag + 1]
            let denominator = left - 2 * centre + right
            if abs(denominator) > 1e-12 {
                refinedLag += 0.5 * (left - right) / denominator
            }
        }

        var bpm = 60 * rate / refinedLag
        while bpm < 80 { bpm *= 2 }
        while bpm >= 160 { bpm /= 2 }

        let prominence = (peak - median) / peak
        guard prominence > 0.35 else { return nil }
        return Tempo(bpm: bpm, confidence: min(1, prominence))
    }

    // MARK: - Beat grid

    /// Aligns a comb of the winning interval against the onset envelope.
    static func beatGrid(flux: [Float], bpm: Double) -> BeatGrid? {
        let rate = envelopeRate
        let interval = 60.0 / bpm * rate            // in envelope frames
        guard interval > 4, flux.count > Int(interval * 8) else { return nil }

        let phaseSteps = max(16, Int(interval))
        var bestPhase = 0.0
        var bestScore = -Double.infinity
        var totalScore = 0.0
        for step in 0..<phaseSteps {
            let phase = Double(step) / Double(phaseSteps) * interval
            var score = 0.0
            var position = phase
            while Int(position) < flux.count {
                score += Double(flux[Int(position)])
                position += interval
            }
            totalScore += score
            if score > bestScore { bestScore = score; bestPhase = phase }
        }
        let meanScore = totalScore / Double(phaseSteps)
        guard meanScore > 0 else { return nil }
        let confidence = min(1, max(0, (bestScore - meanScore) / bestScore))
        // A comb that barely beats the average phase is not a grid.
        guard confidence > 0.25 else { return nil }

        return BeatGrid(
            firstBeatOffset: bestPhase / rate,
            interval: 60.0 / bpm,
            confidence: confidence
        )
    }

    // MARK: - Key

    /// Krumhansl–Schmuckler profiles (probe-tone ratings, 1982) — the
    /// standard against which key detectors are still measured.
    static let majorProfile: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    static let minorProfile: [Double] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    static func keyEstimate(samples: [Float]) -> MusicalKey? {
        guard samples.count >= fftSize,
              let dft = vDSP.DFT(count: fftSize, direction: .forward,
                                 transformType: .complexReal, ofType: Float.self) else { return nil }
        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                                 count: fftSize, isHalfWindow: false)
        var chroma = [Double](repeating: 0, count: 12)
        let bins = fftSize / 2
        let binWidth = workRate / Double(fftSize)

        var real = [Float](repeating: 0, count: fftSize)
        var imaginary = [Float](repeating: 0, count: fftSize)
        var outReal = [Float](repeating: 0, count: fftSize)
        var outImaginary = [Float](repeating: 0, count: fftSize)

        // Chroma needs pitch resolution, not time resolution: stride in
        // whole windows.
        var start = 0
        while start + fftSize <= samples.count {
            for index in 0..<fftSize { real[index] = samples[start + index] * window[index] }
            for index in 0..<fftSize { imaginary[index] = 0 }
            dft.transform(inputReal: real, inputImaginary: imaginary,
                          outputReal: &outReal, outputImaginary: &outImaginary)
            for bin in 1..<bins {
                let frequency = Double(bin) * binWidth
                guard frequency >= 60, frequency <= 5_000 else { continue }
                let magnitude = Double(sqrt(outReal[bin] * outReal[bin] + outImaginary[bin] * outImaginary[bin]))
                let midi = 69 + 12 * log2(frequency / 440)
                let pitchClass = ((Int(midi.rounded()) % 12) + 12) % 12
                chroma[pitchClass] += magnitude
            }
            start += fftSize
        }
        let total = chroma.reduce(0, +)
        guard total > 0 else { return nil }

        var best: (score: Double, tonic: Int, minor: Bool)?
        var second: Double = -.infinity
        for tonic in 0..<12 {
            for (minor, profile) in [(false, majorProfile), (true, minorProfile)] {
                var rotated = [Double](repeating: 0, count: 12)
                for index in 0..<12 { rotated[index] = profile[((index - tonic) % 12 + 12) % 12] }
                let score = pearson(chroma, rotated)
                if best == nil || score > best!.score {
                    second = best?.score ?? -.infinity
                    best = (score, tonic, minor)
                } else if score > second {
                    second = score
                }
            }
        }
        guard let winner = best, winner.score > 0 else { return nil }
        let margin = second.isFinite ? max(0, winner.score - second) : winner.score
        let confidence = min(1, margin / max(abs(winner.score), 1e-9))
        return MusicalKey(tonic: winner.tonic, isMinor: winner.minor, confidence: confidence)
    }

    private static func pearson(_ a: [Double], _ b: [Double]) -> Double {
        let n = Double(a.count)
        let meanA = a.reduce(0, +) / n
        let meanB = b.reduce(0, +) / n
        var covariance = 0.0, varianceA = 0.0, varianceB = 0.0
        for index in a.indices {
            let da = a[index] - meanA, db = b[index] - meanB
            covariance += da * db
            varianceA += da * da
            varianceB += db * db
        }
        let denominator = sqrt(varianceA * varianceB)
        return denominator > 0 ? covariance / denominator : 0
    }
}
