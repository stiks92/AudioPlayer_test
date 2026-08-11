//
//  CorrectionTests.swift
//  SonavaTests
//
//  Headphone correction: the parser against real-world AutoEq exports, and
//  the shelf/cascade DSP in decibels — same regime as StreamEQTests, because
//  a correction that is silently wrong is worse than none: the listener
//  trusts it precisely because it claims to be measured.
//

import Foundation
import Testing
@testable import Sonava

struct CorrectionTests {

    // MARK: - Parser

    private let realExport = """
    Preamp: -6.4 dB
    Filter 1: ON PK Fc 105 Hz Gain -2.4 dB Q 0.70
    Filter 2: ON PK Fc 1350 Hz Gain 3.1 dB Q 1.41
    Filter 3: ON LSC Fc 105 Hz Gain 4.0 dB Q 0.70
    Filter 4: ON HSC Fc 10000 Hz Gain -4.2 dB Q 0.70
    """

    @Test func parsesARealParametricExport() {
        let profile = CorrectionProfileParser.parse(realExport, name: "HD 650")
        #expect(profile != nil)
        guard let profile else { return }
        #expect(profile.preampDB == -6.4)
        #expect(profile.bands.count == 4)
        #expect(profile.bands[0].kind == .peaking && profile.bands[0].frequency == 105)
        #expect(profile.bands[2].kind == .lowShelf)
        #expect(profile.bands[3].kind == .highShelf && profile.bands[3].gainDB == -4.2)
    }

    @Test func survivesDecimalCommasAndCase() {
        // A file that travelled through a Russian spreadsheet.
        let text = """
        PREAMP: -5,1 dB
        FILTER 1: ON PK FC 250 Hz GAIN 2,5 dB Q 1,20
        """
        let profile = CorrectionProfileParser.parse(text, name: "x")
        #expect(profile?.preampDB == -5.1)
        #expect(profile?.bands.first?.gainDB == 2.5)
        #expect(profile?.bands.first?.q == 1.2)
    }

    @Test func garbageIsRefusedNotGuessed() {
        #expect(CorrectionProfileParser.parse("hello world", name: "x") == nil)
        #expect(CorrectionProfileParser.parse("", name: "x") == nil)
    }

    @Test func implausibleGainIsRefused() {
        let text = """
        Preamp: 0 dB
        Filter 1: ON PK Fc 100 Hz Gain 40 dB Q 0.7
        """
        #expect(CorrectionProfileParser.parse(text, name: "troll") == nil,
                "a +40 dB band is a typo or a troll, not a filter to run")
    }

    @Test func disabledFiltersAreSkipped() {
        let text = """
        Preamp: -2 dB
        Filter 1: ON PK Fc 100 Hz Gain 2 dB Q 0.7
        Filter 2: OFF PK Fc 200 Hz Gain 5 dB Q 0.7
        """
        #expect(CorrectionProfileParser.parse(text, name: "x")?.bands.count == 1)
    }

    // MARK: - Shelf DSP, in decibels

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

    private func dsp(with profile: CorrectionProfile) -> EqualizerDSP {
        let dsp = EqualizerDSP()
        dsp.configure(sampleRate: 48_000, channels: 2)
        dsp.update(settings: EqualizerSettings(), loudnessGainDB: 0)
        dsp.updateCorrection(profile)
        return dsp
    }

    @Test func lowShelfLiftsTheBassAndLeavesTheMids() {
        let profile = CorrectionProfile(name: "t", preampDB: 0, bands: [
            CorrectionBand(kind: .lowShelf, frequency: 100, gainDB: 6, q: 0.707)
        ])
        let low = gainDB(of: dsp(with: profile), at: 40)
        let mid = gainDB(of: dsp(with: profile), at: 2_000)
        #expect(abs(low - 6) < 1.0, "40 Hz under a +6 dB low shelf at 100 Hz reads \(low)")
        #expect(abs(mid) < 0.5, "2 kHz should pass a 100 Hz shelf unchanged, reads \(mid)")
    }

    @Test func highShelfCutsTheTopAndLeavesTheMids() {
        let profile = CorrectionProfile(name: "t", preampDB: 0, bands: [
            CorrectionBand(kind: .highShelf, frequency: 10_000, gainDB: -4.2, q: 0.707)
        ])
        let top = gainDB(of: dsp(with: profile), at: 18_000)
        let mid = gainDB(of: dsp(with: profile), at: 1_000)
        #expect(abs(top + 4.2) < 1.0, "18 kHz under a −4.2 dB shelf reads \(top)")
        #expect(abs(mid) < 0.5)
    }

    @Test func correctionPreampScalesEverything() {
        let profile = CorrectionProfile(name: "t", preampDB: -6, bands: [
            CorrectionBand(kind: .peaking, frequency: 4_000, gainDB: 1, q: 1)
        ])
        let far = gainDB(of: dsp(with: profile), at: 200)   // away from the band
        #expect(abs(far + 6) < 0.3, "the profile preamp must apply globally, reads \(far)")
    }

    @Test func correctionComposesWithUserEQ() {
        // Correction: +6 dB low shelf at 100. User EQ: +12 dB at 1 kHz.
        let dsp = EqualizerDSP()
        dsp.configure(sampleRate: 48_000, channels: 2)
        var settings = EqualizerSettings()
        settings.setGain(12, at: 5)
        dsp.update(settings: settings, loudnessGainDB: 0)
        dsp.updateCorrection(CorrectionProfile(name: "t", preampDB: 0, bands: [
            CorrectionBand(kind: .lowShelf, frequency: 100, gainDB: 6, q: 0.707)
        ]))

        var lowBuffer = sine(frequency: 40, sampleRate: 48_000, frames: 19_200)
        let lowRef = rms(lowBuffer[(lowBuffer.count / 2)...])
        lowBuffer.withUnsafeMutableBufferPointer { p in
            dsp.process(p.baseAddress!, frames: p.count, channel: 0, stride: 1)
        }
        let low = 20 * log10(rms(lowBuffer[(lowBuffer.count / 2)...]) / lowRef)

        var midBuffer = sine(frequency: 1_000, sampleRate: 48_000, frames: 19_200)
        let midRef = rms(midBuffer[(midBuffer.count / 2)...])
        midBuffer.withUnsafeMutableBufferPointer { p in
            dsp.process(p.baseAddress!, frames: p.count, channel: 1, stride: 1)
        }
        let mid = 20 * log10(rms(midBuffer[(midBuffer.count / 2)...]) / midRef)

        #expect(abs(low - 6) < 1.0, "the shelf survives alongside user EQ, reads \(low)")
        #expect(abs(mid - 12) < 1.0, "the user boost survives alongside correction, reads \(mid)")
    }

    @Test func removingTheProfileRestoresUnity() {
        let profile = CorrectionProfile(name: "t", preampDB: -6, bands: [
            CorrectionBand(kind: .peaking, frequency: 1_000, gainDB: 8, q: 1)
        ])
        let engine = dsp(with: profile)
        engine.updateCorrection(nil)
        let flat = gainDB(of: engine, at: 1_000)
        #expect(abs(flat) < 0.05, "clearing correction must return to unity, reads \(flat)")
    }
}
