//
//  AIMixService.swift
//  AudioPlayer_test
//
//  On-device "AI Mix": turns a natural-language prompt into a playlist by
//  mapping intent → musical seeds and assembling a mix from the free Audius
//  catalogue. Runs entirely on-device, no server, no cost.
//

import Foundation

final class AIMixService {
    static let shared = AIMixService()

    /// Intent keywords → Audius search seeds.
    private let intents: [(keys: [String], seeds: [String], label: String)] = [
        (["focus", "study", "work", "concentrate", "deep"], ["ambient focus", "lofi", "instrumental"], "Focus"),
        (["chill", "relax", "calm", "cozy", "mellow"], ["chillout", "lofi", "ambient"], "Chill"),
        (["energy", "energetic", "workout", "gym", "run", "hype", "pump"], ["electronic", "edm", "workout"], "Energy"),
        (["sad", "melancholy", "cry", "heartbreak", "emotional"], ["piano", "sad", "cinematic"], "Melancholy"),
        (["happy", "party", "dance", "fun", "upbeat"], ["dance", "house", "feel good"], "Party"),
        (["sleep", "night", "dream", "bedtime"], ["ambient", "sleep", "piano"], "Nightfall"),
        (["epic", "cinematic", "film", "score", "trailer"], ["cinematic", "epic", "soundtrack"], "Cinematic"),
        (["rain", "rainy", "storm"], ["lofi", "rain", "ambient"], "Rainy Day"),
        (["drive", "road", "night drive", "synthwave"], ["synthwave", "electronic", "retro"], "Night Drive"),
        (["jazz"], ["jazz"], "Jazz"),
        (["rock"], ["rock"], "Rock"),
        (["hip hop", "hip-hop", "rap", "beats"], ["hip hop", "beats"], "Beats"),
        (["classical", "orchestra", "piano"], ["classical", "piano"], "Classical"),
        (["electronic", "techno", "house"], ["electronic", "techno", "house"], "Electronic")
    ]

    struct Mix {
        let title: String
        let songs: [Song]
    }

    func generate(prompt: String) async throws -> Mix {
        let text = prompt.lowercased()
        let matched = intents.filter { intent in intent.keys.contains { text.contains($0) } }

        let seeds: [String]
        let label: String
        if let first = matched.first {
            seeds = Array(matched.flatMap(\.seeds).prefix(3))
            label = first.label
        } else {
            // No known intent — search on the raw prompt.
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            seeds = trimmed.isEmpty ? ["trending"] : [trimmed]
            label = trimmed.isEmpty ? "Your Mix" : trimmed.capitalized
        }

        var seen = Set<String>()
        var collected: [Song] = []
        for seed in seeds {
            // Blend full-length Audius tracks with mainstream previews,
            // fetched concurrently.
            async let audius = AudiusService.shared.search(seed)
            async let deezer = DeezerService.shared.search(seed)
            async let apple = iTunesService.shared.searchMusic(seed)
            let results = ((try? await audius) ?? [])
                + ((try? await deezer) ?? [])
                + ((try? await apple) ?? [])
            for song in results where !seen.contains(song.id) {
                seen.insert(song.id)
                collected.append(song)
            }
        }

        collected.shuffle()
        let songs = Array(collected.prefix(30))
        return Mix(title: "\(label) Mix", songs: songs)
    }
}
