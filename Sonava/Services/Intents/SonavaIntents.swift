//
//  SonavaIntents.swift
//  Sonava
//
//  Siri, Shortcuts and Spotlight entry points. These run in the app process, so
//  they drive the same `AudioManager` the UI does.
//
//  They deliberately read the persisted library straight off disk rather than
//  reaching for a live `MusicLibrary`: an intent can fire before any view has
//  been built, and the files are the source of truth either way.
//

import AppIntents
import SwiftUI

// MARK: - Shared plumbing

/// The stores an intent needs, without depending on a running UI.
private enum IntentLibrary {
    @MainActor
    static var favorites: [Song] { JSONFileStore<[Song]>("favorites.json", default: []).read() }

    @MainActor
    static var recents: [Song] { JSONFileStore<[Song]>("recents.json", default: []).read() }
}

// MARK: - Play favourites

struct PlayFavoritesIntent: AppIntent {
    static let title: LocalizedStringResource = "Play my favourites"
    static let description = IntentDescription("Shuffles the tracks you've hearted.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let favorites = IntentLibrary.favorites
        guard let first = favorites.randomElement() else {
            return .result(dialog: "You haven't hearted any tracks yet.")
        }
        let shuffled = [first] + favorites.filter { $0.id != first.id }.shuffled()
        AudioManager.shared.play(first, in: shuffled)
        return .result(dialog: "Playing your favourites.")
    }
}

// MARK: - Taste radio

struct StartMyRadioIntent: AppIntent {
    static let title: LocalizedStringResource = "Start my radio"
    static let description = IntentDescription("Endless listening built from your own taste.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let favorites = IntentLibrary.favorites
        let recents = IntentLibrary.recents
        // Favourites are the stronger signal; recents keep it working for
        // someone who listens a lot but hearts nothing.
        guard let seed = favorites.first ?? recents.first else {
            return .result(dialog: "Play something first — your radio is built from what you listen to.")
        }

        let taste = TasteProfile.build(favorites: favorites, recents: recents)
        let station = await StationService.station(for: seed, taste: taste)
        let queue = [seed] + station.filter { $0.id != seed.id }
        AudioManager.shared.play(seed, in: queue)
        return .result(dialog: "Starting your radio.")
    }
}

// MARK: - Resume

struct ResumeListeningIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume listening"
    static let description = IntentDescription("Picks up wherever you stopped.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let audio = AudioManager.shared
        // No-op when a track is already loaded, which is exactly what we want:
        // then this is simply "press play".
        audio.restoreLastSession()
        guard audio.currentSong != nil else {
            return .result(dialog: "There's nothing to resume yet.")
        }
        audio.play()
        return .result(dialog: "Picking up where you left off.")
    }
}

// MARK: - Shortcuts

/// Registers the intents so they appear in Spotlight, the Shortcuts app and
/// Siri with no setup by the user. Phrases must name the app, and are
/// translated through the same String Catalog as the rest of the UI.
struct SonavaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayFavoritesIntent(),
            phrases: [
                "Play my favourites in \(.applicationName)",
                "Play my favorites in \(.applicationName)",
                "Play my liked songs in \(.applicationName)"
            ],
            shortTitle: "Favourites",
            systemImageName: "heart.fill"
        )
        AppShortcut(
            intent: StartMyRadioIntent(),
            phrases: [
                "Start my radio in \(.applicationName)",
                "Play my radio in \(.applicationName)"
            ],
            shortTitle: "My radio",
            systemImageName: "dot.radiowaves.left.and.right"
        )
        AppShortcut(
            intent: ResumeListeningIntent(),
            phrases: [
                "Resume listening in \(.applicationName)",
                "Keep listening in \(.applicationName)"
            ],
            shortTitle: "Resume",
            systemImageName: "play.fill"
        )
    }
}
