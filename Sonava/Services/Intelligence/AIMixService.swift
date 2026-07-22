//
//  AIMixService.swift
//  Sonava
//
//  On-device "AI Mix": turns a natural-language prompt into a playlist by
//  mapping intent → musical seeds and assembling a mix from the free Audius
//  catalogue. Runs entirely on-device, no server, no cost.
//

import Foundation

final class AIMixService {
    static let shared = AIMixService()

    /// Intent keywords (EN + RU) → search seeds (kept English — services match
    /// them best) and a display label.
    private let intents: [(keys: [String], seeds: [String], label: String)] = [
        (["focus", "study", "work", "concentrate", "deep",
          "фокус", "работа", "учеб", "концентрац", "сосредоточ", "продуктивн"],
         ["lofi", "ambient", "instrumental focus"], "Focus"),
        (["chill", "relax", "calm", "cozy", "mellow",
          "чил", "релакс", "расслаб", "спокой", "уют", "отдых"],
         ["chillout", "lofi", "ambient chill"], "Chill"),
        (["energy", "energetic", "workout", "gym", "run", "hype", "pump",
          "энерг", "качалк", "спорт", "бег", "тренировк", "бодр", "драйв"],
         ["electronic", "edm", "workout"], "Energy"),
        (["sad", "melancholy", "cry", "heartbreak", "emotional",
          "груст", "печаль", "меланхол", "слез", "тоск"],
         ["piano", "sad", "cinematic piano"], "Melancholy"),
        (["happy", "party", "dance", "fun", "upbeat",
          "вечеринк", "танц", "праздник", "радост", "весел", "туса"],
         ["dance", "house", "feel good"], "Party"),
        (["sleep", "night", "dream", "bedtime",
          "сон", "ноч", "засыпа", "перед сном", "мечт"],
         ["ambient", "sleep", "calm piano"], "Nightfall"),
        (["epic", "cinematic", "film", "score", "trailer",
          "эпичн", "кино", "саундтрек", "оркестр"],
         ["cinematic", "epic", "soundtrack"], "Cinematic"),
        (["rain", "rainy", "storm", "дожд", "гроза", "осен"],
         ["lofi", "rain", "ambient"], "Rainy Day"),
        (["drive", "road", "synthwave", "дорог", "поездк", "трасс", "синтвейв"],
         ["synthwave", "electronic", "retrowave"], "Night Drive"),
        (["jazz", "джаз"], ["jazz"], "Jazz"),
        (["rock", "рок", "метал", "metal"], ["rock"], "Rock"),
        (["hip hop", "hip-hop", "rap", "beats", "рэп", "реп", "хип-хоп", "бит"],
         ["hip hop", "trap beats"], "Beats"),
        (["classical", "orchestra", "piano", "классик", "классич", "пианино", "фортепиано"],
         ["classical", "piano"], "Classical"),
        (["electronic", "techno", "house", "электрон", "техно", "хаус"],
         ["electronic", "techno", "house"], "Electronic")
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
