//
//  JourneyTests.swift
//  SonavaTests
//
//  The listening biography: both Spotify export generations, the
//  ListenBrainz shapes, and the aggregation arithmetic the timeline and
//  provenance badges stand on.
//

import Foundation
import Testing
@testable import Sonava

struct JourneyTests {

    // MARK: - Spotify parsers

    @Test func parsesTheExtendedExport() {
        let json = """
        [{"ts":"2014-03-02T21:14:33Z","ms_played":214000,
          "master_metadata_track_name":"Halcyon Drift",
          "master_metadata_album_artist_name":"Vaelo"},
         {"ts":"2014-03-02T21:18:00Z","ms_played":12000,
          "master_metadata_track_name":"Skipped",
          "master_metadata_album_artist_name":"Vaelo"},
         {"ts":"2014-03-02T21:20:00Z","ms_played":180000,
          "master_metadata_track_name":null,
          "master_metadata_album_artist_name":null}]
        """
        let events = ListeningJourney.parseSpotifyExport(Data(json.utf8))
        #expect(events.count == 2, "null-metadata rows (podcasts) drop; short plays survive parsing")
        #expect(events[0].artist == "Vaelo")
        #expect(Int(events[0].timestamp) == 1393794873)
    }

    @Test func parsesTheLegacyExport() {
        let json = """
        [{"endTime":"2019-11-04 14:02","artistName":"Iri","trackName":"Drift","msPlayed":201000}]
        """
        let events = ListeningJourney.parseSpotifyExport(Data(json.utf8))
        #expect(events.count == 1)
        #expect(events[0].title == "Drift")
        #expect(events[0].milliseconds == 201000)
    }

    @Test func listenBrainzExportAndAPIShareOneDecoder() {
        let wrapped = """
        {"payload":{"listens":[
          {"listened_at":1771414109,
           "track_metadata":{"artist_name":"Röyksopp","track_name":"Some Resolve"}}]}}
        """
        let bare = """
        [{"listened_at":1771414109,
          "track_metadata":{"artist_name":"Röyksopp","track_name":"Some Resolve"}}]
        """
        #expect(ListeningJourney.parseListenBrainzExport(Data(wrapped.utf8)).count == 1)
        #expect(ListeningJourney.parseListenBrainzExport(Data(bare.utf8)).count == 1)
    }

    @Test func garbageParsesToNothing() {
        #expect(ListeningJourney.parseSpotifyExport(Data("not json".utf8)).isEmpty)
        #expect(ListeningJourney.parseListenBrainzExport(Data("{}".utf8)).isEmpty)
    }

    // MARK: - Aggregation

    private func event(_ ts: TimeInterval, _ artist: String = "Vaelo",
                       _ title: String = "Halcyon Drift", ms: Int? = 200_000) -> ListenEvent {
        ListenEvent(timestamp: ts, artist: artist, title: title, milliseconds: ms)
    }

    @Test func mergeAggregatesFirstLastAndYears() {
        var journey = Journey()
        // 2014, 2014, 2021 — same track.
        ListeningJourney.merge([
            event(1_393_794_873), event(1_400_000_000), event(1_620_000_000)
        ], into: &journey, source: "test")

        #expect(journey.tracks.count == 1)
        let track = journey.tracks.values.first!
        #expect(track.plays == 3)
        #expect(Int(track.firstListen) == 1_393_794_873)
        #expect(Int(track.lastListen) == 1_620_000_000)
        #expect(track.yearCounts["2014"] == 2)
        #expect(track.yearCounts["2021"] == 1)
    }

    @Test func skipsUnderThirtySeconds() {
        var journey = Journey()
        ListeningJourney.merge([event(1_400_000_000, ms: 5_000)], into: &journey, source: "test")
        #expect(journey.tracks.isEmpty, "a 5-second skip is not a listen")
    }

    @Test func editionsOfTheSameSongLandTogether() {
        var journey = Journey()
        ListeningJourney.merge([
            event(1_400_000_000, "Vaelo", "Halcyon Drift"),
            event(1_500_000_000, "Vaelo", "Halcyon Drift (Remastered 2011)"),
            event(1_600_000_000, "Vaelo", "Halcyon Drift - Single Version")
        ], into: &journey, source: "test")
        #expect(journey.tracks.count == 1,
                "the normaliser must fold editions the way the playlist importer does")
        #expect(journey.tracks.values.first?.plays == 3)
    }

    @Test func provenanceMatchesTheLibrarySong() async {
        let store = await JourneyStore(filename: "journey-test-\(UUID().uuidString).json")
        var journey = Journey()
        ListeningJourney.merge([event(1_393_794_873)], into: &journey, source: "test")
        let song = Song(id: "local:x", title: "Halcyon Drift (Remastered)", artist: "Vaelo",
                        album: "Nightfold", gradientHex: [0, 0xFFFFFF])
        await MainActor.run {
            store.add(events: [ListenEvent(timestamp: 1_393_794_873, artist: "Vaelo",
                                           title: "Halcyon Drift", milliseconds: 200_000)],
                      source: "test")
            #expect(store.entry(for: song) != nil,
                    "a remaster in the library must find its plain-title history")
        }
    }

    @Test func recapTellsTheYearsStory() async {
        await MainActor.run {
            let store = JourneyStore(filename: "journey-test-\(UUID().uuidString).json")
            // 2014: Vaelo ×3. 2015: Iri ×5, Vaelo ×2, Newcomer ×4 (first ever).
            var events: [ListenEvent] = []
            let y2014 = 1_400_000_000.0, y2015 = 1_430_000_000.0
            for i in 0..<3 { events.append(ListenEvent(timestamp: y2014 + Double(i), artist: "Vaelo", title: "T\(i)", milliseconds: nil)) }
            for i in 0..<5 { events.append(ListenEvent(timestamp: y2015 + Double(i), artist: "Iri", title: "I\(i)", milliseconds: nil)) }
            for i in 0..<2 { events.append(ListenEvent(timestamp: y2015 + 100 + Double(i), artist: "Vaelo", title: "T\(i)", milliseconds: nil)) }
            for i in 0..<4 { events.append(ListenEvent(timestamp: y2015 + 200 + Double(i), artist: "Newcomer", title: "N\(i)", milliseconds: nil)) }
            store.add(events: events, source: "test")

            let recap = store.recap(year: "2015")
            #expect(recap != nil)
            guard let recap else { return }
            #expect(recap.plays == 11)
            #expect(recap.topArtists.first?.name == "Iri")
            #expect(recap.discoveries.contains("Newcomer"))
            #expect(!recap.discoveries.contains("Vaelo"),
                    "an artist first heard in 2014 is rotation, not a 2015 discovery")
            #expect(recap.oldestCompanion?.name == "Vaelo")
            #expect(recap.oldestCompanion?.since == "2014")
            #expect(recap.previousYearPlays == 3)
            #expect(store.recap(year: "2019") == nil, "an empty year has no story")
        }
    }

    @Test func timelineRanksArtistsWithinYears() async {
        await MainActor.run {
            let store = JourneyStore(filename: "journey-test-\(UUID().uuidString).json")
            store.add(events: [
                ListenEvent(timestamp: 1_400_000_000, artist: "Vaelo", title: "One", milliseconds: nil),
                ListenEvent(timestamp: 1_400_100_000, artist: "Vaelo", title: "Two", milliseconds: nil),
                ListenEvent(timestamp: 1_400_200_000, artist: "Iri", title: "Three", milliseconds: nil)
            ], source: "test")
            let timeline = store.timeline()
            #expect(timeline.count == 1)
            #expect(timeline.first?.plays == 3)
            #expect(timeline.first?.topArtists.first?.name == "Vaelo")
        }
    }
}
