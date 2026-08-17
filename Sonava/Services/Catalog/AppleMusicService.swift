//
//  AppleMusicService.swift
//  Sonava
//
//  The 100-million-track answer to "the app feels empty": the listener's
//  own Apple Music subscription, played inside Sonava through MusicKit.
//
//  The economics that make this the right first catalogue move (from the
//  growth consilium): this is NOT catalogue licensing. Apple's subscriber
//  pays Apple; MusicKit grants third-party apps full catalogue playback for
//  that subscriber at zero licence cost — the same door Marvis Pro lives
//  behind. We sell the experience around the catalogue, never the
//  catalogue itself.
//
//  Two honest boundaries, stated where they bite:
//  * Playback runs in Apple's DRM player, outside our AVAudioEngine graph —
//    EQ, headphone correction and loudness levelling cannot touch it, and
//    the EQ screen says so for this source.
//  * The whole feature degrades to a quiet "connect" state until the owner
//    flips the MusicKit app service on the App ID in App Store Connect —
//    without it, catalogue requests are refused a developer token. That
//    switch cannot be flipped from code and lands on the owner's hand-list.
//

import Foundation
import MusicKit

@MainActor
final class AppleMusicService: ObservableObject {

    static let shared = AppleMusicService()

    enum Availability: Equatable {
        /// Not asked yet, or asked and declined.
        case notConnected
        /// Authorized and the catalogue answers.
        case ready
        /// Authorized, but no active subscription — browse works, play won't.
        case noSubscription
        /// The App ID has no MusicKit service yet (developer-token refusal).
        case notConfigured
    }

    @Published private(set) var availability: Availability = .notConnected

    var isReady: Bool { availability == .ready || availability == .noSubscription }

    // MARK: - Connect

    /// Asks for authorization and probes the catalogue once, mapping every
    /// failure to an honest availability state.
    func connect() async {
        let status = await MusicAuthorization.request()
        guard status == .authorized else {
            availability = .notConnected
            return
        }
        do {
            // A one-song probe proves the developer token works.
            var request = MusicCatalogSearchRequest(term: "a", types: [MusicKit.Song.self])
            request.limit = 1
            _ = try await request.response()
            let subscription = try? await MusicSubscription.current
            availability = (subscription?.canPlayCatalogContent ?? false) ? .ready : .noSubscription
        } catch {
            // Missing MusicKit app service presents as a token/permission
            // error on the very first request.
            availability = .notConfigured
        }
    }

    func restoreIfAuthorized() async {
        guard MusicAuthorization.currentStatus == .authorized else { return }
        await connect()
    }

    // MARK: - Catalogue

    func search(_ term: String, limit: Int = 25) async throws -> [Song] {
        var request = MusicCatalogSearchRequest(term: term, types: [MusicKit.Song.self])
        request.limit = limit
        let response = try await request.response()
        return response.songs.compactMap(Self.map)
    }

    /// The storefront's current top songs — the day-zero shelf for a
    /// subscriber.
    func chart(limit: Int = 20) async throws -> [Song] {
        var request = MusicCatalogChartsRequest(kinds: [.mostPlayed], types: [MusicKit.Song.self])
        request.limit = limit
        let response = try await request.response()
        return response.songCharts.first?.items.compactMap(Self.map) ?? []
    }

    // MARK: - Mapping

    /// MusicKit's song into the app's own currency. The id keeps the catalog
    /// identifier so playback can rebuild the MusicKit queue from it.
    nonisolated static func map(_ song: MusicKit.Song) -> Song? {
        Song(
            id: "applemusic:\(song.id.rawValue)",
            title: song.title,
            artist: song.artistName,
            album: song.albumTitle ?? "",
            source: .appleMusic,
            artworkURL: song.artwork?.url(width: 600, height: 600),
            streamURL: nil,
            gradientHex: Palette.hex(forSeed: song.id.rawValue),
            durationSeconds: song.duration,
            trackNumber: song.trackNumber,
            year: song.releaseDate.map { Calendar.current.component(.year, from: $0) }
        )
    }

    /// The raw catalogue id back out of our Song id.
    nonisolated static func catalogID(of song: Song) -> String? {
        guard song.source == .appleMusic,
              song.id.hasPrefix("applemusic:") else { return nil }
        return String(song.id.dropFirst("applemusic:".count))
    }
}
