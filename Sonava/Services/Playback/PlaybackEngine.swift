//
//  PlaybackEngine.swift
//  Sonava
//
//  Two interchangeable playback backends behind one interface:
//  - LocalAudioEngine  : an AVAudioEngine graph for imported files, giving a
//                        real 10-band equalizer and true tap-based metering.
//  - RemoteAudioEngine : AVPlayer for network streams & live radio.
//
//  AudioManager picks a backend per track and never touches AVFoundation
//  directly.
//

import Foundation
import AVFoundation
import QuartzCore
import os

/// Playback is driven entirely from `AudioManager`, which is main-actor
/// isolated, and both backends touch UIKit-adjacent AVFoundation state.
/// Pinning the protocol to the main actor makes that contract explicit rather
/// than something every call site has to remember.
@MainActor
protocol PlaybackEngine: AnyObject {
    var onFinish: (() -> Void)? { get set }
    /// The engine started the *preloaded* track without stopping — playback
    /// never paused, so the app must catch its state up rather than load
    /// anything. Only the local engine can do this; see `preloadNext`.
    var onAdvancedToNext: (() -> Void)? { get set }
    var isPlaying: Bool { get }
    var currentTime: Double { get }
    var duration: Double { get }
    var level: CGFloat { get }
    var isLive: Bool { get }

    @discardableResult
    func prepare(url: URL, isLive: Bool, autoplay: Bool) -> Bool
    func play()
    func pause()
    func seek(to time: Double)
    func setVolume(_ volume: Float)
    /// Per-track levelling, dB. Kept apart from `setVolume` on purpose: the
    /// listener's volume and the track's correction are different facts, and
    /// folding them together would make the slider mean something different
    /// on every track.
    func setLoudnessGain(_ decibels: Double)
    func setRate(_ rate: Float)   // playback speed (podcasts)
    func apply(_ equalizer: EqualizerSettings)
    /// Headphone-correction profile, applied before the user's EQ.
    func applyCorrection(_ profile: CorrectionProfile?)
    func refresh()          // sampled by AudioManager's timer
    func teardown()

    /// Queues the next track so it begins the sample after this one ends.
    /// Returns whether the engine could do it — a format change, a stream, or
    /// an unreadable file all mean "no", and the caller falls back to loading
    /// the track the ordinary way.
    @discardableResult
    func preloadNext(url: URL) -> Bool
    /// Forgets anything queued — the queue changed under us.
    func cancelPreload()
}

extension PlaybackEngine {
    @discardableResult
    func preloadNext(url: URL) -> Bool { false }
    func cancelPreload() {}
    /// Both engines implement this now — the local one through its EQ node's
    /// global gain, the remote one through the stream processing tap — so the
    /// default is only a formality for tests' stub engines.
    func setLoudnessGain(_ decibels: Double) {}
    func applyCorrection(_ profile: CorrectionProfile?) {}
}

// MARK: - Local files
// Graph: playerA ─┐
//                 ├─ blend (AVAudioMixerNode) → EQ → timePitch → mainMixer
//        playerB ─┘
//
// Two player nodes because Crate Mix overlaps two tracks in time. One of
// them is always the *primary* (the track the app calls current); the other
// stands by, silent, until an overlap is scheduled — then it starts at a
// beat-aligned host time, the two cross on an equal-power fade, and the
// roles swap. Gapless stays what it always was: back-to-back segments on
// the primary node alone.

final class LocalAudioEngine: PlaybackEngine {

    var onFinish: (() -> Void)?
    var onAdvancedToNext: (() -> Void)?

    private let engine = AVAudioEngine()
    private let playerA = AVAudioPlayerNode()
    private let playerB = AVAudioPlayerNode()
    private let blend = AVAudioMixerNode()
    /// Which node is the track the app calls current.
    private var primaryIsA = true
    private var primary: AVAudioPlayerNode { primaryIsA ? playerA : playerB }
    private var standby: AVAudioPlayerNode { primaryIsA ? playerB : playerA }
    /// 10 user bands + up to 16 correction slots: 14 for the measured
    /// profile (12 peaks + 2 shelves) plus 2 for the voicing tilt's shelves,
    /// which the composed profile places first so they can never fall off
    /// the prefix. AVAudioUnitEQ's band count is fixed at init, so the
    /// headroom is allocated up front and unused slots stay bypassed.
    private static let correctionSlots = 16
    private let eq = AVAudioUnitEQ(numberOfBands: EqualizerBand.count + LocalAudioEngine.correctionSlots)
    private var correctionPreampDB: Double = 0
    private let timePitch = AVAudioUnitTimePitch()

    private var file: AVAudioFile?
    private var sampleRate: Double = 44_100
    private var totalFrames: AVAudioFramePosition = 0
    /// The file frame the current schedule began at — the base for position.
    private var segmentStartFrame: AVAudioFramePosition = 0
    private var playing = false
    private var volume: Float = 0.75
    private var rate: Float = 1.0
    /// Per-track levelling in dB, and the listener's own pre-amp. The EQ unit
    /// offers a single `globalGain`, so these are summed rather than
    /// overwriting each other.
    private var loudnessGain: Double = 0
    private var preamp: Float = 0
    /// Bumped whenever the node is *stopped* — seek, prepare, teardown — so a
    /// completion callback from the discarded run cannot be mistaken for a
    /// track finishing. It is deliberately not bumped when queueing the next
    /// track, because that schedule must stay valid alongside the current one.
    private var scheduleGeneration = 0
    /// Identifies one scheduled segment within a run.
    private var lastSegmentID = 0
    private var playingSegmentID = 0
    /// The track queued to start the instant this one ends — the whole of
    /// gapless playback.
    private var preloaded: (id: Int, file: AVAudioFile)?
    /// Frames of this uninterrupted run already spent on *earlier* tracks.
    /// The node's clock keeps running across queued segments, so without this
    /// the second track of a gapless pair would report the first track's
    /// elapsed time as its own.
    private var runOffsetFrames: AVAudioFramePosition = 0
    private var lastKnownTime: Double = 0

    /// Written by the render-thread metering tap, read on the main actor.
    private let levelBox = OSAllocatedUnfairLock<Float>(initialState: 0)

    var isLive: Bool { false }
    var isPlaying: Bool { playing }
    var duration: Double { totalFrames > 0 ? Double(totalFrames) / sampleRate : 0.001 }
    private(set) var level: CGFloat = 0

    var currentTime: Double {
        if playing,
           let nodeTime = primary.lastRenderTime,
           let playerTime = primary.playerTime(forNodeTime: nodeTime) {
            let ownFrames = max(0, playerTime.sampleTime - runOffsetFrames)
            let played = Double(ownFrames) / playerTime.sampleRate
            lastKnownTime = min(Double(segmentStartFrame) / sampleRate + played, duration)
        }
        return lastKnownTime
    }

    init() {
        configureBands()
        engine.attach(playerA)
        engine.attach(playerB)
        engine.attach(blend)
        engine.attach(eq)
        engine.attach(timePitch)
    }

    private func configureBands() {
        for (index, band) in eq.bands.enumerated() {
            if index < EqualizerBand.count {
                band.filterType = .parametric
                band.frequency = EqualizerBand.frequencies[index]
                band.bandwidth = 0.5   // octaves
            }
            band.bypass = true
            band.gain = 0
        }
        eq.globalGain = 0
    }

    /// Correction lives in the slots after the user's ten. The remote tap
    /// runs the same profile through exact RBJ shelves; AVAudioUnitEQ's
    /// shelf filters take no Q, so the two paths differ slightly in shelf
    /// slope — a known, inaudible-in-practice seam, documented rather than
    /// hidden.
    func applyCorrection(_ profile: CorrectionProfile?) {
        let slots = EqualizerBand.count..<eq.bands.count
        for index in slots {
            eq.bands[index].bypass = true
            eq.bands[index].gain = 0
        }
        correctionPreampDB = 0
        if let profile, profile.isEnabled {
            correctionPreampDB = profile.preampDB
            for (offset, band) in profile.bands.prefix(Self.correctionSlots).enumerated() {
                let slot = eq.bands[EqualizerBand.count + offset]
                switch band.kind {
                case .peaking:
                    slot.filterType = .parametric
                    // AVAudioUnitEQ wants bandwidth in octaves; convert Q.
                    slot.bandwidth = Float((2 / log(2)) * asinh(1 / (2 * max(band.q, 0.1))))
                case .lowShelf:
                    slot.filterType = .lowShelf
                case .highShelf:
                    slot.filterType = .highShelf
                }
                slot.frequency = Float(min(band.frequency, 20_000))
                slot.gain = Float(band.gainDB)
                slot.bypass = false
            }
        }
        applyGlobalGain()
    }

    // MARK: Transport

    @discardableResult
    func prepare(url: URL, isLive: Bool, autoplay: Bool) -> Bool {
        teardown()
        do {
            let audioFile = try AVAudioFile(forReading: url)
            file = audioFile
            let format = audioFile.processingFormat
            sampleRate = format.sampleRate
            totalFrames = audioFile.length
            segmentStartFrame = 0
            lastKnownTime = 0

            engine.connect(playerA, to: blend, format: format)
            engine.connect(playerB, to: blend, format: format)
            engine.connect(blend, to: eq, format: format)
            engine.connect(eq, to: timePitch, format: format)
            engine.connect(timePitch, to: engine.mainMixerNode, format: format)
            playerA.volume = 1
            playerB.volume = 1
            primaryIsA = true
            engine.mainMixerNode.outputVolume = volume
            timePitch.rate = clampRate(rate)

            installMeterTap()
            engine.prepare()
            try engine.start()

            scheduleFrom(0)
            playing = autoplay
            if autoplay { primary.play() }
            return true
        } catch {
            print("LocalAudioEngine: \(error)")
            file = nil
            return false
        }
    }

    func play() {
        if !engine.isRunning { try? engine.start() }
        primary.play()
        playing = true
    }

    func pause() {
        _ = currentTime            // latch position before the node stops advancing
        // A scheduled overlap fires at a host time; a paused primary would
        // let the incoming track start on top of silence. Cancel honestly —
        // resume re-plans or falls back to the ordinary advance.
        cancelOverlap()
        primary.pause()
        playing = false
    }

    func seek(to time: Double) {
        guard file != nil else { return }
        let wasPlaying = playing
        let clamped = max(0, min(time, duration))
        let startFrame = AVAudioFramePosition(clamped * sampleRate)

        scheduleGeneration += 1
        cancelOverlap()
        primary.stop()
        segmentStartFrame = startFrame
        lastKnownTime = clamped
        scheduleFrom(startFrame)
        if wasPlaying { primary.play(); playing = true }
    }

    func setVolume(_ volume: Float) {
        self.volume = volume
        engine.mainMixerNode.outputVolume = volume
    }

    func setRate(_ rate: Float) {
        self.rate = rate
        timePitch.rate = clampRate(rate)
    }

    func setLoudnessGain(_ decibels: Double) {
        loudnessGain = decibels
        applyGlobalGain()
    }

    func apply(_ equalizer: EqualizerSettings) {
        let bypass = !equalizer.isEnabled
        preamp = bypass ? 0 : equalizer.preamp
        applyGlobalGain()
        for (index, band) in eq.bands.enumerated() where index < EqualizerBand.count {
            band.bypass = bypass
            band.gain = bypass ? 0 : equalizer.gains[index]
        }
    }

    /// Clamped to the unit's own ±24 dB range. Writing the levelling straight
    /// to the node instead would work until the next EQ change silently
    /// undid it.
    private func applyGlobalGain() {
        eq.globalGain = Float(min(max(Double(preamp) + loudnessGain + correctionPreampDB, -24), 24))
    }

    func refresh() {
        guard playing else { return }
        let rms = levelBox.withLock { $0 }
        // Typical music RMS sits around 0.05–0.35; scale into the 0…1 the
        // visualizer expects, then smooth so the bars breathe rather than jitter.
        let normalized = min(1, CGFloat(rms) * 3.2)
        level = level * 0.7 + normalized * 0.3
    }

    func teardown() {
        scheduleGeneration += 1
        cancelOverlap()
        preloaded = nil
        runOffsetFrames = 0
        playerA.stop()
        playerB.stop()
        playerA.volume = 1
        playerB.volume = 1
        primaryIsA = true
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
        file = nil
        playing = false
        level = 0
        levelBox.withLock { $0 = 0 }
    }

    // MARK: Scheduling

    private func scheduleFrom(_ startFrame: AVAudioFramePosition) {
        guard let file else { return }
        // Any queued follow-on belonged to the schedule being replaced.
        preloaded = nil
        runOffsetFrames = 0
        let remaining = AVAudioFrameCount(max(0, totalFrames - startFrame))
        guard remaining > 0 else { return }

        lastSegmentID += 1
        playingSegmentID = lastSegmentID
        schedule(file, from: startFrame, frames: remaining, id: playingSegmentID)
    }

    private func schedule(_ file: AVAudioFile, from startFrame: AVAudioFramePosition,
                          frames: AVAudioFrameCount, id: Int, on node: AVAudioPlayerNode? = nil) {
        let generation = scheduleGeneration
        (node ?? primary).scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: frames,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor in self?.handleCompletion(generation: generation, segment: id) }
        }
    }

    /// Queues the next track behind the current one.
    ///
    /// `AVAudioPlayerNode` renders queued segments back to back with no gap at
    /// all, which is the entire trick — but only while the format stays put,
    /// because the node is connected to the graph with one format. A rate or
    /// channel-count change means the ordinary load path has to run, and the
    /// half-second it costs is honest: the hardware really is being
    /// reconfigured.
    @discardableResult
    func preloadNext(url: URL) -> Bool {
        guard let current = file, preloaded == nil else { return false }
        guard let next = try? AVAudioFile(forReading: url) else { return false }

        let a = current.processingFormat, b = next.processingFormat
        guard a.sampleRate == b.sampleRate,
              a.channelCount == b.channelCount,
              a.commonFormat == b.commonFormat else { return false }

        let frames = AVAudioFrameCount(next.length)
        guard frames > 0 else { return false }

        lastSegmentID += 1
        preloaded = (id: lastSegmentID, file: next)
        schedule(next, from: 0, frames: frames, id: lastSegmentID)
        return true
    }

    // MARK: Overlap (Crate Mix part two)

    /// One planned crossing between the primary and the standby player.
    struct OverlapRequest {
        var url: URL
        /// Seconds into the outgoing track when the incoming one starts —
        /// already snapped to the outgoing beat grid by the planner.
        var startInOutgoing: Double
        /// Seconds into the incoming file to start from (its first beat).
        var incomingOffset: Double
        /// Equal-power fade length in seconds (16 or 4 outgoing beats).
        var fadeDuration: Double
    }

    private var overlap: (file: AVAudioFile, request: OverlapRequest,
                          segmentID: Int, fire: DispatchWorkItem)?
    private var fadeTimer: Timer?

    /// Schedules the incoming track to start, beat-aligned, while this one
    /// is still playing. Returns false when the moment is too close, the
    /// formats disagree, or a gapless preload already owns the ending — the
    /// caller falls back to the ordinary path, honestly.
    @discardableResult
    func scheduleOverlap(_ request: OverlapRequest) -> Bool {
        guard let current = file, overlap == nil, preloaded == nil, playing else { return false }
        guard let next = try? AVAudioFile(forReading: request.url) else { return false }
        let a = current.processingFormat, b = next.processingFormat
        guard a.sampleRate == b.sampleRate, a.channelCount == b.channelCount else { return false }

        let lead = request.startInOutgoing - currentTime
        guard lead > 0.35, request.startInOutgoing + 0.25 < duration else { return false }

        let offsetFrames = AVAudioFramePosition(request.incomingOffset * b.sampleRate)
        let frames = AVAudioFrameCount(max(0, next.length - offsetFrames))
        guard frames > 0 else { return false }

        lastSegmentID += 1
        let segmentID = lastSegmentID
        standby.stop()
        standby.volume = 0
        schedule(next, from: offsetFrames, frames: frames, id: segmentID, on: standby)

        // Sample-true start: the incoming first beat lands on an outgoing
        // beat instant. Host time is the one clock both nodes share.
        let startHost = AVAudioTime.hostTime(forSeconds:
            AVAudioTime.seconds(forHostTime: mach_absolute_time()) + lead)
        standby.play(at: AVAudioTime(hostTime: startHost))

        let fire = DispatchWorkItem { [weak self] in self?.beginCrossing() }
        overlap = (next, request, segmentID, fire)
        DispatchQueue.main.asyncAfter(deadline: .now() + lead, execute: fire)
        return true
    }

    /// The moment the incoming track becomes the current one: swap roles,
    /// hand the app its advance, and drive the equal-power fade. The
    /// *alignment* was fixed earlier by `play(at:)`; this only moves volume
    /// and bookkeeping, so main-queue jitter cannot smear the beat.
    private func beginCrossing() {
        guard let (nextFile, request, segmentID, _) = overlap else { return }
        overlap = nil

        let outgoing = primary
        primaryIsA.toggle()

        file = nextFile
        totalFrames = nextFile.length
        sampleRate = nextFile.processingFormat.sampleRate
        segmentStartFrame = AVAudioFramePosition(request.incomingOffset * sampleRate)
        runOffsetFrames = 0
        lastKnownTime = request.incomingOffset
        playingSegmentID = segmentID
        preloaded = nil
        onAdvancedToNext?()

        let incoming = primary
        let fadeSeconds = max(0.3, request.fadeDuration)
        let started = CACurrentMediaTime()
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            let x = min(1, (CACurrentMediaTime() - started) / fadeSeconds)
            // Equal-power: the crossing keeps constant perceived energy.
            incoming.volume = Float(sin(x * .pi / 2))
            outgoing.volume = Float(cos(x * .pi / 2))
            if x >= 1 {
                timer.invalidate()
                outgoing.stop()
                outgoing.volume = 1
                Task { @MainActor in self?.fadeTimer = nil }
            }
        }
    }

    /// Forgets a planned crossing: the standby stops, volumes restore, and
    /// the ordinary end-of-track path takes over.
    private func cancelOverlap() {
        overlap?.fire.cancel()
        overlap = nil
        fadeTimer?.invalidate()
        fadeTimer = nil
        standby.stop()
        standby.volume = 1
        primary.volume = 1
    }

    var hasScheduledOverlap: Bool { overlap != nil }

    func cancelPreload() {
        // The scheduled segment cannot be un-queued without stopping the node,
        // which would break the gapless join we are protecting. Dropping the
        // reference is enough: when the current track ends, the completion
        // finds nothing queued and reports a finish, and `AudioManager` loads
        // whatever the queue now says — the extra audio is stopped by that
        // load, not heard.
        preloaded = nil
    }

    private func handleCompletion(generation: Int, segment: Int) {
        // A completion from a discarded run (we stopped to seek) means nothing.
        guard generation == scheduleGeneration, playing else { return }
        guard segment == playingSegmentID else { return }

        if let next = preloaded {
            // The node is already rendering the queued track: nothing to
            // start, only bookkeeping to catch up.
            runOffsetFrames += max(0, totalFrames - segmentStartFrame)
            file = next.file
            totalFrames = next.file.length
            sampleRate = next.file.processingFormat.sampleRate
            segmentStartFrame = 0
            lastKnownTime = 0
            playingSegmentID = next.id
            preloaded = nil
            onAdvancedToNext?()
            return
        }

        playing = false
        onFinish?()
    }

    // MARK: Metering

    private func installMeterTap() {
        let mixer = engine.mainMixerNode
        mixer.removeTap(onBus: 0)
        let format = mixer.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { return }
        // Install from a nonisolated context: AVAudioEngine invokes the tap on
        // its realtime render thread, and a closure built here in @MainActor
        // scope would trap Swift 6's executor check the instant audio flows.
        Self.installMeterTap(on: mixer, format: format, into: levelBox)
    }

    nonisolated private static func installMeterTap(
        on mixer: AVAudioMixerNode,
        format: AVAudioFormat,
        into levelBox: OSAllocatedUnfairLock<Float>
    ) {
        mixer.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            let samples = channels[0]
            var sum: Float = 0
            for frame in 0..<frames {
                let sample = samples[frame]
                sum += sample * sample
            }
            let rms = (sum / Float(frames)).squareRoot()
            levelBox.withLock { $0 = rms }
        }
    }

    private func clampRate(_ rate: Float) -> Float {
        min(2.0, max(0.5, rate))
    }
}

// MARK: - Live stream state

/// What a live stream is honestly doing right now. Four states, no more:
/// the moment between tuning and the first audio (`connecting`), a stall in
/// the middle of the air (`buffering`), audio flowing (`onAir`), and a
/// connection that died (`dropped`). There is deliberately no `paused` —
/// a live stream cannot be paused, only tuned out of, and that fact belongs
/// to the transport, not to the stream.
enum LiveStreamState: Equatable {
    case connecting
    case buffering
    case onAir
    case dropped
}

/// Pulls a display title out of an ICY `StreamTitle` value, or nothing.
///
/// At file scope on purpose, and pure on purpose: it can be tested as
/// arithmetic, and it never guesses. Stations send real "Artist - Title"
/// strings, empty strings, bare separators, and ad-tag URLs down the same
/// pipe — everything that isn't a title becomes `nil`, and `nil` is rendered
/// as no line at all rather than as a placeholder.
func parseStreamTitle(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    // A separator with nothing on either side ("-", " - ") is ICY's way of
    // sending nothing.
    if trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "-–—· ")).isEmpty { return nil }
    // A bare URL is an ad marker or a stream id, not a track.
    let lowered = trimmed.lowercased()
    if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") { return nil }
    return trimmed
}

/// Receives timed ICY metadata from AVFoundation and forwards the raw
/// StreamTitle string.
///
/// A separate object rather than the engine itself: the engine is pinned to
/// the main actor by its protocol, and `AVPlayerItemMetadataOutput` calls its
/// delegate from whatever queue it was handed — the callback must not carry
/// an actor's isolation stamp (the StreamProcessingTap C callbacks earned
/// that rule the hard way).
private final class LiveMetadataRelay: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    let onStreamTitle: @Sendable (String?) -> Void
    init(onStreamTitle: @escaping @Sendable (String?) -> Void) {
        self.onStreamTitle = onStreamTitle
    }

    nonisolated func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                                    didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                                    from track: AVPlayerItemTrack?) {
        let raw = groups.flatMap(\.items)
            .first { $0.identifier == .icyMetadataStreamTitle }?
            .stringValue
        onStreamTitle(raw)
    }
}

// MARK: - Network streams & live radio (AVPlayer)

final class RemoteAudioEngine: NSObject, PlaybackEngine {
    var onFinish: (() -> Void)?
    /// Never called: AVPlayer item transitions are not gapless, so the remote
    /// engine always reports a plain finish and lets the app load the next
    /// track.
    var onAdvancedToNext: (() -> Void)?
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var playing = false
    private var live = false
    private var volume: Float = 0.75
    private var rate: Float = 1.0
    private(set) var level: CGFloat = 0

    /// The EQ + loudness processor for AVPlayer content. Attached per item;
    /// reports whether it actually landed so the UI can tell the truth.
    private let tap = StreamProcessingTap()
    private var equalizer = EqualizerSettings()
    private var loudnessGainDB: Double = 0
    /// Forwarded to AudioManager: true while the current stream is actually
    /// being processed (progressive HTTP yes, HLS no).
    var onProcessingChange: ((Bool) -> Void)? {
        get { tap.onAttachChange }
        set { tap.onAttachChange = newValue }
    }

    // MARK: Live stream facts

    /// Fired on every honest change of the live stream's state. Low-frequency;
    /// AudioManager republishes it for the radio screen.
    var onLiveStateChange: ((LiveStreamState) -> Void)?
    /// The parsed, deduplicated ICY now-playing title — or nil when the
    /// station stops sending one. Never fired twice with the same value.
    var onLiveMetadata: ((String?) -> Void)?

    private(set) var liveStreamState: LiveStreamState = .connecting
    private var liveURL: URL?
    private var livePausedAt: Date?
    private var lastStreamTitle: String?
    private var timeControlObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var stallObserver: NSObjectProtocol?
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var metadataRelay: LiveMetadataRelay?
    private var dropCountdown: Task<Void, Never>?

    /// How long a stall may buffer before it is called what it is. Injectable
    /// so the transition can be tested without eight wall-clock seconds.
    var liveDropTimeout: TimeInterval = 8
    /// A live pause longer than this resumes at the live edge, not from a
    /// protracted buffer — resuming stale audio and calling it live would be
    /// a lie. Injectable for the same reason as the timeout.
    var liveResumeThreshold: TimeInterval = 5
    /// The clock the pause bookkeeping reads. Tests replace it instead of
    /// sleeping through real seconds.
    var nowProvider: () -> Date = Date.init

    #if DEBUG
    /// Puts the engine in live mode without touching AVFoundation, so the
    /// state machine and the ICY dedup can be exercised as arithmetic.
    func enterLiveModeForTesting() {
        live = true
        liveStreamState = .connecting
    }
    var currentItemForTesting: AVPlayerItem? { player?.currentItem }
    #endif

    var isLive: Bool { live }
    var isPlaying: Bool { playing }

    var currentTime: Double {
        let t = player?.currentTime().seconds ?? 0
        return t.isFinite ? t : 0
    }

    var duration: Double {
        guard let d = player?.currentItem?.duration.seconds, d.isFinite, d > 0 else {
            return live ? 0 : 1
        }
        return d
    }

    @discardableResult
    func prepare(url: URL, isLive: Bool, autoplay: Bool) -> Bool {
        teardown()
        live = isLive
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain   // natural voice at higher speeds
        let p = AVPlayer(playerItem: item)
        p.volume = volume
        player = p
        // The curve must be in the DSP before the first buffer, not after:
        // a stream that opens flat and snaps into shape a second later is
        // exactly the kind of seam a listener notices once and distrusts.
        tap.dsp.update(settings: equalizer, loudnessGainDB: loudnessGainDB)
        MainActor.assumeIsolated { tap.attach(to: item) }
        attachItemObservers(to: item)
        if live {
            liveURL = url
            livePausedAt = nil
            lastStreamTitle = nil
            liveStreamState = .connecting
            onLiveStateChange?(.connecting)
            observeLivePlayer(p)
        }
        if autoplay { play() }
        return true
    }

    /// Everything watched on one specific item — reattached whenever the item
    /// is rebuilt for a live-edge rejoin, torn down with it.
    private func attachItemObservers(to item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            // Posted on .main by the queue above, so this is already the
            // main actor — assert it instead of hopping and losing ordering.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.playing = false
                if self.live {
                    // A live stream has no end; reaching one means the
                    // connection died. That is a fact about this station —
                    // it must never advance the queue to the next one.
                    self.transitionLive(to: .dropped)
                } else {
                    self.onFinish?()
                }
            }
        }
        guard live else { return }

        // Timed ICY metadata: what the station says it is playing right now.
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        let relay = LiveMetadataRelay { [weak self] raw in
            Task { @MainActor in self?.ingestStreamTitle(raw) }
        }
        output.setDelegate(relay, queue: .main)
        item.add(output)
        metadataOutput = output
        metadataRelay = relay

        itemStatusObservation = Self.observeStatus(of: item) { [weak self] in
            Task { @MainActor in self?.handleLiveItemFailed() }
        }
        stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleLiveStall() }
        }
    }

    /// The player-level observation survives item rebuilds; only teardown
    /// removes it.
    private func observeLivePlayer(_ player: AVPlayer) {
        timeControlObservation = Self.observeTimeControl(of: player) { [weak self] status in
            Task { @MainActor in self?.handleTimeControl(status) }
        }
    }

    // KVO handlers are built from a nonisolated context on purpose: a closure
    // born inside a main-actor method carries the actor's isolation check, and
    // AVFoundation delivers KVO from whatever thread it likes — the same trap
    // the stream tap's C callbacks sprang once already. The handlers hop to
    // the main actor through a Task instead of asserting an executor.
    nonisolated private static func observeTimeControl(
        of player: AVPlayer,
        onChange: @escaping @Sendable (AVPlayer.TimeControlStatus) -> Void
    ) -> NSKeyValueObservation {
        player.observe(\.timeControlStatus, options: [.new]) { player, _ in
            onChange(player.timeControlStatus)
        }
    }

    nonisolated private static func observeStatus(
        of item: AVPlayerItem,
        onFailure: @escaping @Sendable () -> Void
    ) -> NSKeyValueObservation {
        item.observe(\.status, options: [.new]) { item, _ in
            guard item.status == .failed else { return }
            onFailure()
        }
    }

    private func removeItemObservers() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let stallObserver {
            NotificationCenter.default.removeObserver(stallObserver)
            self.stallObserver = nil
        }
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        metadataOutput = nil
        metadataRelay = nil
    }

    // MARK: Live state machine

    /// One door for every state change: deduplicates, cancels a pending drop
    /// countdown when the stream recovers, and reports outward.
    func transitionLive(to state: LiveStreamState) {
        guard live, state != liveStreamState else { return }
        liveStreamState = state
        if state != .buffering {
            dropCountdown?.cancel()
            dropCountdown = nil
        }
        onLiveStateChange?(state)
    }

    func handleTimeControl(_ status: AVPlayer.TimeControlStatus) {
        guard live else { return }
        switch status {
        case .playing:
            transitionLive(to: .onAir)
        case .waitingToPlayAtSpecifiedRate:
            // The first wait is the connection being made; any later wait is
            // the middle of the air falling out.
            guard liveStreamState != .connecting, liveStreamState != .dropped else { return }
            transitionLive(to: .buffering)
            beginDropCountdown()
        case .paused:
            break   // the listener's stop, or a teardown — not the stream's state
        @unknown default:
            break
        }
    }

    func handleLiveStall() {
        guard live, playing else { return }
        transitionLive(to: .buffering)
        beginDropCountdown()
    }

    func handleLiveItemFailed() {
        guard live else { return }
        playing = false
        transitionLive(to: .dropped)
    }

    /// A stall that outlives the timeout stops being a buffer and becomes a
    /// lost signal. Sleep-based rather than polled; the injected timeout is
    /// what tests shrink.
    private func beginDropCountdown() {
        dropCountdown?.cancel()
        let timeout = liveDropTimeout
        dropCountdown = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, let self,
                  self.live, self.liveStreamState == .buffering else { return }
            self.playing = false
            self.transitionLive(to: .dropped)
        }
    }

    /// Parse, dedupe, report. The station repeats its StreamTitle with every
    /// metadata interval; the app only cares when it actually changes.
    func ingestStreamTitle(_ raw: String?) {
        guard live else { return }
        let title = parseStreamTitle(raw)
        guard title != lastStreamTitle else { return }
        lastStreamTitle = title
        onLiveMetadata?(title)
    }

    // MARK: Live resume

    /// Tuning back in. An `AVPlayer` resumed after a long live pause plays
    /// the protracted buffer — minutes-old audio presented as the air. Past
    /// the threshold (or after a drop) the item is rebuilt from the same URL,
    /// which is what actually rejoins the live edge; the tap and the metadata
    /// output ride the new item.
    private func rejoinLiveEdgeIfStale() {
        guard live, let url = liveURL else { return }
        let stale: Bool
        if liveStreamState == .dropped {
            stale = true
        } else if let pausedAt = livePausedAt {
            stale = nowProvider().timeIntervalSince(pausedAt) > liveResumeThreshold
        } else {
            stale = false
        }
        livePausedAt = nil
        guard stale, let player else { return }

        removeItemObservers()
        MainActor.assumeIsolated { tap.detach() }
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain
        tap.dsp.update(settings: equalizer, loudnessGainDB: loudnessGainDB)
        MainActor.assumeIsolated { tap.attach(to: item) }
        attachItemObservers(to: item)
        lastStreamTitle = nil
        liveStreamState = .connecting
        onLiveStateChange?(.connecting)
        player.replaceCurrentItem(with: item)
    }

    func play() {
        if live { rejoinLiveEdgeIfStale() }
        playing = true
        // Setting rate resumes playback; live streams always play at 1×.
        player?.rate = live ? 1.0 : rate
    }

    func pause() {
        if live { livePausedAt = nowProvider() }
        player?.pause()
        playing = false
    }

    func seek(to time: Double) {
        guard !live else { return }
        player?.seek(to: CMTime(seconds: max(0, time), preferredTimescale: 600))
    }

    func setVolume(_ volume: Float) { self.volume = volume; player?.volume = volume }

    func setRate(_ rate: Float) {
        self.rate = rate
        if playing && !live { player?.rate = rate }
    }

    func apply(_ equalizer: EqualizerSettings) {
        self.equalizer = equalizer
        tap.dsp.update(settings: equalizer, loudnessGainDB: loudnessGainDB)
    }

    func applyCorrection(_ profile: CorrectionProfile?) {
        tap.dsp.updateCorrection(profile)
    }

    func setLoudnessGain(_ decibels: Double) {
        loudnessGainDB = decibels
        tap.dsp.update(settings: equalizer, loudnessGainDB: decibels)
    }

    func refresh() {
        guard playing else { level = 0; return }
        let measured = tap.dsp.drainLevel()
        if tap.isAttached, measured > 0 {
            // The real level, measured in the tap — same scaling and smoothing
            // as the local engine, so the meter doesn't change personality
            // when the source does.
            let normalized = min(1, CGFloat(measured) * 3.2)
            level = level * 0.55 + normalized * 0.45
        } else {
            // No tap on this stream (HLS): synthesise a gentle level rather
            // than freeze the meter — but only then.
            let t = CACurrentMediaTime()
            let synthetic = 0.45 + 0.22 * sin(t * 3.1) + 0.12 * sin(t * 7.3)
            level = level * 0.6 + CGFloat(synthetic) * 0.4
        }
    }

    func teardown() {
        removeItemObservers()
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        dropCountdown?.cancel()
        dropCountdown = nil
        liveURL = nil
        livePausedAt = nil
        lastStreamTitle = nil
        liveStreamState = .connecting
        MainActor.assumeIsolated { tap.detach() }
        player?.pause()
        player = nil
        playing = false
        level = 0
    }
}
