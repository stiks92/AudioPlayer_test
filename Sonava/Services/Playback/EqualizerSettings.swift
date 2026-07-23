//
//  EqualizerSettings.swift
//  Sonava
//
//  A plain, Codable value describing the EQ curve. Deliberately free of any
//  AVFoundation type so it can be persisted, diffed and unit-tested without an
//  audio engine — the engine reads it, it does not own it.
//

import Foundation

/// The ten ISO octave-band centre frequencies, low to high.
enum EqualizerBand {
    static let frequencies: [Float] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    static let count = frequencies.count

    /// A short label for a frequency: "32", "1k", "16k".
    static func label(for frequency: Float) -> String {
        frequency >= 1_000
            ? "\(Int(frequency / 1_000))k"
            : "\(Int(frequency))"
    }
}

struct EqualizerSettings: Codable, Equatable, Sendable {

    /// Gain per band in dB, clamped to ±`gainLimit`. Always `EqualizerBand.count` long.
    private(set) var gains: [Float]
    /// Overall pre-amp in dB, applied on top of the per-band gains.
    var preamp: Float
    /// Whether the curve is applied at all. Off means a clean bypass.
    var isEnabled: Bool
    /// The preset this curve came from, or `nil` once the user edits a band.
    private(set) var presetID: String?

    static let gainLimit: Float = 12

    init(
        gains: [Float] = Array(repeating: 0, count: EqualizerBand.count),
        preamp: Float = 0,
        isEnabled: Bool = false,
        presetID: String? = EqualizerPreset.flat.id
    ) {
        self.gains = Self.normalize(gains)
        self.preamp = Self.clamp(preamp)
        self.isEnabled = isEnabled
        self.presetID = presetID
    }

    // MARK: - Editing

    /// Sets one band's gain. Doing so detaches from any named preset, because
    /// the curve is no longer that preset.
    mutating func setGain(_ gain: Float, at index: Int) {
        guard gains.indices.contains(index) else { return }
        gains[index] = Self.clamp(gain)
        presetID = matchingPreset()?.id
    }

    /// Adopts a preset wholesale.
    mutating func apply(_ preset: EqualizerPreset) {
        gains = Self.normalize(preset.gains)
        preamp = Self.clamp(preset.preamp)
        presetID = preset.id
    }

    // MARK: - Guards

    /// Keeps a decoded curve honest: right length, every value in range. A
    /// hand-edited or corrupt file cannot feed the audio unit a bad gain.
    private static func normalize(_ gains: [Float]) -> [Float] {
        var result = Array(gains.prefix(EqualizerBand.count)).map(clamp)
        if result.count < EqualizerBand.count {
            result.append(contentsOf: Array(repeating: 0, count: EqualizerBand.count - result.count))
        }
        return result
    }

    private static func clamp(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, -gainLimit), gainLimit)
    }

    /// The preset whose curve exactly matches the current one, if any — so an
    /// edit that happens to land back on a preset re-adopts its name.
    private func matchingPreset() -> EqualizerPreset? {
        EqualizerPreset.all.first { preset in
            preset.gains == gains && preset.preamp == preamp
        }
    }

    // MARK: - Codable resilience

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawGains = try container.decodeIfPresent([Float].self, forKey: .gains) ?? []
        gains = Self.normalize(rawGains)
        preamp = Self.clamp(try container.decodeIfPresent(Float.self, forKey: .preamp) ?? 0)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        presetID = try container.decodeIfPresent(String.self, forKey: .presetID)
    }
}
