//
//  AIMixService.swift
//  Sonava
//
//  On-device "AI Mix": turns a natural-language prompt into a playlist by
//  mapping intent → musical seeds and assembling a mix from the free Audius
//  catalogue. Runs entirely on-device, no server, no cost.
//

import Foundation

final class AIMixService: Sendable {
    static let shared = AIMixService()

    /// Intent keywords (EN + RU) → search seeds (kept English — services match
    /// them best) and a display label.
    private let intents: [(keys: [String], seeds: [String], label: String)] = [
        (["focus", "study", "work", "concentrate", "deep",
          "фокус", "работ", "учеб", "концентрац", "сосредоточ", "продуктивн"],
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
        // "сон" declines to сна / сну / сне / сном, and the shared stem ("сн")
        // is too short to match safely — it would catch "снег". Listing the
        // five forms of one common noun is the honest, finite fix.
        (["sleep", "night", "dream", "bedtime",
          "сон", "сна", "сну", "сне", "сном", "ноч", "засыпа", "мечт"],
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

    /// What a prompt was understood to mean.
    struct Intent: Equatable {
        /// Search terms handed to the catalogues — always English, because
        /// that is what they index well.
        let seeds: [String]
        /// Human label for the resulting mix.
        let label: String
    }

    /// Understands the prompt. Pure and synchronous, deliberately split from
    /// `generate` so the language handling — Russian in particular — can be
    /// verified without touching the network.
    func resolveIntent(for prompt: String) -> Intent {
        let text = prompt.lowercased()

        // Keys match as substrings so Russian inflections work ("груст" catches
        // "грустная"). The cost is that short keys swallow longer ones —
        // "workout" contains "work", "night drive" contains "night" — so rank
        // by the most specific keyword that matched rather than table order.
        let scored = intents.compactMap { intent -> (intent: Intent, specificity: Int)? in
            let hits = intent.keys.filter { text.contains($0) }
            guard let longest = hits.map(\.count).max() else { return nil }
            return (Intent(seeds: intent.seeds, label: intent.label), longest)
        }
        .sorted { $0.specificity > $1.specificity }

        if let best = scored.first {
            let seeds = scored.flatMap(\.intent.seeds).prefix(3)
            return Intent(seeds: Array(seeds), label: best.intent.label)
        }

        // No known intent — search on the raw prompt.
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return Intent(
            seeds: trimmed.isEmpty ? ["trending"] : [trimmed],
            label: trimmed.isEmpty ? "Your Mix" : trimmed.capitalized
        )
    }

    func generate(prompt: String) async throws -> Mix {
        let intent = resolveIntent(for: prompt)
        let seeds = intent.seeds
        let label = intent.label

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
