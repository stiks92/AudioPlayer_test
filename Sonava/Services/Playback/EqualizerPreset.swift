//
//  EqualizerPreset.swift
//  Sonava
//
//  Named EQ curves. Gains are in dB per band, low → high, matching
//  `EqualizerBand.frequencies`.
//

import Foundation

struct EqualizerPreset: Identifiable, Equatable, Sendable {
    let id: String
    /// English name; the UI wraps it in `LocalizedStringKey` so it translates.
    let name: String
    let gains: [Float]
    let preamp: Float

    init(id: String, name: String, gains: [Float], preamp: Float = 0) {
        self.id = id
        self.name = name
        self.gains = gains
        self.preamp = preamp
    }
}

extension EqualizerPreset {

    //                                      32   64  125  250  500   1k   2k   4k   8k  16k
    static let flat = EqualizerPreset(id: "flat", name: "Flat",
        gains: [0,   0,   0,   0,   0,   0,   0,   0,   0,   0])

    static let bassBoost = EqualizerPreset(id: "bass", name: "Bass Boost",
        gains: [6,   5,   4,   2,   0,   0,   0,   0,   0,   0], preamp: -2)

    static let bassReducer = EqualizerPreset(id: "bass-cut", name: "Bass Reducer",
        gains: [-6,  -5,  -4,  -2,   0,   0,   0,   0,   0,   0])

    static let vocal = EqualizerPreset(id: "vocal", name: "Vocal Boost",
        gains: [-2,  -2,  -1,   1,   3,   4,   4,   3,   1,   0])

    static let treble = EqualizerPreset(id: "treble", name: "Treble Boost",
        gains: [0,   0,   0,   0,   0,   1,   2,   4,   5,   6], preamp: -2)

    static let rock = EqualizerPreset(id: "rock", name: "Rock",
        gains: [5,   4,   3,   1,  -1,  -1,   1,   3,   4,   5], preamp: -2)

    static let pop = EqualizerPreset(id: "pop", name: "Pop",
        gains: [-1,   0,   2,   4,   4,   3,   1,   0,  -1,  -1])

    static let jazz = EqualizerPreset(id: "jazz", name: "Jazz",
        gains: [3,   2,   1,   2,  -1,  -1,   0,   1,   2,   3])

    static let classical = EqualizerPreset(id: "classical", name: "Classical",
        gains: [4,   3,   2,   0,   0,   0,  -1,  -1,   2,   3])

    static let electronic = EqualizerPreset(id: "electronic", name: "Electronic",
        gains: [5,   4,   1,   0,  -1,   1,   0,   1,   4,   5], preamp: -2)

    static let hipHop = EqualizerPreset(id: "hiphop", name: "Hip-Hop",
        gains: [6,   5,   2,   3,  -1,  -1,   1,  -1,   2,   3], preamp: -2)

    static let lounge = EqualizerPreset(id: "lounge", name: "Lounge",
        gains: [-2,  -1,   0,   2,   3,   1,   0,  -1,   1,   0])

    static let podcast = EqualizerPreset(id: "podcast", name: "Spoken Word",
        gains: [-4,  -3,  -1,   2,   4,   4,   3,   2,   0,  -2])

    /// Every preset, in the order the picker shows them. Flat first.
    static let all: [EqualizerPreset] = [
        flat, bassBoost, bassReducer, vocal, treble,
        rock, pop, jazz, classical, electronic, hipHop, lounge, podcast,
    ]

    static func preset(id: String?) -> EqualizerPreset? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}
