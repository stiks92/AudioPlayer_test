//
//  LocalizationCatalogTests.swift
//  SonavaTests
//
//  The old localization system shipped a startup crash (a duplicate key in a
//  static dictionary) and shipped untranslated screens (literals nobody
//  remembered to wrap). The String Catalog makes the first impossible; this
//  suite makes the second visible in CI instead of on a user's phone.
//

import Testing
import Foundation
@testable import Sonava

struct LocalizationCatalogTests {

    /// The catalog compiles to `.lproj` resources in the bundle, so asserting
    /// against the built product is what actually proves shipping behaviour.
    private static let bundle = Bundle(for: BundleToken.self)

    private final class BundleToken {}

    @Test("Russian is a shipped localization")
    func russianIsBundled() throws {
        let appBundle = Bundle(identifier: "com.sonava.player") ?? .main
        #expect(appBundle.localizations.contains("ru"))
    }

    @Test(
        "Key user-facing strings are translated, not echoed back in English",
        arguments: [
            "Home", "Search", "Radio", "Podcasts", "Library",
            "Settings", "Playback", "Sources", "Support",
            "Queue", "Now Playing", "Lyrics", "Favorites",
            "Cancel", "Done", "Create", "Connect",
            // The onboarding subtitles were the strings that actually shipped
            // untranslated, so they are named explicitly here.
            "Streaming, internet radio, podcasts and your own server — unified in one beautiful place.",
            "On-device intelligence, no tracking, no ads. Your taste stays yours.",
            // Genre chips are runtime FilterChip labels, not compiler-visible
            // literals, so they must be added to the catalog by hand — the
            // podcast genres shipped half-translated once because they weren't.
            "Technology", "Comedy", "True Crime", "Business", "Science",
            "Health", "Sports", "History", "Education",
            "Jazz", "Classical", "Electronic", "Ambient",
            // Paywall perks and AI Mix suggestion chips were both runtime
            // strings that shipped in English on a Russian device.
            "Every source, unified", "Studio EQ & spatial", "Support indie dev",
            "Offline & lossless", "Rainy day focus", "Cozy jazz", "Sad piano",
            // The stats screen — including the share card, which is the string
            // most likely to be seen by people who don't have the app yet.
            "Your Sound", "You listened for", "Top artists", "Top tracks",
            "Week", "Month", "All time", "day streak", "peak hour",
            "MY SOUND", "this week", "Clear history",
            // Self-hosting is the differentiator, and its errors are the
            // strings a user sees at their most frustrated.
            "Self-hosted servers", "Add server", "Connect a server",
            "No server connected", "Remove this server?",
            "Invalid server URL.", "Server rejected the credentials.",
            "Connecting more than one server needs Sonava Pro.",
            // Siri phrases and the replies it speaks back.
            "Play my favorites", "Start my radio", "Resume listening",
            "Playing your favorites.", "Starting your radio.",
            "Play my favorites in ${applicationName}",
            // This release's new surfaces. Each of these shipped in English
            // on a Russian build at least once during development, which is
            // exactly why they are named here rather than trusted.
            "Server", "Sources", "Cloud drive", "Artists",
            "No cloud drive connected", "Connect a drive", "App password",
            "Move to a new iPhone", "Save a backup", "Restore from a backup",
            "Even out volume", "Random", "Try again", "Reading your library…",
            "The server has no albums yet.",
            "Import a playlist", "Choose a file", "Not found", "Start over",
            // The stream-EQ honesty footnotes: the words that state whether a
            // stream is actually being processed.
            "Shapes files and network streams alike.",
            "Applied to this stream too.",
            "This stream's format doesn't allow processing — it plays flat.",
            // The growth-scan batch: the paywall's pay-once framing and the
            // Monday Mix ritual.
            "Pay once. No subscription, no ads.",
            "Pay once — yours forever",
            "Monday Mix", "Monday Mix reminder",
            "A fresh weekly mix, announced once on Monday morning.",
            "Your Monday Mix is ready",
            "A fresh week of music, picked from what you love.",
            "Gapless, loudness levelling and scrobbling are free for everyone — Pro is the extras.",
            // Caught untranslated on a RU paywall frame while shipping the
            // batch above — the fifth such catch, and the reason this list
            // only ever grows.
            "Plus every self-hosted server you own searched together, and your full listening history.",
            // Stage 2: the recap ritual.
            "Your year", "Share the card", "Discovered this year", "Still with you",
            "Counted on this phone. Your listening never leaves it.",
            // Stage 2: the listening-history import.
            "Listening history", "Open the timeline", "Your years in music",
            "Bring your listening past with you — every year of it, stitched to the music you own.",
            // Stage 1 of the Backroom: the headphone-correction screen.
            "Headphone correction", "Apply profile",
            "Studio-grade correction for your exact headphones — from a measurement of your model, not a generic bass boost.",
            "Applied to files and streams alike, before your own EQ. One profile for both ears for now.",
            "From a file", "From a list", "Playlist name",
            "Those credentials weren't accepted. Yandex and Mail.ru need an app password, not your account password.",
        ]
    )
    func stringsAreTranslatedToRussian(key: String) throws {
        let appBundle = Bundle(identifier: "com.sonava.player") ?? .main
        let path = try #require(
            appBundle.path(forResource: "ru", ofType: "lproj"),
            "the app bundle has no ru.lproj"
        )
        let russian = try #require(Bundle(path: path))

        let translated = russian.localizedString(forKey: key, value: nil, table: nil)
        #expect(translated != key, "\"\(key)\" is still English in Russian builds")
        #expect(translated.isEmpty == false)
    }

    @Test("Russian counts decline instead of reading \"5 трек\"")
    func russianPluralsDecline() throws {
        let appBundle = Bundle(identifier: "com.sonava.player") ?? .main
        let path = try #require(appBundle.path(forResource: "ru", ofType: "lproj"))
        let russian = try #require(Bundle(path: path))

        let format = russian.localizedString(forKey: "%lld tracks", value: nil, table: nil)
        let one = String(format: format, locale: Locale(identifier: "ru_RU"), 1)
        let few = String(format: format, locale: Locale(identifier: "ru_RU"), 3)
        let many = String(format: format, locale: Locale(identifier: "ru_RU"), 5)

        #expect(one == "1 трек")
        #expect(few == "3 трека")
        #expect(many == "5 треков")
    }
}
