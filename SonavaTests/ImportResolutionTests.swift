//
//  ImportResolutionTests.swift
//  SonavaTests
//
//  The import's move onto the shared TrackResolver: parsed rows go through
//  the same door order as every other import path — and previews finally
//  flow through the resolver's own honest `.preview` column instead of
//  being silently absent. Every door is a stub; what's proven is the
//  ledger's arithmetic, not the networks.
//

import Foundation
import Testing
@testable import Sonava

@MainActor
struct ImportResolutionTests {

    private func song(_ id: String, _ artist: String, _ title: String,
                      source: TrackSource) -> Song {
        Song(id: id, title: title, artist: artist, album: "A", source: source,
             gradientHex: [0, 1])
    }

    /// Three rows, three fates: found locally, preview-only, nowhere at all.
    @Test func resolverAnswersBucketIntoTheImportLedger() async {
        let resolver = TrackResolver(doors: .init(
            librarySongs: { [self.song("local:1", "Vaelo", "Halcyon Drift", source: .local)] },
            serverSearch: nil,
            appleMusicSearch: nil,
            audiusSearch: { _ in [] },
            previewSearch: { term in
                term.contains("Roads")
                    ? [self.song("deezer:2", "Portishead", "Roads", source: .deezer)] : []
            }))

        let parsed = [
            PlaylistImport.ParsedTrack(title: "Halcyon Drift", artist: "Vaelo", album: nil),
            PlaylistImport.ParsedTrack(title: "Roads", artist: "Portishead", album: nil),
            PlaylistImport.ParsedTrack(title: "Nowhere To Be Found", artist: "Nobody", album: nil)
        ]
        let results = await resolver.resolveAll(
            PlaylistImport.foreignTracks(parsed, origin: .pastedText))
        let outcome = PlaylistImport.outcome(from: results)

        #expect(outcome.matched.map(\.id) == ["local:1"])
        #expect(outcome.previews.map(\.id) == ["deezer:2"],
                "a preview is its own ledger column, never dressed as a match")
        #expect(outcome.missing.map(\.title) == ["Nowhere To Be Found"],
                "the honest not-found, by name, in the order the list read")
        #expect(outcome.total == 3)
    }

    @Test func foreignTracksCarryTheirOrigin() {
        let parsed = [PlaylistImport.ParsedTrack(title: "Xtal", artist: "Aphex Twin", album: "SAW 85-92")]
        let foreign = PlaylistImport.foreignTracks(parsed, origin: .youtubeLink)
        #expect(foreign.count == 1)
        #expect(foreign[0].origin == .youtubeLink)
        #expect(foreign[0].title == "Xtal")
        #expect(foreign[0].artist == "Aphex Twin")
        #expect(foreign[0].album == "SAW 85-92")
    }

    @Test func aFullTrackDoorAnsweringMeansPreviewsAreNeverAsked() async {
        var previewsAsked = false
        let resolver = TrackResolver(doors: .init(
            librarySongs: { [] },
            serverSearch: nil,
            appleMusicSearch: nil,
            audiusSearch: { _ in [self.song("audius:1", "Vaelo", "Halcyon Drift", source: .audius)] },
            previewSearch: { _ in previewsAsked = true; return [] }))

        let parsed = [PlaylistImport.ParsedTrack(title: "Halcyon Drift", artist: "Vaelo", album: nil)]
        let results = await resolver.resolveAll(
            PlaylistImport.foreignTracks(parsed, origin: .pastedText))
        let outcome = PlaylistImport.outcome(from: results)

        #expect(outcome.matched.count == 1)
        #expect(!previewsAsked, "the consolation door opens only after every full-track door said no")
    }

    @Test func missingRowsKeepArtistAndAlbumForTheScreen() {
        let foreign = ForeignTrack(title: "T", artist: "A", album: "B", origin: .pastedText)
        let outcome = PlaylistImport.outcome(from: [(foreign, .notFound)])
        #expect(outcome.missing == [PlaylistImport.ParsedTrack(title: "T", artist: "A", album: "B")])
    }
}
