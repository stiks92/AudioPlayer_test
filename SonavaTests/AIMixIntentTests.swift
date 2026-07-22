//
//  AIMixIntentTests.swift
//  SonavaTests
//
//  "AI must understand Russian" is standing feedback from the owner, and the
//  intent table is the only place that promise lives. These run against the
//  pure resolver, so they are fast and offline.
//

import Testing
@testable import Sonava

struct AIMixIntentTests {

    private let service = AIMixService.shared

    // MARK: English

    @Test("English prompts map to the expected mix", arguments: [
        ("i want to focus on work", "Focus"),
        ("something chill and cozy", "Chill"),
        ("gym workout hype", "Energy"),
        ("sad heartbreak songs", "Melancholy"),
        ("party dance music", "Party"),
        ("music for sleep", "Nightfall"),
        ("epic cinematic score", "Cinematic"),
        ("rainy day", "Rainy Day"),
        ("night drive synthwave", "Night Drive"),
    ])
    func englishIntents(prompt: String, expected: String) {
        #expect(service.resolveIntent(for: prompt).label == expected)
    }

    // MARK: Russian

    @Test("Russian prompts map to the same mixes as their English twins", arguments: [
        ("хочу сосредоточиться на работе", "Focus"),
        ("что-нибудь спокойное и уютное", "Chill"),
        ("музыка для качалки", "Energy"),
        ("грустные песни про тоску", "Melancholy"),
        ("вечеринка танцы", "Party"),
        ("музыка перед сном", "Nightfall"),
        ("эпичный саундтрек из кино", "Cinematic"),
        ("дождливый день", "Rainy Day"),
        ("в дорогу синтвейв", "Night Drive"),
        ("джаз", "Jazz"),
        ("рок и метал", "Rock"),
        ("рэп биты", "Beats"),
        ("классическая музыка фортепиано", "Classical"),
        ("электронная музыка техно", "Electronic"),
    ])
    func russianIntents(prompt: String, expected: String) {
        #expect(service.resolveIntent(for: prompt).label == expected)
    }

    @Test("Russian matches on word stems, so inflections still work", arguments: [
        "грустно", "грустная", "грустные песни",
    ])
    func russianInflections(prompt: String) {
        #expect(service.resolveIntent(for: prompt).label == "Melancholy")
    }

    // MARK: Seeds

    @Test("Seeds stay English even for a Russian prompt")
    func seedsAreAlwaysEnglish() {
        let intent = service.resolveIntent(for: "музыка для сна")

        // The catalogues index English tags; sending Cyrillic returns nothing.
        #expect(intent.seeds.contains("ambient"))
        for seed in intent.seeds {
            #expect(seed.allSatisfy { $0.isASCII })
        }
    }

    @Test("At most three seeds are used, however many intents match")
    func seedsAreCapped() {
        let intent = service.resolveIntent(for: "focus chill energy sad party sleep epic")
        #expect(intent.seeds.count <= 3)
    }

    // MARK: Fallbacks

    @Test("An unrecognised prompt is searched literally")
    func unknownPromptIsUsedVerbatim() {
        let intent = service.resolveIntent(for: "Sigur Ros")
        #expect(intent.seeds == ["Sigur Ros"])
        #expect(intent.label == "Sigur Ros")
    }

    @Test("An empty prompt still yields something playable", arguments: ["", "   ", "\n"])
    func emptyPromptFallsBackToTrending(prompt: String) {
        let intent = service.resolveIntent(for: prompt)
        #expect(intent.seeds == ["trending"])
        #expect(intent.label == "Your Mix")
    }

    @Test("Matching ignores case")
    func matchingIsCaseInsensitive() {
        #expect(service.resolveIntent(for: "FOCUS").label == "Focus")
        #expect(service.resolveIntent(for: "ФОКУС").label == "Focus")
    }
}
