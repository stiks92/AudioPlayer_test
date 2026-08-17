//
//  AppleMusicTests.swift
//  SonavaTests
//
//  The Apple Music seam: id round-tripping and the gates that keep a DRM
//  catalogue track from being promised things the app cannot deliver.
//

import Foundation
import Testing
@testable import Sonava

struct AppleMusicTests {

    private func amSong(_ id: String = "1613600188") -> Song {
        Song(id: "applemusic:\(id)", title: "T", artist: "A", album: "L",
             source: .appleMusic, gradientHex: [0, 1])
    }

    @Test func catalogIDRoundTrips() {
        #expect(AppleMusicService.catalogID(of: amSong("42")) == "42")
        let local = Song(id: "local:x", title: "T", artist: "A", album: "L", gradientHex: [0, 1])
        #expect(AppleMusicService.catalogID(of: local) == nil,
                "only Apple Music songs may claim a catalogue id")
    }

    @Test func drmTracksAreNeverDownloadable() {
        #expect(!TrackSource.appleMusic.isDownloadable,
                "there is no file to save; a progress bar over DRM would be a lie")
    }

    @Test func badgeNamesTheSource() {
        #expect(TrackSource.appleMusic.badge == "APPLE MUSIC")
    }

    @Test func crateMixSinksUnpassportedCatalogueTracks() {
        // No file → no passport → the planner must not guess about it.
        let steps = CrateMix.plan(anchor: nil, songs: [amSong()]) { _ in nil }
        #expect(steps.first?.quality == 0.1, "an unmeasurable track rides the tail, honestly")
    }

    @Test func sharedPlaylistsCarryIdentityAndRoundTrip() throws {
        // The wire format for an Apple Music track carries the catalogue id
        // (no stream, no credentials) — the receiver's own subscription
        // resolves it, the same recipient-side re-resolution servers use.
        let link = try #require(PlaylistSharing.link(
            for: UserPlaylist(name: "Mix", tracks: [amSong("99")])))
        let decoded = try #require(PlaylistSharing.playlist(from: link))
        #expect(decoded.tracks.first?.id == "applemusic:99")
        #expect(decoded.tracks.first?.source == .appleMusic)
        #expect(decoded.tracks.first?.streamURL == nil, "identity travels; no stream does")
    }
}
