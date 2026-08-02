//
//  LoudnessStore.swift
//  Sonava
//
//  Remembers how loud each track is, so the analysis happens once.
//
//  The scope is deliberately narrow and stated out loud in Settings: files
//  the listener owns, tracks they downloaded, and server tracks whose
//  ReplayGain tag the server publishes. A live radio stream cannot be
//  analysed before it plays, and an `AVPlayer` stream cannot be re-gained
//  without an audio tap — so those play at their own level, and the app says
//  so rather than implying a levelling it isn't doing.
//
//  This is a free feature. It is not a Pro trick or a "sound suite" upsell:
//  a queue that jumps fifteen decibels between a 1978 transfer and a modern
//  master is a defect, and charging to fix a defect is how apps earn the
//  reviews this whole roadmap is trying to avoid.
//

import Foundation
import Combine

@MainActor
final class LoudnessStore: ObservableObject {

    /// Whether levelling is applied at all. On by default: the listener who
    /// wants raw levels is rarer than the one reaching for the volume knob.
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: enabledKey) }
    }

    private let enabledKey: String
    private let store: JSONFileStore<[String: LoudnessAnalyzer.Measurement]>
    private var measurements: [String: LoudnessAnalyzer.Measurement] = [:]
    private var inFlight: Set<String> = []

    /// The file and defaults key are injectable so tests get their own — they
    /// run in parallel, and a shared cache means one case wipes another's
    /// fixture halfway through.
    init(store: JSONFileStore<[String: LoudnessAnalyzer.Measurement]> =
            JSONFileStore("loudness.json", default: [:]),
         enabledKey: String = "loudness.enabled.v1") {
        self.store = store
        self.enabledKey = enabledKey
        isEnabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
        measurements = store.read()
    }

    /// The gain to apply to this track right now, in dB.
    ///
    /// Zero means "play it as it is", which is the answer for anything not
    /// yet measured — playback never waits for analysis.
    func gain(for song: Song, fileURL: URL?) -> Double {
        guard isEnabled else { return 0 }
        if let measured = measurements[song.id] { return measured.gain }

        // A server that publishes ReplayGain has already done the work.
        if let tag = song.replayGain {
            let measurement = LoudnessAnalyzer.Measurement(
                loudness: LoudnessAnalyzer.referenceLUFS - LoudnessAnalyzer.gain(fromReplayGain: tag),
                gain: LoudnessAnalyzer.gain(fromReplayGain: tag))
            measurements[song.id] = measurement
            store.write(measurements)
            return measurement.gain
        }

        // Otherwise measure it — in the background, for next time. The track
        // playing now stays at its own level rather than lurching when the
        // analysis lands mid-song.
        if let fileURL, fileURL.isFileURL { analyse(song.id, at: fileURL) }
        return 0
    }

    /// True when this track's level is known — what the UI needs to avoid
    /// claiming levelling it hasn't measured.
    func isMeasured(_ song: Song) -> Bool { measurements[song.id] != nil }

    func measurement(for song: Song) -> LoudnessAnalyzer.Measurement? {
        measurements[song.id]
    }

    /// Analyses ahead of time — used when a download finishes, so the track
    /// is already levelled the first time it plays.
    func prepare(_ song: Song, fileURL: URL) {
        guard isEnabled, measurements[song.id] == nil, song.replayGain == nil else { return }
        analyse(song.id, at: fileURL)
    }

    private func analyse(_ id: String, at url: URL) {
        guard !inFlight.contains(id) else { return }
        inFlight.insert(id)
        Task.detached(priority: .utility) {
            // Off the main actor: reading a 60 MB FLAC in 400 ms blocks is
            // hundreds of milliseconds of arithmetic.
            let measured = LoudnessAnalyzer.analyse(url: url)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.inFlight.remove(id)
                guard let measured else { return }
                self.measurements[id] = measured
                self.trim()
                self.store.write(self.measurements)
            }
        }
    }

    /// A library of 30,000 tracks would otherwise grow this file without
    /// limit. The cache is an optimisation, not a record — a dropped entry
    /// costs one re-analysis.
    private func trim() {
        guard measurements.count > 5_000 else { return }
        measurements = Dictionary(uniqueKeysWithValues: measurements.suffix(4_000))
    }

    #if DEBUG
    func setMeasurementForTesting(_ measurement: LoudnessAnalyzer.Measurement, id: String) {
        measurements[id] = measurement
    }
    #endif
}
