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
    static func station(for song: Song) async -> [Song] {
        let query = song.artist.isEmpty ? song.title : song.artist

        async let deezer = DeezerService.shared.search(query)
        async let audius = AudiusService.shared.search(query)

        var seen = Set<String>([song.id])
        var related: [Song] = []
        for candidate in ((try? await deezer) ?? []) + ((try? await audius) ?? []) {
            guard !seen.contains(candidate.id) else { continue }
            seen.insert(candidate.id)
            related.append(candidate)
        }

        return [song] + related.shuffled()
    }
}
