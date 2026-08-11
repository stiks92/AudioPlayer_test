//
//  TrackPassport.swift
//  Sonava
//
//  Stage 0 of the Backroom: one analysis pass per file, written down once,
//  read by every feature after it.
//
//  The consilium's judges said it in one sentence: the four product bets all
//  begin with the same offline scan, so the scan is the platform and each
//  feature is a thin reading layer. This file is that scan's ledger — what
//  the app measured about a recording, with the honesty rules the rest of
//  the codebase already lives by: unknown stays nil, confidence is stored
//  next to every estimate, and nothing user-facing ever shows a guess as a
//  fact.
//
//  Patent posture (owner's decision, 2026-08-12, permanent): the passport
//  records tempo, beat grid, key, loudness and a content key. It feeds
//  downbeat-aligned crossfades and queue planning. Nothing here performs or
//  prepares tempo conversion (time-stretch), and nothing performs
//  volume-tracked equal-loudness compensation — those stay out of the
//  binary until the relevant patents expire, by design, not by TODO.
//

import Foundation

/// A steady beat grid: where beat one falls and how far apart beats are.
/// Deliberately not a per-beat array — a grid this shape can only describe
/// steady tempo, which is exactly the only case downstream features are
/// allowed to act on. Rubato gets `nil`, not a lie.
struct BeatGrid: Codable, Equatable, Sendable {
    /// Seconds from file start to the first detected beat.
    var firstBeatOffset: Double
    /// Seconds between beats (60 / BPM).
    var interval: Double
    /// 0…1 — how much of the onset energy the grid actually explains.
    var confidence: Double
}

/// A musical key estimate: pitch class + mode, Krumhansl-correlated.
struct MusicalKey: Codable, Equatable, Sendable {
    /// 0 = C … 11 = B.
    var tonic: Int
    var isMinor: Bool
    /// 0…1 — margin of the winning key over the runner-up.
    var confidence: Double

    /// "F♯m" / "E♭" — unicode accidentals, flats for the flat keys the way
    /// musicians actually spell them.
    var label: String {
        let names = ["C", "D♭", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        let name = names[((tonic % 12) + 12) % 12]
        return isMinor ? name + "m" : name
    }
}

/// Everything one analysis pass learned about one file.
struct TrackPassport: Codable, Equatable, Sendable {
    static let currentVersion = 1

    /// Schema version — the passport outlives app versions, and re-analysis
    /// is triggered by comparing this, not by guessing.
    var version: Int = TrackPassport.currentVersion

    /// Digest of the decoded audio itself (not the file bytes): stable across
    /// retagging, filename changes and container moves of the same PCM.
    var contentKey: String
    /// Which algorithm produced `contentKey`. v0 is a PCM digest — fragile
    /// across transcodes, honest about being so. A future fingerprint
    /// (Chromaprint-class) replaces it under a new kind, and the version
    /// field forces re-analysis at that migration.
    var keyKind: String = "pcm60-sha256-v0"

    var durationSeconds: Double

    /// Integrated loudness, LUFS — measured by the same EBU R128 code the
    /// levelling feature has trusted since epic №6.
    var loudnessLUFS: Double?

    /// Tempo in beats per minute, folded into the 80–160 octave.
    var bpm: Double?
    /// 0…1 — prominence of the tempo peak over the field.
    var bpmConfidence: Double?
    var beatGrid: BeatGrid?

    var musicalKey: MusicalKey?

    /// Seconds where the arrangement audibly changes — verse/chorus-scale
    /// boundaries from a self-similarity novelty curve. Optional and sparse:
    /// a through-composed or ambient piece legitimately has none, and Crate
    /// Mix would rather transition on a real boundary or not at all.
    var sectionBounds: [Double]?

    var analyzedAt: Date
}

/// One passport per file on disk, in Application Support/Passports/<id>.json.
///
/// Per-file rather than one big ledger on purpose: a two-thousand-track
/// library rewriting a single JSON on every scanned file is the exact
/// pattern JSONFileStore exists to avoid, and a corrupt byte should cost one
/// passport, not the archive. Writes are atomic; a file that no longer
/// decodes is deleted and reported, never trusted.
struct PassportStore: Sendable {

    private let directory: URL

    /// Injectable for tests: parallel suites must not share a shelf.
    init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Passports", isDirectory: true)
    }

    static let shared = PassportStore()

    func passport(for songID: String) -> TrackPassport? {
        let url = fileURL(for: songID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let passport = try? JSONDecoder().decode(TrackPassport.self, from: data) else {
            // Corrupt passports are cheap to rebuild and dangerous to trust.
            try? FileManager.default.removeItem(at: url)
            StorageDiagnostics.report(filename: url.lastPathComponent,
                                      message: "passport failed to decode; removed for re-analysis")
            return nil
        }
        guard passport.version == TrackPassport.currentVersion else { return nil }
        return passport
    }

    func save(_ passport: TrackPassport, for songID: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(passport) else { return }
        try? data.write(to: fileURL(for: songID), options: .atomic)
    }

    func hasPassport(for songID: String) -> Bool {
        passport(for: songID) != nil
    }

    /// FNV-1a of the song id — ids carry slashes, colons and unicode, none
    /// of which belong in a filename.
    private func fileURL(for songID: String) -> URL {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in songID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return directory.appendingPathComponent("\(hash).json")
    }
}
