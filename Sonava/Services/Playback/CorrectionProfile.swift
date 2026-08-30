//
//  CorrectionProfile.swift
//  Sonava
//
//  Stage 1 of the Backroom: headphone correction — the parametric EQ that
//  flattens a specific headphone toward a studio target.
//
//  The licence line this feature walks (drilled and assassin-checked): the
//  AutoEq project's MIT licence covers its *code*, not its measurement
//  data — the author said so in writing. So v1 ships no third-party
//  profiles at all. Instead it does what the playlist importer does: the
//  listener pastes or opens the profile THEY exported from AutoEq's own
//  site for THEIR headphones, and the app applies it. Their download,
//  their data, our DSP. Bundling profiles becomes possible per-source as
//  written permissions arrive (the letters live in docs/letters/).
//
//  Positioning rule from the same drill: this is sound personalisation,
//  never medicine. No "hearing test", no "audiogram" anywhere in UI or
//  code-facing strings.
//

import Foundation

/// One parametric band of a correction profile.
struct CorrectionBand: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case peaking      // AutoEq "PK"
        case lowShelf     // AutoEq "LSC"
        case highShelf    // AutoEq "HSC"
    }
    var kind: Kind
    var frequency: Double   // Hz
    var gainDB: Double
    var q: Double
}

/// A named correction: preamp + bands, applied before the user's own EQ.
struct CorrectionProfile: Codable, Equatable, Sendable {
    var name: String
    var preampDB: Double
    var bands: [CorrectionBand]
    var isEnabled: Bool = true

    /// Sanity limits: a pasted file claiming +40 dB anywhere is a typo or a
    /// troll, and either way not a filter this app will run.
    var isPlausible: Bool {
        guard !bands.isEmpty, bands.count <= 32 else { return false }
        guard preampDB > -30, preampDB <= 6 else { return false }
        return bands.allSatisfy { band in
            band.frequency >= 10 && band.frequency <= 22_000
                && abs(band.gainDB) <= 20
                && band.q > 0.05 && band.q <= 12
        }
    }
}

/// Parses AutoEq's ParametricEQ export — the text file their site produces
/// for every headphone model:
///
///     Preamp: -6.4 dB
///     Filter 1: ON PK Fc 105 Hz Gain -2.4 dB Q 0.70
///     Filter 10: ON HSC Fc 10000 Hz Gain -4.2 dB Q 0.70
///
/// Tolerant of the wild: extra whitespace, decimal commas (a file that
/// travelled through a Russian spreadsheet), case drift, "None" filters.
enum CorrectionProfileParser {

    static func parse(_ text: String, name: String) -> CorrectionProfile? {
        var preamp: Double = 0
        var bands: [CorrectionBand] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()

            if lower.hasPrefix("preamp") {
                if let value = firstNumber(after: "preamp", in: lower) { preamp = value }
                continue
            }
            guard lower.hasPrefix("filter"), lower.contains(" on ") else { continue }

            let kind: CorrectionBand.Kind
            if lower.contains(" pk ") { kind = .peaking }
            else if lower.contains(" lsc ") || lower.contains(" ls ") { kind = .lowShelf }
            else if lower.contains(" hsc ") || lower.contains(" hs ") { kind = .highShelf }
            else { continue }

            guard let frequency = firstNumber(after: "fc", in: lower),
                  let gain = firstNumber(after: "gain", in: lower) else { continue }
            // Shelf lines from some exporters omit Q; RBJ's gentle default.
            let q = firstNumber(after: "q", in: lower) ?? 0.707

            bands.append(CorrectionBand(kind: kind, frequency: frequency, gainDB: gain, q: q))
        }

        let profile = CorrectionProfile(name: name, preampDB: preamp, bands: bands)
        return profile.isPlausible ? profile : nil
    }

    /// The first number following a keyword: "gain -2.4 db" → -2.4.
    /// Understands decimal commas because exported files travel.
    private static func firstNumber(after keyword: String, in line: String) -> Double? {
        guard let range = line.range(of: keyword) else { return nil }
        let tail = line[range.upperBound...]
        var token = ""
        var started = false
        for character in tail {
            if character.isNumber || character == "-" || character == "+" || character == "." || character == "," {
                token.append(character == "," ? "." : character)
                started = true
            } else if started {
                break
            } else if character == ":" || character == " " || character == "\t" {
                continue
            }
        }
        return Double(token)
    }
}

/// The selected profile, persisted with the same resilience as every other
/// store in the app.
@MainActor
final class CorrectionStore: ObservableObject {

    @Published private(set) var profile: CorrectionProfile? {
        didSet { file.write(profile) }
    }

    /// The voicing tilt — stage 1.5. Persisted beside the profile, in its
    /// own file, because they are different facts with different lifetimes:
    /// replacing the headphones' measurement must not reset the listener's
    /// taste, and clearing the taste must not touch the measurement.
    @Published private(set) var tilt: VoicingTilt {
        didSet { tiltFile.write(tilt) }
    }

    /// The A/B switch: true while the listener is comparing against the
    /// untouched sound. Deliberately NOT persisted — bypass is a comparison
    /// instrument, not a setting, and an app relaunch must never silently
    /// resume "off".
    @Published private(set) var isBypassed = false

    /// Mirrors the subscription, like `ServerStore.isPro` — set only from
    /// RootView's single propagation point. A lapse never deletes the
    /// installed profile: it stays on disk and on screen, it just stops
    /// being applied until Pro returns. Hiding the data would make the gate
    /// feel like confiscation, the same rule the servers follow.
    @Published var isPro = false

    /// What the engines actually run: the measured profile composed with
    /// the voicing tilt, only while Pro, and nothing at all during A/B.
    var effectiveProfile: CorrectionProfile? {
        Self.effective(profile: profile, tilt: tilt, isPro: isPro, isBypassed: isBypassed)
    }

    /// The one place profile and tilt become a cascade. Static and pure so
    /// the Combine pipeline can call it with *emitted* values — `@Published`
    /// fires on willSet, so reading the store's properties from inside a
    /// sink would read the past.
    ///
    /// The tilt's shelves go FIRST in the band list: biquads commute, but
    /// the local engine's slot count does not — a profile long enough to
    /// hit the prefix cap must truncate its own tail, never the tilt.
    static func effective(profile: CorrectionProfile?, tilt: VoicingTilt,
                          isPro: Bool, isBypassed: Bool) -> CorrectionProfile? {
        guard isPro, !isBypassed else { return nil }
        let base = (profile?.isEnabled == true) ? profile : nil
        if tilt.isNeutral { return base }
        let tiltBands = tilt.bands
        guard base != nil || !tiltBands.isEmpty else { return nil }
        return CorrectionProfile(name: base?.name ?? "Voicing",
                                 preampDB: (base?.preampDB ?? 0) + tilt.preampDB,
                                 bands: tiltBands + (base?.bands ?? []))
    }

    private let file: JSONFileStore<CorrectionProfile?>
    private let tiltFile: JSONFileStore<VoicingTilt>

    init(filename: String = "headphone-correction.json",
         tiltFilename: String = "headphone-voicing.json") {
        file = JSONFileStore(filename, default: nil)
        tiltFile = JSONFileStore(tiltFilename, default: VoicingTilt())
        profile = file.read()
        tilt = tiltFile.read()
    }

    func install(_ profile: CorrectionProfile) {
        self.profile = profile
    }

    func setEnabled(_ enabled: Bool) {
        guard var current = profile else { return }
        current.isEnabled = enabled
        profile = current
    }

    /// Re-normalises through the clamping initialiser so a wild value from
    /// any call site lands inside the shelf ranges.
    func setTilt(_ tilt: VoicingTilt) {
        self.tilt = VoicingTilt(bassDB: tilt.bassDB, trebleDB: tilt.trebleDB)
    }

    func setBypassed(_ bypassed: Bool) {
        isBypassed = bypassed
    }

    func remove() {
        profile = nil
    }
}
