//
//  StationService.swift
//  Sonava
//
//  Builds an endless "station" seeded from a track — pulls related music
//  from every source the listener has, and returns a queue with the seed
//  first.
//
//  ## Why the listener's own server goes first
//
//  This used to search Deezer and Audius only, which meant a listener with a
//  36,000-track Navidrome heard endless radio built entirely from other
//  people's catalogues — and, worse, from Deezer's 30-second previews, so a
//  station audibly stumbled every half minute. The person this app is for
//  already owns the best possible station material. So the order is: the
//  user's own server, then full-length Audius tracks, and previews only to
//  fill a queue that would otherwise be short.
//

import Foundation

enum StationService {

    /// Searches the listener's connected server. Set once at launch by the
    /// app, which owns `ServerStore`; nil when no server is connected, and
    /// deliberately weakly held so this static hook cannot keep a store alive.
    ///
    /// A closure rather than a dependency because `StationService` is called
    /// from four places including an App Intent, and threading a store
    /// through all of them to reach one search call would be the larger
    /// change.
    @MainActor static var serverSearch: (@Sendable (String) async -> [Song])?

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
        let server = await MainActor.run { serverSearch }
        var seen = ids
        var owned: [Song] = []      // the listener's own library
        var full: [Song] = []       // full-length streams
        var previews: [Song] = []   // 30-second stubs, last resort

        for query in queries.prefix(4) {
            async let serverHits = server?(query) ?? []
            async let deezer = DeezerService.shared.search(query)
            async let audius = AudiusService.shared.search(query)

            for candidate in await serverHits + ((try? await audius) ?? []) + ((try? await deezer) ?? []) {
                guard !seen.contains(candidate.id) else { continue }
                seen.insert(candidate.id)
                switch candidate.source {
                case .subsonic, .local: owned.append(candidate)
                default: candidate.isFullLength ? full.append(candidate) : previews.append(candidate)
                }
            }
        }
        // Previews only fill what the real sources could not: a station made
        // of stubs is the "AI radio stumbles every 30 seconds" complaint.
        let substantial = owned + full
        return substantial + previews.prefix(max(0, 25 - substantial.count))
    }
}

private extension Array where Element == String {
    /// De-duplicates case-insensitively while preserving order.
    func reduced() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0.lowercased()).inserted }
    }
}
