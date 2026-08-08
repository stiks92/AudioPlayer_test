//
//  StreamProcessingTap.swift
//  Sonava
//
//  The equalizer and loudness levelling for everything AVPlayer plays.
//
//  The local engine runs an AVAudioUnitEQ node; AVPlayer has no insertable
//  node, so for two months every stream — Subsonic, WebDAV, Audius, radio —
//  played flat while the EQ screen quietly said so. That footnote was the
//  last honesty gap the growth scan called a marketing blocker: the one
//  word the App Store listing could not say was "equalizer".
//
//  An MTAudioProcessingTap sits inside the player item's audio mix and hands
//  us raw PCM between decode and output. We run the same ten-band curve the
//  local engine runs — same centre frequencies, same 0.5-octave bandwidth,
//  RBJ peaking biquads — plus the summed preamp and per-track loudness gain,
//  and measure the true output level while we are there (the visualizer for
//  streams was synthesised until now; see `RemoteAudioEngine.refresh`).
//
//  Two deliberate structural choices:
//
//  * The DSP lives in `EqualizerDSP`, a plain class with no AVFoundation in
//    sight, because the tap's C callbacks cannot be unit-tested but filter
//    arithmetic can — the tests feed sines through it and assert decibels.
//
//  * The audio thread takes one short unfair lock per buffer and allocates
//    nothing. The main thread's writes under that lock (a settings change, a
//    level drain) are a few hundred nanoseconds; the alternative — copying
//    filter state out and back — allocates on the audio thread, which is the
//    worse trade.
//

import AVFoundation
import os

// MARK: - Filter arithmetic

/// One RBJ "peaking EQ" biquad, normalised so a0 = 1.
struct BiquadCoefficients: Equatable {
    var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float

    /// Audio EQ Cookbook (R. Bristow-Johnson), peakingEQ, bandwidth form —
    /// the same curve family AVAudioUnitEQ's `.parametric` filter uses, with
    /// the same 0.5-octave bandwidth the local engine configures.
    init(frequency: Float, gainDB: Float, bandwidthOctaves: Float, sampleRate: Float) {
        let amp = pow(10, gainDB / 40)
        let omega = 2 * Float.pi * frequency / sampleRate
        let sinOmega = sin(omega)
        let alpha = sinOmega * sinh(log(2) / 2 * bandwidthOctaves * omega / sinOmega)
        let cosOmega = cos(omega)
        let a0 = 1 + alpha / amp
        b0 = (1 + alpha * amp) / a0
        b1 = (-2 * cosOmega) / a0
        b2 = (1 - alpha * amp) / a0
        a1 = (-2 * cosOmega) / a0
        a2 = (1 - alpha / amp) / a0
    }
}

/// The ten-band cascade plus a linear make-up gain, processing float32 PCM in
/// place. Channel delay lines are isolated per channel: a filter's memory of
/// the left channel must never colour the right.
final class EqualizerDSP {

    private var lock = os_unfair_lock()

    // Everything below the lock line is guarded by it.
    private var coefficients: [BiquadCoefficients] = []
    private var linearGain: Float = 1
    /// Per channel, per band: lanes are x[n-1], x[n-2], y[n-1], y[n-2].
    private var memory: [[SIMD4<Float>]] = []
    private var sampleRate: Float = 44_100
    private var settings = EqualizerSettings()
    private var loudnessGainDB: Double = 0
    private var levelEnergy: Float = 0
    private var levelFrames: Int = 0

    // MARK: Configuration

    /// Called from the tap's prepare callback with the stream's real format.
    /// Recomputes the cascade: a curve computed for 44.1 kHz is a different
    /// filter at 22.05, and web radio ships every rate there is.
    func configure(sampleRate: Double, channels: Int) {
        os_unfair_lock_lock(&lock)
        self.sampleRate = Float(sampleRate)
        memory = Array(repeating: [], count: max(1, channels))
        rebuildLocked()
        os_unfair_lock_unlock(&lock)
    }

    /// Recomputes the cascade for a settings + loudness pair.
    func update(settings: EqualizerSettings, loudnessGainDB: Double) {
        os_unfair_lock_lock(&lock)
        self.settings = settings
        self.loudnessGainDB = loudnessGainDB
        rebuildLocked()
        os_unfair_lock_unlock(&lock)
    }

    private func rebuildLocked() {
        var bands: [BiquadCoefficients] = []
        if settings.isEnabled {
            for (index, frequency) in EqualizerBand.frequencies.enumerated() {
                let gain = settings.gains[index]
                // A unity band costs cycles and does nothing; a band centred
                // above what this stream's rate can represent would fold into
                // garbage. Both are skipped, not clamped.
                guard abs(gain) > 0.05, frequency < sampleRate * 0.45 else { continue }
                bands.append(BiquadCoefficients(
                    frequency: frequency, gainDB: gain,
                    bandwidthOctaves: 0.5, sampleRate: sampleRate))
            }
        }
        let preamp = settings.isEnabled ? Double(settings.preamp) : 0
        // The same ±24 dB clamp the local engine applies to its globalGain.
        let totalDB = min(max(preamp + loudnessGainDB, -24), 24)
        coefficients = bands
        linearGain = pow(10, Float(totalDB) / 20)
        for channel in memory.indices {
            memory[channel] = Array(repeating: .zero, count: bands.count)
        }
    }

    // MARK: Processing (audio thread)

    /// Filters one channel's samples in place. `stride` is 1 for deinterleaved
    /// buffers, the channel count for interleaved ones.
    func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, channel: Int, stride: Int) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard channel < memory.count, frames > 0 else { return }

        let gain = linearGain
        var energy: Float = 0
        var index = 0

        if coefficients.isEmpty && gain == 1 {
            for _ in 0..<frames {
                let sample = samples[index]
                energy += sample * sample
                index += stride
            }
        } else {
            for _ in 0..<frames {
                var sample = samples[index]
                for band in coefficients.indices {
                    let c = coefficients[band]
                    let m = memory[channel][band]
                    // Direct Form I: y = b0·x + b1·x1 + b2·x2 − a1·y1 − a2·y2
                    let filtered = c.b0 * sample + c.b1 * m.x + c.b2 * m.y
                                 - c.a1 * m.z - c.a2 * m.w
                    memory[channel][band] = SIMD4(sample, m.x, filtered, m.z)
                    sample = filtered
                }
                let out = sample * gain
                samples[index] = out
                energy += out * out
                index += stride
            }
        }

        levelEnergy += energy
        levelFrames += frames
    }

    /// RMS of everything processed since the last call — the *measured* level
    /// of the stream, replacing the synthetic sine the visualizer used to get.
    func drainLevel() -> Float {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard levelFrames > 0 else { return 0 }
        let rms = sqrt(levelEnergy / Float(levelFrames))
        levelEnergy = 0
        levelFrames = 0
        return rms
    }
}

// MARK: - The tap itself

/// Owns an `MTAudioProcessingTap` and the audio mix that carries it, and
/// forwards every buffer through the shared `EqualizerDSP`.
final class StreamProcessingTap {

    let dsp = EqualizerDSP()

    /// Whether a mix carrying the tap is currently attached to an item —
    /// the fact the EQ screen shows instead of guessing. Main-thread only.
    private(set) var isAttached = false
    var onAttachChange: ((Bool) -> Void)?

    private var loadTask: Task<Void, Never>?

    /// Storage handed to the C callbacks. The tap retains it; `finalize`
    /// releases it. It deliberately owns only the DSP — never the tap class,
    /// or teardown order would become a reference cycle with an audio thread
    /// in the middle.
    fileprivate final class TapStorage {
        let dsp: EqualizerDSP
        init(dsp: EqualizerDSP) { self.dsp = dsp }
    }

    /// Builds the audio mix for an item once its audible track is known, and
    /// attaches it. Progressive HTTP audio (Subsonic, WebDAV, Audius, most
    /// radio) exposes its track shortly after loading; HLS wraps its audio
    /// where no tap can reach, `loadTracks` returns nothing, and we report
    /// "not attached" so the UI can say the stream plays flat — true, and
    /// said in the one place the listener is looking.
    @MainActor
    func attach(to item: AVPlayerItem) {
        detach()
        loadTask = Task { [weak self, weak item] in
            guard let tracks = try? await item?.asset.loadTracks(withMediaType: .audio),
                  let track = tracks.first,
                  !Task.isCancelled,
                  let self, let item else { return }

            var callbacks = MTAudioProcessingTapCallbacks(
                version: kMTAudioProcessingTapCallbacksVersion_0,
                clientInfo: UnsafeMutableRawPointer(
                    Unmanaged.passRetained(TapStorage(dsp: self.dsp)).toOpaque()),
                init: tapInitCallback,
                finalize: tapFinalizeCallback,
                prepare: tapPrepareCallback,
                unprepare: tapUnprepareCallback,
                process: tapProcessCallback
            )

            var tapOut: MTAudioProcessingTap?
            let status = MTAudioProcessingTapCreate(
                kCFAllocatorDefault, &callbacks,
                kMTAudioProcessingTapCreationFlag_PostEffects, &tapOut)
            guard status == noErr, let tap = tapOut, !Task.isCancelled else { return }

            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [parameters]

            await MainActor.run { [weak self, weak item] in
                guard let self, let item, !(self.loadTask?.isCancelled ?? true) else { return }
                item.audioMix = mix
                self.isAttached = true
                self.onAttachChange?(true)
            }
        }
    }

    @MainActor
    func detach() {
        loadTask?.cancel()
        loadTask = nil
        if isAttached {
            isAttached = false
            onAttachChange?(false)
        }
    }
}

// MARK: - C callbacks
//
// Deliberately at file scope, outside every actor context. The first version
// declared these inline inside `attach`'s `Task { }` — a MainActor-inheriting
// context — so the compiler stamped the closures with an isolation check.
// MediaToolbox then called `finalize` from its own queue during a full
// parallel test run and the check tripped: dispatch_assert_queue_fail,
// SIGTRAP, dead test host. In isolation the release happened to come from the
// main queue and everything "worked". An audio framework's C callbacks run
// wherever the framework pleases, so they must carry no isolation at all.

private func tapStorage(_ tap: MTAudioProcessingTap) -> StreamProcessingTap.TapStorage {
    Unmanaged<StreamProcessingTap.TapStorage>
        .fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
}

private let tapInitCallback: MTAudioProcessingTapInitCallback = { _, clientInfo, storageOut in
    storageOut.pointee = clientInfo
}

private let tapFinalizeCallback: MTAudioProcessingTapFinalizeCallback = { tap in
    Unmanaged<StreamProcessingTap.TapStorage>
        .fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private let tapPrepareCallback: MTAudioProcessingTapPrepareCallback = { tap, _, format in
    tapStorage(tap).dsp.configure(
        sampleRate: format.pointee.mSampleRate,
        channels: Int(format.pointee.mChannelsPerFrame))
}

private let tapUnprepareCallback: MTAudioProcessingTapUnprepareCallback = { _ in }

private let tapProcessCallback: MTAudioProcessingTapProcessCallback = { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
    let status = MTAudioProcessingTapGetSourceAudio(
        tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
    guard status == noErr else { return }
    let dsp = tapStorage(tap).dsp
    let frames = Int(numberFramesOut.pointee)
    let buffers = UnsafeMutableAudioBufferListPointer(bufferListInOut)
    for (bufferIndex, buffer) in buffers.enumerated() {
        guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
        let channelsHere = Int(buffer.mNumberChannels)
        if channelsHere <= 1 {
            // Deinterleaved: one buffer per channel.
            dsp.process(data, frames: frames, channel: bufferIndex, stride: 1)
        } else {
            // Interleaved: one buffer, samples striped by channel.
            for channel in 0..<channelsHere {
                dsp.process(data + channel, frames: frames,
                            channel: channel, stride: channelsHere)
            }
        }
    }
}
