//
//  TasteProfile.swift
//  Sonava
//
//  A tiny, on-device model of what the listener likes, derived from the tracks
//  they favourited and recently played. It stays on the phone — no profiling
//  server, in keeping with the app's privacy promise — and seeds both the
//  "Made for you" shelf and taste-aware endless radio.
//

import Foundation

struct TasteProfile: Equatable {

    /// Artists the listener returns to, most-liked first.
    let topArtists: [String]

    /// Search terms to find more music like this — the top artists, capped.
    var seedQueries: [String] { Array(topArtists.prefix(4)) }

    var isEmpty: Bool { topArtists.isEmpty }

    /// A favourite is a stronger signal than something merely played, so it
    /// counts for more. Live radio and podcasts carry no "artist" taste and are
    /// ignored.
    static func build(favorites: [Song], recents: [Song]) -> TasteProfile {
        var weights: [String: Int] = [:]

        func tally(_ songs: [Song], weight: Int) {
            for song in songs where song.source != .radio && song.source != .podcast {
                let artist = song.artist.trimmingCharacters(in: .whitespaces)
                guard !artist.isEmpty,
                      artist.caseInsensitiveCompare(unknownArtist) != .orderedSame
                else { continue }
                weights[artist, default: 0] += weight
            }
        }

        tally(favorites, weight: 3)
        tally(recents, weight: 1)

        // Rank by weight; break ties alphabetically so the result is stable.
        let ranked = weights.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
        }
        return TasteProfile(topArtists: ranked.map(\.key))
    }

    /// Matches the placeholder `LocalFileStore` gives files with no artist tag,
    /// so an untagged import doesn't masquerade as a taste signal.
    private static let unknownArtist = String(localized: "Unknown artist")
}
