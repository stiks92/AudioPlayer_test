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

    private let file: JSONFileStore<CorrectionProfile?>

    init(filename: String = "headphone-correction.json") {
        file = JSONFileStore(filename, default: nil)
        profile = file.read()
    }

    func install(_ profile: CorrectionProfile) {
        self.profile = profile
    }

    func setEnabled(_ enabled: Bool) {
        guard var current = profile else { return }
        current.isEnabled = enabled
        profile = current
    }

    func remove() {
        profile = nil
    }
}
