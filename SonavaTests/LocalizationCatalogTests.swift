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
