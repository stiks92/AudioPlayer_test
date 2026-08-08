//
//  LyricsFallbackTests.swift
//  SonavaTests
//
//  The search fallback and the offline cache — the two behaviours that turn
//  "lyrics sometimes" into "lyrics for the library you actually have".
//

import Foundation
import Testing
@testable import Sonava

struct LyricsFallbackTests {

    // MARK: - Query cleaning

    @Test func searchQueryTrimsTagNoise() {
        #expect(LyricsService.searchQuery("Halcyon Drift (feat. Iri)") == "Halcyon Drift")
        #expect(LyricsService.searchQuery("Undertow - Radio Edit") == "Undertow")
        #expect(LyricsService.searchQuery("Low Tide [Remastered 2011]") == "Low Tide")
        #expect(LyricsService.searchQuery("Paper Lanterns – Live") == "Paper Lanterns")
    }

    @Test func searchQueryKeepsSpacesUnlikeTheImportNormaliser() {
        // PlaylistImport.normalise strips spaces for identity comparison;
        // a *search* query with the spaces removed matches nothing.
        #expect(LyricsService.searchQuery("Every Little Ghost") == "Every Little Ghost")
    }

    @Test func searchQueryNeverReturnsEmpty() {
        // A title that IS a parenthetical must survive as itself rather than
        // being trimmed into an empty query that matches the whole database.
        #expect(LyricsService.searchQuery("(untitled)") == "(untitled)")
    }

    // MARK: - Candidate choice

    private func candidate(_ synced: String?, _ plain: String?, _ duration: Double?) -> LrcLibResponse {
        var value = LrcLibResponse(plainLyrics: plain, syncedLyrics: synced)
        value.duration = duration
        return value
    }

    @Test func durationAgreementBeatsListOrder() {
        let wrong = candidate("[00:01.00]wrong", nil, 431)   // 7-minute album cut
        let right = candidate("[00:01.00]right", nil, 212)   // the radio edit we're playing
        let best = LyricsService.bestMatch(from: [wrong, right], duration: 210)
        #expect(best?.syncedLyrics == "[00:01.00]right",
                "a 7-minute cut's lyrics on a 3:30 edit scroll off by the second chorus")
    }

    @Test func syncedBeatsPlainAmongAgreeingCandidates() {
        let plain = candidate(nil, "plain words", 200)
        let synced = candidate("[00:01.00]line", nil, 201)
        let best = LyricsService.bestMatch(from: [plain, synced], duration: 200)
        #expect(best?.syncedLyrics != nil)
    }

    @Test func emptyCandidatesAreNotAMatch() {
        let empty = candidate(nil, nil, 200)
        #expect(LyricsService.bestMatch(from: [empty], duration: 200) == nil)
    }

    @Test func unknownDurationFallsBackToFirstSynced() {
        let plain = candidate(nil, "plain", nil)
        let synced = candidate("[00:01.00]line", nil, nil)
        let best = LyricsService.bestMatch(from: [plain, synced], duration: nil)
        #expect(best?.syncedLyrics != nil)
    }

    // MARK: - Offline cache

    @Test func cacheRoundTripsWithoutNetwork() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyrics-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = LyricsService(cacheDirectory: directory)

        let raw = LyricsService.RawLyrics(synced: "[00:12.00]cached line", plain: nil)
        service.store(raw, artist: "Vaelo", title: "Halcyon Drift")

        let hit = service.cachedRaw(artist: "vaelo", title: "HALCYON DRIFT")
        #expect(hit == raw, "the cache key must be case-insensitive — tags vary by source")
    }

    @Test func cacheMissesAcrossDifferentTracks() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyrics-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = LyricsService(cacheDirectory: directory)
        service.store(.init(synced: "[00:01.00]x", plain: nil), artist: "A", title: "One")
        #expect(service.cachedRaw(artist: "A", title: "Two") == nil)
    }
}
