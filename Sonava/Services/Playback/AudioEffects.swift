//
//  AudioEffects.swift
//  Sonava
//
//  The single source of truth for the equalizer. The UI binds to it; the
//  playback engine observes it and reshapes its audio unit live. Persisted so
//  the curve survives relaunches.
//

import Foundation
import Combine

@MainActor
final class AudioEffects: ObservableObject {

    @Published private(set) var equalizer: EqualizerSettings {
        didSet { store.write(equalizer) }
    }

    private let store: JSONFileStore<EqualizerSettings>

    init(store: JSONFileStore<EqualizerSettings> = JSONFileStore("equalizer.json", default: EqualizerSettings())) {
        self.store = store
        self.equalizer = store.read()
    }

    // MARK: - Intent

    func setEnabled(_ enabled: Bool) {
        equalizer.isEnabled = enabled
    }

    func setGain(_ gain: Float, at index: Int) {
        equalizer.setGain(gain, at: index)
    }

    func setPreamp(_ preamp: Float) {
        equalizer.preamp = min(max(preamp, -EqualizerSettings.gainLimit), EqualizerSettings.gainLimit)
    }

    func apply(_ preset: EqualizerPreset) {
        equalizer.apply(preset)
    }

    func reset() {
        equalizer.apply(.flat)
    }

    /// The currently selected preset, or `nil` after a manual edit.
    var selectedPreset: EqualizerPreset? {
        EqualizerPreset.preset(id: equalizer.presetID)
    }
}
