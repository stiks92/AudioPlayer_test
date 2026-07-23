//
//  StationService.swift
//  Sonava
//
//  Builds an endless "station" seeded from a track — pulls related music
//  from multiple sources (the artist across Deezer + Audius) and returns a
//  queue with the seed first.
//

import Foundation

enum StationService {

    /// Endless station seeded from a track, optionally biased toward the
    /// listener's taste so autoplay drifts toward what they like rather than
    /// only more of the current artist.
    static func station(for song: Song, taste: TasteProfile = .init(topArtists: [])) async -> [Song] {
        let seed = song.artist.isEmpty ? song.title : song.artist
        let queries = ([seed] + taste.seedQueries).reduced()

        let related = await fetch(queries: queries, excluding: [song.id])
        return [song] + related.shuffled()
    }

    /// Recommendations built purely from taste — used by the "Made for you"
    /// shelf. Excludes tracks the listener already has.
    static func recommendations(for taste: TasteProfile, excluding ids: Set<String>) async -> [Song] {
        guard !taste.isEmpty else { return [] }
        return await fetch(queries: taste.seedQueries, excluding: ids)
    }

    private static func fetch(queries: [String], excluding ids: Set<String>) async -> [Song] {
        var seen = ids
        var results: [Song] = []
        for query in queries.prefix(4) {
            async let deezer = DeezerService.shared.search(query)
            async let audius = AudiusService.shared.search(query)
            for candidate in ((try? await deezer) ?? []) + ((try? await audius) ?? []) {
                guard !seen.contains(candidate.id) else { continue }
                seen.insert(candidate.id)
                results.append(candidate)
            }
        }
        return results
    }
}

private extension Array where Element == String {
    /// De-duplicates case-insensitively while preserving order.
    func reduced() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0.lowercased()).inserted }
    }
}
