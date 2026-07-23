//
//  EqualizerTests.swift
//  SonavaTests
//
//  The EQ model is pure and feeds an audio unit that traps on a bad gain, so
//  its clamping and persistence are worth pinning down.
//

import Testing
import Foundation
@testable import Sonava

struct EqualizerSettingsTests {

    @Test("A fresh curve is flat, disabled and named Flat")
    func defaultsAreFlat() {
        let settings = EqualizerSettings()
        #expect(settings.gains == Array(repeating: 0, count: EqualizerBand.count))
        #expect(settings.isEnabled == false)
        #expect(settings.presetID == EqualizerPreset.flat.id)
    }

    @Test("Gains are clamped to ±12 dB so the audio unit never sees a bad value")
    func gainsClamp() {
        var settings = EqualizerSettings()
        settings.setGain(999, at: 0)
        settings.setGain(-999, at: 1)
        #expect(settings.gains[0] == EqualizerSettings.gainLimit)
        #expect(settings.gains[1] == -EqualizerSettings.gainLimit)
    }

    @Test("A non-finite gain is treated as zero, not passed through")
    func rejectsNonFinite() {
        var settings = EqualizerSettings()
        settings.setGain(.nan, at: 0)
        settings.setGain(.infinity, at: 1)
        #expect(settings.gains[0] == 0)
        #expect(settings.gains[1] == 0)
    }

    @Test("An out-of-range band index is ignored")
    func ignoresBadIndex() {
        var settings = EqualizerSettings()
        settings.setGain(6, at: 99)
        settings.setGain(6, at: -1)
        #expect(settings.gains == Array(repeating: 0, count: EqualizerBand.count))
    }

    @Test("Editing a band detaches from the named preset")
    func editingClearsPreset() {
        var settings = EqualizerSettings()
        settings.apply(.rock)
        #expect(settings.presetID == "rock")

        settings.setGain(1, at: 4)
        #expect(settings.presetID == nil)
    }

    @Test("Editing back onto a preset's exact curve re-adopts its name")
    func editingOntoPresetReadopts() {
        var settings = EqualizerSettings()
        settings.apply(.bassBoost)
        settings.setGain(0, at: 0)          // now off-preset
        #expect(settings.presetID == nil)

        settings.setGain(EqualizerPreset.bassBoost.gains[0], at: 0)   // back onto it
        #expect(settings.presetID == "bass")
    }

    @Test("Applying a preset copies its whole curve and pre-amp")
    func applyPreset() {
        var settings = EqualizerSettings()
        settings.apply(.electronic)
        #expect(settings.gains == EqualizerPreset.electronic.gains)
        #expect(settings.preamp == EqualizerPreset.electronic.preamp)
        #expect(settings.presetID == "electronic")
    }

    @Test("A curve survives a JSON round trip")
    func codableRoundTrip() throws {
        var settings = EqualizerSettings()
        settings.apply(.jazz)
        settings.isEnabled = true

        let decoded = try JSONDecoder().decode(
            EqualizerSettings.self,
            from: JSONEncoder().encode(settings)
        )
        #expect(decoded == settings)
    }

    @Test("A corrupt file — wrong length, wild values — is repaired on decode")
    func decodeRepairsBadData() throws {
        let json = #"{"gains":[99,-99],"preamp":500,"isEnabled":true,"presetID":"nope"}"#
        let decoded = try JSONDecoder().decode(EqualizerSettings.self, from: Data(json.utf8))

        #expect(decoded.gains.count == EqualizerBand.count)          // padded back to length
        #expect(decoded.gains[0] == EqualizerSettings.gainLimit)     // clamped
        #expect(decoded.gains[1] == -EqualizerSettings.gainLimit)
        #expect(decoded.preamp == EqualizerSettings.gainLimit)
        #expect(decoded.gains.allSatisfy { abs($0) <= EqualizerSettings.gainLimit })
    }
}

struct EqualizerPresetTests {

    @Test("Every preset has one gain per band")
    func presetsAreWellFormed() {
        for preset in EqualizerPreset.all {
            #expect(preset.gains.count == EqualizerBand.count, "\(preset.id) has \(preset.gains.count) gains")
        }
    }

    @Test("Preset gains are within the allowed range")
    func presetGainsInRange() {
        for preset in EqualizerPreset.all {
            for gain in preset.gains {
                #expect(abs(gain) <= EqualizerSettings.gainLimit, "\(preset.id) has \(gain) dB")
            }
            #expect(abs(preset.preamp) <= EqualizerSettings.gainLimit)
        }
    }

    @Test("Preset ids are unique")
    func idsAreUnique() {
        let ids = EqualizerPreset.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Flat is genuinely flat — the honest bypass curve")
    func flatIsFlat() {
        #expect(EqualizerPreset.flat.gains.allSatisfy { $0 == 0 })
        #expect(EqualizerPreset.flat.preamp == 0)
    }

    @Test("Band frequency labels are compact", arguments: [
        (Float(32), "32"), (Float(1_000), "1k"), (Float(16_000), "16k"),
    ])
    func frequencyLabels(frequency: Float, expected: String) {
        #expect(EqualizerBand.label(for: frequency) == expected)
    }
}

@MainActor
struct AudioEffectsTests {

    private func freshEffects() -> AudioEffects {
        let store = JSONFileStore<EqualizerSettings>("eq-test-\(UUID().uuidString).json", default: EqualizerSettings())
        return AudioEffects(store: store)
    }

    @Test("Toggling enabled is published and persisted")
    func enablePersists() {
        let store = JSONFileStore<EqualizerSettings>("eq-persist-test.json", default: EqualizerSettings())
        store.write(EqualizerSettings())

        let effects = AudioEffects(store: store)
        effects.setEnabled(true)
        #expect(effects.equalizer.isEnabled)

        // A second store over the same file sees the change.
        #expect(AudioEffects(store: store).equalizer.isEnabled)
    }

    @Test("Selecting a preset updates the published curve")
    func applyPresetPublishes() {
        let effects = freshEffects()
        effects.apply(.vocal)
        #expect(effects.selectedPreset?.id == "vocal")
        #expect(effects.equalizer.gains == EqualizerPreset.vocal.gains)
    }

    @Test("Reset returns to flat")
    func resetIsFlat() {
        let effects = freshEffects()
        effects.apply(.rock)
        effects.reset()
        #expect(effects.selectedPreset?.id == "flat")
    }

    @Test("A manual band edit clears the selected preset")
    func manualEditClearsSelection() {
        let effects = freshEffects()
        effects.apply(.pop)
        effects.setGain(10, at: 9)
        #expect(effects.selectedPreset == nil)
    }
}
