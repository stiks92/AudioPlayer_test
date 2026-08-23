//
//  TrackResolver.swift
//  Sonava
//
//  The hub's engine room: one service that takes a *foreign* track — a row
//  from a Spotify export, a pasted Yandex playlist, a shared link, a
//  history entry — and answers with the best PLAYABLE version the listener
//  actually has, searched in honest order:
//
//      their files → their server → their Apple Music subscription → Audius
//
//  Previews are deliberately not in the chain: the resolver promises full
//  tracks or a truthful "not found", never a 30-second consolation prize
//  dressed as a match.
//
//  Matching is the playlist importer's own arithmetic (normalised
//  artist/title, duration agreement when both sides know it), so a
//  remaster, a "(feat.)" credit or a Single Version all land on the same
//  recording — and the fingerprint key in the track passport is the
//  planned upgrade path for the day two files disagree about their tags.
//

import Foundation

/// Where a foreign row came from — carried for provenance chips, the
/// "Открыть в {сервисе}" degradation and per-origin link-backs (Spotify's
/// policy requires them). Deliberately NOT part of the cache key: the same
/// recording pasted from two services is one resolution.
enum TrackOrigin: String, Codable, Sendable {
    case spotifyExport, yandexLink, youtubeLink, sharedLink
    case listeningHistory, pastedText
}

struct ForeignTrack: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String?
    var durationSeconds: Double?
    var origin: TrackOrigin?
    var originURL: URL?

    init(title: String, artist: String, album: String? = nil,
         durationSeconds: Double? = nil,
         origin: TrackOrigin? = nil, originURL: URL? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.origin = origin
        self.originURL = originURL
    }
}

enum TrackResolution: Equatable, Sendable {
    /// A playable full track from one of the listener's own sources.
    case matched(Song)
    /// Only a 30-second preview exists. A separate case on purpose: the
    /// import ledger counts "нашлось 30 · превью 4 · не нашлось 6", and a
    /// preview claiming to be a match would be a lie with a play button.
    case preview(Song)
    /// Nothing playable found — the honest answer, kept distinct from an
    /// error so UI can offer the Bandcamp/store path instead of a spinner.
    case notFound
}

@MainActor
final class TrackResolver {

    /// The searchable doors, injectable so tests can stub every one.
    /// TIDAL is deliberately NOT a door: its terms forbid mixing TIDAL
    /// content into another service's stream — it plays only in its own
    /// segregated session, never as a resolver answer.
    struct Doors {
        var librarySongs: () -> [Song]
        var serverSearch: ((String) async -> [Song])?
        var appleMusicSearch: ((String) async throws -> [Song])?
        var audiusSearch: ((String) async throws -> [Song])?
        /// Previews, tried LAST and reported as `.preview`, never `.matched`.
        var previewSearch: ((String) async throws -> [Song])?
    }

    private let doors: Doors
    /// Resolutions are stable within a session: the same foreign row asked
    /// twice (import retried, screen re-entered) must not search twice.
    private var cache: [String: TrackResolution] = [:]
    /// Bumped when a door opens or closes (server connected, Apple Music
    /// authorized): earlier answers may now be beatable, so they expire.
    private var generation = 0

    init(doors: Doors) {
        self.doors = doors
    }

    /// A door changed (connected/disconnected): everything resolved before
    /// is re-askable — a track that fell through to Audius yesterday may
    /// live on the server the listener just connected.
    func invalidate() {
        generation += 1
        cache.removeAll()
    }

    /// Production wiring: every door the listener actually has connected.
    static func live(library: MusicLibrary, serverStore: ServerStore) -> TrackResolver {
        TrackResolver(doors: Doors(
            librarySongs: { library.songs },
            serverSearch: serverStore.isConnected
                ? { term in (try? await serverStore.search(term)) ?? [] } : nil,
            appleMusicSearch: AppleMusicService.shared.isReady
                ? { term in try await AppleMusicService.shared.search(term) } : nil,
            audiusSearch: { term in try await AudiusService.shared.search(term) }
        ))
    }

    /// The cache key folds the duration into 5-second buckets: the radio
    /// edit and the album cut of one song are different recordings and must
    /// not share a resolution.
    private func cacheKey(_ foreign: ForeignTrack) -> String {
        let bucket = foreign.durationSeconds.map { Int($0 / 5) } ?? -1
        return Journey.key(artist: foreign.artist, title: foreign.title) + "|\(bucket)"
    }

    func resolve(_ foreign: ForeignTrack) async -> TrackResolution {
        let key = cacheKey(foreign)
        if let cached = cache[key] { return cached }

        let resolution = await search(foreign)
        cache[key] = resolution
        return resolution
    }

    /// Resolves a whole list, reporting progress — the number the import
    /// screens already speak: "нашлось 34 из 40".
    func resolveAll(_ tracks: [ForeignTrack],
                    progress: (@MainActor (Int, Int) -> Void)? = nil) async -> [(ForeignTrack, TrackResolution)] {
        var results: [(ForeignTrack, TrackResolution)] = []
        for (index, track) in tracks.enumerated() {
            results.append((track, await resolve(track)))
            progress?(index + 1, tracks.count)
        }
        return results
    }

    // MARK: - The order of doors

    private func search(_ foreign: ForeignTrack) async -> TrackResolution {
        // 1. Their files — free, instant, offline.
        if let hit = Self.bestMatch(foreign, in: doors.librarySongs()) {
            return .matched(hit)
        }
        let term = "\(foreign.artist) \(foreign.title)"
        // 2. Their server.
        if let serverSearch = doors.serverSearch,
           let hit = Self.bestMatch(foreign, in: await serverSearch(term)) {
            return .matched(hit)
        }
        // 3. Their Apple Music subscription.
        if let appleSearch = doors.appleMusicSearch,
           let hit = Self.bestMatch(foreign, in: (try? await appleSearch(term)) ?? []) {
            return .matched(hit)
        }
        // 4. The open catalogue.
        if let audiusSearch = doors.audiusSearch,
           let hit = Self.bestMatch(foreign, in: (try? await audiusSearch(term)) ?? []) {
            return .matched(hit)
        }
        // 5. Previews — the consolation, clearly labelled as one.
        if let previewSearch = doors.previewSearch,
           let hit = Self.bestMatch(foreign, in: (try? await previewSearch(term)) ?? [],
                                    allowPreviews: true) {
            return .preview(hit)
        }
        return .notFound
    }

    /// The importer's matching rules, applied to one candidate list: the
    /// normalised pair must agree, and when both sides know their duration
    /// they must agree within four seconds — a 7-minute album cut is not a
    /// match for a radio edit whatever the tags say.
    /// Exact normalised-pair equality only — containment matching ("Help"
    /// inside "Help Me Out") is refused by design, because a wrong match in
    /// a music app plays the wrong song with full confidence. Among equals:
    /// album agreement wins, then reported quality.
    static func bestMatch(_ foreign: ForeignTrack, in candidates: [Song],
                          allowPreviews: Bool = false) -> Song? {
        let wanted = Journey.key(artist: foreign.artist, title: foreign.title)
        let agreeing = candidates.filter { candidate in
            if !allowPreviews, candidate.source == .deezer || candidate.source == .itunes {
                return false
            }
            guard Journey.key(artist: candidate.artist, title: candidate.title) == wanted else {
                return false
            }
            if let want = foreign.durationSeconds, want > 0,
               let has = candidate.durationSeconds, has > 0 {
                return abs(want - has) <= 4
            }
            return true
        }
        guard !agreeing.isEmpty else { return nil }
        if let album = foreign.album, !album.isEmpty {
            let albumKey = PlaylistImport.normalise(album)
            if let sameAlbum = agreeing.first(where: {
                PlaylistImport.normalise($0.album) == albumKey
            }) {
                return sameAlbum
            }
        }
        return agreeing.max { a, b in
            (a.qualityParts.kbps ?? 0) < (b.qualityParts.kbps ?? 0)
        }
    }
}
