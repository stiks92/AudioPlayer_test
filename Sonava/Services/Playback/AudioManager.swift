//
//  AudioManager.swift
//  Sonava
//
//  The playback engine orchestrator. Manages the queue / shuffle / repeat,
//  delegates actual audio to a LocalAudioEngine (bundled files) or a
//  RemoteAudioEngine (network streams & radio), drives the visualizer level,
//  and integrates with the system Now Playing controls & lock screen.
//

import SwiftUI
import UIKit
import AVFoundation
import MediaPlayer
import QuartzCore
import Combine

@MainActor
final class AudioManager: NSObject, ObservableObject {

    static let shared = AudioManager()

    // MARK: - Published state

    @Published private(set) var currentSong: Song?
    /// The colours of the sleeve that is actually playing, read from the
    /// artwork's pixels (see `ArtworkPalette`) — nil while extraction is in
    /// flight or when the track has no art, in which case views fall back to
    /// the song's stored pair. This is what makes the app's light honest: the
    /// room takes the record's colour, never a template's.
    @Published private(set) var sleeveHex: [UInt]?
    @Published private(set) var isPlaying = false
    @Published private(set) var queue: [Song] = []
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var isShuffling = false
    @Published var volume: Float = 0.75 {
        didSet { activeEngine?.setVolume(volume) }
    }
    @Published private(set) var playbackRate: Float = 1.0

    /// Live time/level updates — observed only by Now Playing / mini / lyrics.
    let clock = PlaybackClock()

    /// The equalizer, shared with the EQ screen. Owned here so its curve is
    /// pushed to whichever engine is active.
    let effects = AudioEffects()

    /// Optional taste bias for endless autoplay. Set by the app so extending
    /// the queue drifts toward what the listener likes.
    var tasteProfile: TasteProfile = .init(topArtists: [])

    /// Offline downloads, shared with the UI. Resolved ahead of the stream URL
    /// so a saved track plays with no network.
    let downloads = DownloadStore()

    var isLive: Bool { currentSong?.isLive ?? false }

    /// Speed control is only meaningful for spoken-word content (podcasts).
    var supportsPlaybackRate: Bool { currentSong?.source == .podcast }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        activeEngine?.setRate(rate)
    }

    // MARK: - Private

    private let localEngine = LocalAudioEngine()
    private let remoteEngine = RemoteAudioEngine()
    private var activeEngine: PlaybackEngine?
    private var timer: Timer?
    private var baseQueue: [Song] = []
    private var currentIndex = 0

    // Endless autoplay — keep the music going by extending the queue with
    // related tracks as it nears the end.
    @Published var autoExtendEnabled: Bool = UserDefaults.standard.object(forKey: "autoextend.v1") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoExtendEnabled, forKey: "autoextend.v1") }
    }
    private var isExtending = false
    private var effectsCancellable: AnyCancellable?

    // Resume last session
    private let resumeSongKey = "resume.song.v1"
    private let resumePositionKey = "resume.position.v1"
    private var lastPersist = Date.distantPast

    // Listening time accounting (feeds the stats screen)
    private var listenSession = UUID()
    private var listenSeconds: Double = 0
    /// Timestamp of the last accrual, or `nil` while paused — so time spent
    /// paused is never counted as time listened.
    private var listenReference: CFTimeInterval?
    private var lastListenReport: Double = 0
    private static let listenReportInterval: Double = 15

    // Sleep timer
    @Published private(set) var sleepTimerMinutes: Int?
    private var sleepTimer: Timer?
    private var sleepFireDate: Date?

    var sleepRemaining: TimeInterval? {
        guard let sleepFireDate else { return nil }
        return max(0, sleepFireDate.timeIntervalSinceNow)
    }

    private override init() {
        super.init()
        configureSession()
        setupRemoteCommands()

        // Reshape the live engine whenever the EQ curve changes.
        effectsCancellable = effects.$equalizer
            .sink { [weak self] settings in self?.activeEngine?.apply(settings) }

        // Re-read the sleeve whenever the *track* changes (not on every
        // republish of the same song — hence the id-based dedup).
        sleeveCancellable = $currentSong
            .removeDuplicates { $0?.id == $1?.id }
            .sink { [weak self] song in self?.refreshSleeve(for: song) }
    }

    // MARK: - Sleeve colour

    private var sleeveCancellable: AnyCancellable?
    private var sleeveTask: Task<Void, Never>?
    /// Session cache so returning to a track doesn't re-decode its art.
    private var sleeveCache: [String: [UInt]] = [:]

    private func refreshSleeve(for song: Song?) {
        sleeveTask?.cancel()
        guard let song else { sleeveHex = nil; return }
        if let cached = sleeveCache[song.id] { sleeveHex = cached; return }
        sleeveHex = nil
        guard let url = song.artworkURL else { return }
        let id = song.id
        sleeveTask = Task { [weak self] in
            // `ArtworkPalette.load` is nonisolated-async, so the decode runs
            // off the main actor; only the publish below hops back here.
            guard let hex = await ArtworkPalette.load(from: url), !Task.isCancelled else { return }
            guard let self, self.currentSong?.id == id else { return }
            if self.sleeveCache.count > 128 { self.sleeveCache.removeAll() }
            self.sleeveCache[id] = hex
            self.sleeveHex = hex
        }
    }

    // MARK: - Public transport

    /// Starts playback of `song`, using `context` as the surrounding queue.
    func play(_ song: Song, in context: [Song]) {
        baseQueue = context
        if isShuffling {
            let rest = context.filter { $0 != song }.shuffled()
            queue = [song] + rest
            currentIndex = 0
        } else {
            queue = context
            currentIndex = context.firstIndex(of: song) ?? 0
        }
        load(autoplay: true)
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard activeEngine != nil else { return }
        activeEngine?.play()
        isPlaying = true
        startTimer()
        updateNowPlayingInfo()
    }

    func pause() {
        activeEngine?.pause()
        isPlaying = false
        accrueListenTime()      // bank the final slice before the clock stops
        stopTimer()
        reportListen()
        updateNowPlayingInfo()
    }

    /// Stops playback and clears the queue.
    ///
    /// Used when the current track stops being available — deleting a file the
    /// player is still playing would otherwise leave the mini player advertising
    /// something that no longer exists.
    func stop() {
        accrueListenTime()
        stopTimer()
        reportListen()
        activeEngine?.teardown()
        activeEngine = nil
        isPlaying = false
        currentSong = nil
        queue = []
        baseQueue = []
        currentIndex = 0
        clock.reset(duration: 1)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func next() {
        advance(auto: false)
    }

    func previous() {
        if !isLive && clock.currentTime > 3 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty else { return }
        currentIndex = currentIndex > 0 ? currentIndex - 1 : queue.count - 1
        load(autoplay: true)
    }

    func seek(to time: Double) {
        guard !isLive else { return }
        activeEngine?.seek(to: time)
        clock.currentTime = min(max(0, time), clock.duration)
        updateNowPlayingInfo()
    }

    /// Jump straight to a specific song already inside the queue.
    func playFromQueue(_ song: Song) {
        guard let idx = queue.firstIndex(of: song) else { return }
        currentIndex = idx
        load(autoplay: true)
    }

    // MARK: - Queue editing

    /// Tracks after the current one.
    var upNext: [Song] {
        let start = currentIndex + 1
        guard start < queue.count else { return [] }
        return Array(queue[start...])
    }

    func playNext(_ song: Song) {
        guard !queue.isEmpty else { play(song, in: [song]); return }
        queue.insert(song, at: min(currentIndex + 1, queue.count))
        Haptics.selection()
    }

    func addToQueue(_ song: Song) {
        guard !queue.isEmpty else { play(song, in: [song]); return }
        queue.append(song)
        Haptics.selection()
    }

    func removeUpNext(at offsets: IndexSet) {
        let base = currentIndex + 1
        let absolute = IndexSet(offsets.map { base + $0 }.filter { $0 < queue.count })
        queue.remove(atOffsets: absolute)
    }

    func moveUpNext(from source: IndexSet, to destination: Int) {
        let base = currentIndex + 1
        guard base <= queue.count else { return }
        var sub = Array(queue[base...])
        sub.move(fromOffsets: source, toOffset: destination)
        queue.replaceSubrange(base..<queue.count, with: sub)
    }

    // MARK: - Modes

    func cycleRepeat() {
        repeatMode = repeatMode.next
    }

    func toggleShuffle() {
        isShuffling.toggle()
        guard let current = currentSong else { return }
        if isShuffling {
            let rest = baseQueue.filter { $0 != current }.shuffled()
            queue = [current] + rest
            currentIndex = 0
        } else {
            queue = baseQueue
            currentIndex = queue.firstIndex(of: current) ?? 0
        }
    }

    // MARK: - Loading

    /// Called when a track finishes playing naturally — the signal for
    /// scrobbling a completed listen. Not fired on manual skips.
    var onTrackCompleted: ((Song) -> Void)?

    // MARK: - Listening time

    /// Reports how long the current track has actually been heard, paused time
    /// excluded. Called on a slow cadence and again when the track changes,
    /// always with the same `session` for one continuous listen — so the
    /// receiver updates that listen in place instead of double-counting it.
    var onListenProgress: ((Song, Double, UUID) -> Void)?

    /// Banks the elapsed slice since the last accrual and reports it if enough
    /// time has passed. Cheap, so it can run on the sampling timer.
    private func accrueListenTime() {
        let now = CACurrentMediaTime()
        defer { listenReference = now }
        guard let reference = listenReference else { return }
        // Clamp the slice: a suspended app or a stalled stream must not credit
        // the listener with hours they never heard.
        listenSeconds += min(max(0, now - reference), 1)
        if listenSeconds - lastListenReport >= Self.listenReportInterval { reportListen() }
    }

    private func reportListen() {
        guard let song = currentSong, listenSeconds > lastListenReport else { return }
        lastListenReport = listenSeconds
        onListenProgress?(song, listenSeconds, listenSession)
    }

    /// Persists the in-flight listen. Called when the app leaves the foreground,
    /// where it may be suspended without another timer tick.
    func flushListeningTime() {
        accrueListenTime()
        reportListen()
    }

    private func beginListenSession() {
        reportListen()          // close out the outgoing track first
        listenSession = UUID()
        listenSeconds = 0
        lastListenReport = 0
        listenReference = nil
    }

    private func advance(auto: Bool) {
        guard !queue.isEmpty else { return }
        if auto, let finished = currentSong {
            onTrackCompleted?(finished)
        }
        if auto && repeatMode == .one {
            seek(to: 0)
            play()
            return
        }
        if currentIndex + 1 < queue.count {
            currentIndex += 1
            load(autoplay: true)
        } else if repeatMode == .off && auto {
            currentIndex = 0
            load(autoplay: false)
        } else {
            currentIndex = 0
            load(autoplay: true)
        }
    }

    private func load(autoplay: Bool) {
        guard queue.indices.contains(currentIndex) else { return }
        let song = queue[currentIndex]
        beginListenSession()        // closes out the outgoing track's listen
        currentSong = song

        // Prefer an offline copy — it plays with no network and, being a file,
        // runs through the local engine (so it gets the equalizer too).
        guard let url = downloads.localURL(for: song) ?? song.url else {
            print("AudioManager: missing URL for \(song.id)")
            return
        }

        // Local files and downloaded tracks use the AVAudioEngine backend;
        // live streams use AVPlayer.
        let engine: PlaybackEngine = url.isFileURL ? localEngine : remoteEngine
        if activeEngine !== engine { activeEngine?.teardown() }
        activeEngine = engine
        engine.onFinish = { [weak self] in
            Task { @MainActor in self?.advance(auto: true) }
        }
        engine.setVolume(volume)
        engine.apply(effects.equalizer)

        // `isFileURL` is the same test that picks the engine, so the meter's
        // honesty and the engine's capability can never drift apart.
        clock.reset(duration: song.isLive ? 0 : 1, metered: url.isFileURL)

        // Speed persists across podcast episodes but resets for music/radio.
        if song.source != .podcast { playbackRate = 1.0 }

        let ok = engine.prepare(url: url, isLive: song.isLive, autoplay: autoplay)
        if ok {
            engine.setRate(playbackRate)
            isPlaying = autoplay
            // Publish the real duration immediately — the scrubber shouldn't wait
            // for the first timer tick, and a paused track never ticks at all.
            if !song.isLive {
                let d = engine.duration
                if d.isFinite, d > 0 { clock.duration = d }
            }
            if autoplay { startTimer() } else { stopTimer() }
        } else {
            isPlaying = false
            stopTimer()
        }
        updateNowPlayingInfo()
        persistNowPlaying(force: true)
        maybeExtendQueue()
    }

    // MARK: - Endless autoplay

    /// When the queue nears its end, append related tracks so playback
    /// continues seamlessly. Skipped for radio/podcasts and repeat modes.
    private func maybeExtendQueue() {
        guard autoExtendEnabled, !isExtending,
              repeatMode == .off,
              let song = currentSong,
              !song.isLive, song.source != .podcast,
              currentIndex >= queue.count - 2 else { return }
        isExtending = true
        Task { @MainActor in
            defer { isExtending = false }
            let more = await StationService.station(for: song, taste: tasteProfile)
            let existing = Set(queue.map(\.id))
            let fresh = more.filter { !existing.contains($0.id) }
            guard !fresh.isEmpty else { return }
            queue.append(contentsOf: fresh)
        }
    }

    // MARK: - Resume last session

    private func persistNowPlaying(force: Bool) {
        guard let song = currentSong, !song.isLive else { return }
        if !force && Date().timeIntervalSince(lastPersist) < 5 { return }
        lastPersist = Date()
        if let data = try? JSONEncoder().encode(song) {
            UserDefaults.standard.set(data, forKey: resumeSongKey)
        }
        UserDefaults.standard.set(clock.currentTime, forKey: resumePositionKey)
    }

    /// Reload the last played track (paused) so the mini player is ready on launch.
    func restoreLastSession() {
        guard currentSong == nil,
              let data = UserDefaults.standard.data(forKey: resumeSongKey),
              let song = try? JSONDecoder().decode(Song.self, from: data) else { return }
        let position = UserDefaults.standard.double(forKey: resumePositionKey)
        queue = [song]
        currentIndex = 0
        load(autoplay: false)
        if position > 1 { seek(to: position) }
    }

    // MARK: - Sleep timer

    func setSleepTimer(minutes: Int?) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerMinutes = minutes
        guard let minutes, minutes > 0 else {
            sleepFireDate = nil
            return
        }
        let interval = Double(minutes) * 60
        sleepFireDate = Date().addingTimeInterval(interval)
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.sleepTimerFired() }
        }
        RunLoop.main.add(t, forMode: .common)
        sleepTimer = t
    }

    private func sleepTimerFired() {
        pause()
        setSleepTimer(minutes: nil)
    }

    // MARK: - Session & remote

    private func configureSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudioManager: session error \(error)")
        }
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let song = currentSong else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: clock.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: song.isLive
        ]
        if !song.isLive {
            info[MPMediaItemPropertyPlaybackDuration] = clock.duration
        }
        // Lock-screen art comes from the track's extracted cover file, if it
        // has one. Remote covers aren't fetched synchronously here.
        if let cover = song.artworkURL, cover.isFileURL,
           let image = UIImage(contentsOfFile: cover.path) {
            info[MPMediaItemPropertyArtwork] = Self.artwork(for: image)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// MediaPlayer invokes the artwork request handler on an arbitrary thread.
    /// Building it here — outside the main actor — keeps the closure
    /// non-isolated, so Swift 6's executor check doesn't trap when the lock
    /// screen asks for the image off the main thread.
    private nonisolated static func artwork(for image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    // MARK: - Sampling timer

    private func startTimer() {
        stopTimer()
        listenReference = CACurrentMediaTime()
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        listenReference = nil       // paused time is not listening time
    }

    private func tick() {
        guard let engine = activeEngine else { return }
        accrueListenTime()
        engine.refresh()
        clock.currentTime = engine.currentTime
        let d = engine.duration
        clock.duration = (d.isFinite && d > 0) ? d : (isLive ? 0 : 1)
        clock.audioLevel = engine.level
        persistNowPlaying(force: false)
    }
}
