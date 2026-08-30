//
//  VoicingTests.swift
//  SonavaTests
//
//  Stage 1.5 of the Backroom: the voicing tilt and the A/B switch.
//
//  Three regimes, matching how the feature can be wrong: the *model* (a
//  preset must mean exactly the shelves it claims), the *composition* (the
//  cascade the engines run must be profile + tilt, with bypass killing all
//  of it), and the *filter arithmetic* in decibels through the same
//  `EqualizerDSP` both stream playback and the correction tests already
//  trust. Store tests write their own files under injected names — store
//  files outlive runs and suites run in parallel.
//

import Foundation
import Testing
@testable import Sonava

// MARK: - The tilt model

struct VoicingTiltModelTests {

    @Test func presetsMapToTheDocumentedShelves() {
        // Flat is the absence of a tilt, not a tilt of zero-gain bands.
        #expect(VoicingPreset.flat.tilt.isNeutral)
        #expect(VoicingPreset.flat.tilt.bands.isEmpty)

        let warm = VoicingPreset.warm.tilt
        #expect(warm.bassDB == 3 && warm.trebleDB == -2)

        let bright = VoicingPreset.bright.tilt
        #expect(bright.bassDB == -1.5 && bright.trebleDB == 3)

        let deep = VoicingPreset.deep.tilt
        #expect(deep.bassDB == 6 && deep.trebleDB == -1.5)

        // The bands speak the correction cascade's language exactly.
        let bands = deep.bands
        #expect(bands.count == 2)
        #expect(bands[0].kind == .lowShelf)
        #expect(bands[0].frequency == VoicingTilt.bassShelfFrequency)
        #expect(bands[0].gainDB == 6)
        #expect(bands[0].q == VoicingTilt.shelfQ)
        #expect(bands[1].kind == .highShelf)
        #expect(bands[1].frequency == VoicingTilt.trebleShelfFrequency)
        #expect(bands[1].gainDB == -1.5)
    }

    @Test func aRestingKnobContributesNoBand() {
        let bassOnly = VoicingTilt(bassDB: 4, trebleDB: 0)
        #expect(bassOnly.bands.count == 1)
        #expect(bassOnly.bands[0].kind == .lowShelf)

        let trebleOnly = VoicingTilt(bassDB: 0, trebleDB: -3)
        #expect(trebleOnly.bands.count == 1)
        #expect(trebleOnly.bands[0].kind == .highShelf)
    }

    @Test func preampGivesHeadroomForBoostsOnly() {
        // Static compensation, the AutoEq convention: a boost costs its own
        // gain in headroom; a pure cut costs nothing.
        #expect(VoicingTilt(bassDB: 6, trebleDB: -1.5).preampDB == -6)
        #expect(VoicingTilt(bassDB: -4, trebleDB: -2).preampDB == 0)
        #expect(VoicingTilt(bassDB: 2, trebleDB: 3).preampDB == -3)
    }

    @Test func initClampsToTheShelfRanges() {
        let wild = VoicingTilt(bassDB: 40, trebleDB: -40)
        #expect(wild.bassDB == VoicingTilt.bassRange.upperBound)
        #expect(wild.trebleDB == VoicingTilt.trebleRange.lowerBound)
        #expect(VoicingTilt(bassDB: .nan, trebleDB: .infinity) == VoicingTilt())
    }

    @Test func serializationRoundTripsAndDecodesDefensively() throws {
        let tilt = VoicingTilt(bassDB: 3.5, trebleDB: -2.5)
        let data = try JSONEncoder().encode(tilt)
        #expect(try JSONDecoder().decode(VoicingTilt.self, from: data) == tilt)

        // A hand-edited file cannot smuggle a wild gain past the decoder.
        let hostile = Data(#"{"bassDB": 400, "trebleDB": "loud"}"#.utf8)
        let decoded = try JSONDecoder().decode(VoicingTilt.self, from: hostile)
        #expect(decoded.bassDB == VoicingTilt.bassRange.upperBound)
        #expect(decoded.trebleDB == 0)
    }

    @Test func slidersLandingOnAPresetReadoptItsName() {
        #expect(VoicingPreset.matching(VoicingTilt(bassDB: 3, trebleDB: -2)) == .warm)
        #expect(VoicingPreset.matching(VoicingTilt()) == .flat)
        #expect(VoicingPreset.matching(VoicingTilt(bassDB: 1, trebleDB: 1)) == nil)
    }
}

// MARK: - Composition: what the engines actually run

@MainActor
struct VoicingCompositionTests {

    private var profile: CorrectionProfile {
        CorrectionProfile(name: "HD 650", preampDB: -6.4, bands: [
            CorrectionBand(kind: .peaking, frequency: 1_350, gainDB: 3.1, q: 1.41),
            CorrectionBand(kind: .highShelf, frequency: 10_000, gainDB: -4.2, q: 0.7),
        ])
    }

    @Test func profilePlusTiltIsOneCascadeTiltFirst() {
        let tilt = VoicingPreset.deep.tilt
        let composed = CorrectionStore.effective(
            profile: profile, tilt: tilt, isPro: true, isBypassed: false)

        #expect(composed != nil)
        guard let composed else { return }
        // Tilt shelves first — the local engine's fixed slot count truncates
        // from the tail, and the tail must be the profile's, never the tilt.
        #expect(Array(composed.bands.prefix(2)) == tilt.bands)
        #expect(Array(composed.bands.dropFirst(2)) == profile.bands)
        // Preamps sum: the profile's own headroom plus the tilt's.
        #expect(abs(composed.preampDB - (-6.4 + tilt.preampDB)) < 0.001)
    }

    @Test func tiltWorksWithoutAProfile() {
        let composed = CorrectionStore.effective(
            profile: nil, tilt: VoicingPreset.warm.tilt, isPro: true, isBypassed: false)
        #expect(composed?.bands == VoicingPreset.warm.tilt.bands)
        #expect(composed?.preampDB == VoicingPreset.warm.tilt.preampDB)
    }

    @Test func neutralTiltLeavesTheProfileUntouched() {
        let composed = CorrectionStore.effective(
            profile: profile, tilt: VoicingTilt(), isPro: true, isBypassed: false)
        #expect(composed == profile, "a resting tilt must not rewrite the profile")
    }

    @Test func aDisabledProfileStillCarriesTheTilt() {
        var off = profile
        off.isEnabled = false
        let composed = CorrectionStore.effective(
            profile: off, tilt: VoicingPreset.deep.tilt, isPro: true, isBypassed: false)
        #expect(composed?.bands == VoicingPreset.deep.tilt.bands)
    }

    @Test func bypassSilencesEverything() {
        let composed = CorrectionStore.effective(
            profile: profile, tilt: VoicingPreset.deep.tilt, isPro: true, isBypassed: true)
        #expect(composed == nil, "A/B must hand the engines nothing at all")
    }

    @Test func nothingToRunMeansNil() {
        #expect(CorrectionStore.effective(
            profile: nil, tilt: VoicingTilt(), isPro: true, isBypassed: false) == nil)
    }
}

// MARK: - The store

@MainActor
struct VoicingStoreTests {

    private let filename = "voicing-store-test.json"
    private let tiltFilename = "voicing-store-test-tilt.json"

    /// Writes its own fixtures first, under its own names — the parallel-run
    /// hygiene every store test in this suite follows.
    private func fresh() -> CorrectionStore {
        JSONFileStore<CorrectionProfile?>(filename, default: nil).write(nil)
        JSONFileStore<VoicingTilt>(tiltFilename, default: VoicingTilt()).write(VoicingTilt())
        return CorrectionStore(filename: filename, tiltFilename: tiltFilename)
    }

    @Test func tiltPersistsBesideTheProfile() {
        let store = fresh()
        store.setTilt(VoicingTilt(bassDB: 3, trebleDB: -2))

        let reopened = CorrectionStore(filename: filename, tiltFilename: tiltFilename)
        #expect(reopened.tilt == VoicingTilt(bassDB: 3, trebleDB: -2))
    }

    @Test func setTiltRenormalisesWildValues() {
        let store = fresh()
        var wild = VoicingTilt()
        wild.bassDB = 99          // direct mutation skips the clamping init…
        store.setTilt(wild)       // …the store must not
        #expect(store.tilt.bassDB == VoicingTilt.bassRange.upperBound)
    }

    @Test func bypassIsAToolNotASetting() {
        let store = fresh()
        store.setTilt(VoicingPreset.deep.tilt)
        store.isPro = true
        store.setBypassed(true)
        #expect(store.effectiveProfile == nil)

        // A relaunch must never silently resume "off".
        let reopened = CorrectionStore(filename: filename, tiltFilename: tiltFilename)
        #expect(reopened.isBypassed == false)
        // And the comparison never touched what it was comparing.
        #expect(reopened.tilt == VoicingPreset.deep.tilt)
    }
}

// MARK: - The filter arithmetic, in decibels

/// The tilt through the same `EqualizerDSP` the streams run — deterministic
/// sine-in, dB-out, the CorrectionTests regime. (The live `LocalAudioEngine`
/// deliberately gets only a does-not-trap test: under a full parallel run
/// its buffers are the machine's mood, a lesson this suite already paid for.)
struct VoicingDSPTests {

    private func sine(frequency: Double, sampleRate: Double, frames: Int) -> [Float] {
        (0..<frames).map { Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    private func rms(_ samples: ArraySlice<Float>) -> Float {
        sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
    }

    private func gainDB(of dsp: EqualizerDSP, at frequency: Double) -> Float {
        var buffer = sine(frequency: frequency, sampleRate: 48_000, frames: 19_200)
        let reference = rms(buffer[(buffer.count / 2)...])
        buffer.withUnsafeMutableBufferPointer { pointer in
            dsp.process(pointer.baseAddress!, frames: pointer.count, channel: 0, stride: 1)
        }
        return 20 * log10(rms(buffer[(buffer.count / 2)...]) / reference)
    }

    private func dsp(running profile: CorrectionProfile?) -> EqualizerDSP {
        let dsp = EqualizerDSP()
        dsp.configure(sampleRate: 48_000, channels: 2)
        dsp.update(settings: EqualizerSettings(), loudnessGainDB: 0)
        dsp.updateCorrection(profile)
        return dsp
    }

    @Test func deepTiltMovesTheSpectrumTheWayItClaims() {
        // The deep voicing (+6 bass shelf, −1.5 treble shelf), no profile —
        // built through the same composition the engines receive.
        let composed = CorrectionProfile(
            name: "t", preampDB: VoicingPreset.deep.tilt.preampDB,
            bands: VoicingPreset.deep.tilt.bands)

        // Absolute gains include the −6 dB headroom preamp, so the honest
        // assertions are *relative*: bass against mids, top against mids.
        let low = gainDB(of: dsp(running: composed), at: 40)
        let mid = gainDB(of: dsp(running: composed), at: 500)
        let top = gainDB(of: dsp(running: composed), at: 10_000)

        #expect(abs((low - mid) - 6) < 1.0,
                "40 Hz should sit ~6 dB above the mids, reads \(low - mid)")
        #expect(abs((top - mid) + 1.5) < 1.0,
                "10 kHz should sit ~1.5 dB below the mids, reads \(top - mid)")
    }

    @Test func brightTiltLiftsTheTopInstead() {
        let composed = CorrectionProfile(
            name: "t", preampDB: VoicingPreset.bright.tilt.preampDB,
            bands: VoicingPreset.bright.tilt.bands)
        let mid = gainDB(of: dsp(running: composed), at: 500)
        let top = gainDB(of: dsp(running: composed), at: 10_000)
        #expect((top - mid) > 2, "a bright voicing must audibly lift the top, reads \(top - mid)")
    }

    @Test func clearingTheCascadeIsTrueBypass() {
        // What the A/B switch actually does to the DSP: effective → nil.
        let engine = dsp(running: CorrectionProfile(
            name: "t", preampDB: VoicingPreset.deep.tilt.preampDB,
            bands: VoicingPreset.deep.tilt.bands))
        engine.updateCorrection(nil)
        let residual = gainDB(of: engine, at: 40)
        #expect(abs(residual) < 0.05, "bypass must return to unity, reads \(residual)")
    }
}
