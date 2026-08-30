//
//  VoicingTilt.swift
//  Sonava
//
//  Stage 1.5 of the Backroom: voicing — two gentle shelves the listener can
//  tilt on top of the measured correction, or run on their own.
//
//  This is deliberately NOT a new DSP mechanism. A tilt is expressed in the
//  same `CorrectionBand` language the correction profile speaks, and rides
//  the very same static RBJ cascade on both playback paths (AVAudioUnitEQ
//  slots for files, the processing tap's biquads for streams). Static EQ
//  only, by design and by the patent gate: nothing here listens to the
//  signal, the playback level, or the hour of the day — the coefficients are
//  a pure function of two knob positions.
//

import Foundation

/// A bass/treble tilt in dB: a low shelf near 105 Hz and a high shelf near
/// 2.5 kHz — the two handles that move a headphone between "studio flat"
/// and "the curve most listeners actually prefer".
struct VoicingTilt: Codable, Equatable, Hashable, Sendable {

    var bassDB: Double
    var trebleDB: Double

    /// Shelf corners. The bass corner follows the convention AutoEq's own
    /// target curves use for their low-shelf tilt; the treble corner sits
    /// where "brightness" starts being heard as such.
    static let bassShelfFrequency: Double = 105
    static let trebleShelfFrequency: Double = 2_500
    static let bassRange: ClosedRange<Double> = -6...6
    static let trebleRange: ClosedRange<Double> = -6...6
    /// RBJ's gentle default slope — the same Q the profile parser assumes
    /// when a shelf line omits one.
    static let shelfQ: Double = 0.707

    init(bassDB: Double = 0, trebleDB: Double = 0) {
        self.bassDB = Self.clamp(bassDB, to: Self.bassRange)
        self.trebleDB = Self.clamp(trebleDB, to: Self.trebleRange)
    }

    /// Both knobs at rest — audibly identical to no tilt at all.
    var isNeutral: Bool { abs(bassDB) < 0.05 && abs(trebleDB) < 0.05 }

    /// The tilt in the correction cascade's own language. A resting knob
    /// contributes no band: a unity filter costs cycles and does nothing.
    var bands: [CorrectionBand] {
        var bands: [CorrectionBand] = []
        if abs(bassDB) >= 0.05 {
            bands.append(CorrectionBand(kind: .lowShelf,
                                        frequency: Self.bassShelfFrequency,
                                        gainDB: bassDB, q: Self.shelfQ))
        }
        if abs(trebleDB) >= 0.05 {
            bands.append(CorrectionBand(kind: .highShelf,
                                        frequency: Self.trebleShelfFrequency,
                                        gainDB: trebleDB, q: Self.shelfQ))
        }
        return bands
    }

    /// Static headroom so a boosted shelf cannot clip full-scale material —
    /// the same negative-preamp convention AutoEq exports carry. A constant
    /// derived from the knob positions, never from the signal.
    var preampDB: Double { -max(0, bassDB, trebleDB) }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: Codable resilience

    private enum CodingKeys: String, CodingKey { case bassDB, trebleDB }

    /// A hand-edited or corrupt file cannot feed the cascade a wild gain:
    /// everything decodes through the clamping initialiser.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(bassDB: (try? container.decode(Double.self, forKey: .bassDB)) ?? 0,
                  trebleDB: (try? container.decode(Double.self, forKey: .trebleDB)) ?? 0)
    }
}

/// Named tilts, in the app's own words. `name` is the English catalogue key;
/// the UI wraps it in `LocalizedStringKey` — the `EqualizerPreset` pattern.
struct VoicingPreset: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let tilt: VoicingTilt

    static let flat = VoicingPreset(id: "flat", name: "Flat", tilt: VoicingTilt())

    static let warm = VoicingPreset(id: "warm", name: "Warm",
                                    tilt: VoicingTilt(bassDB: 3, trebleDB: -2))

    static let bright = VoicingPreset(id: "bright", name: "Bright",
                                      tilt: VoicingTilt(bassDB: -1.5, trebleDB: 3))

    /// In the spirit of the published preference-curve tilt — roughly a
    /// +6 dB low shelf near 105 Hz with a slightly relaxed top. The word on
    /// screen is ours; the curve reference lives only in this comment.
    static let deep = VoicingPreset(id: "deep", name: "Deep",
                                    tilt: VoicingTilt(bassDB: 6, trebleDB: -1.5))

    static let all: [VoicingPreset] = [.flat, .warm, .bright, .deep]

    /// The preset a tilt exactly equals, if any — so a slider that lands
    /// back on a named curve re-adopts its name, like the equalizer does.
    static func matching(_ tilt: VoicingTilt) -> VoicingPreset? {
        all.first { $0.tilt == tilt }
    }
}
