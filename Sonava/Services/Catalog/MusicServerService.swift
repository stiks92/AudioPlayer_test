//
//  MusicServerService.swift
//  Sonava
//
//  What the app asks of a self-hosted music server, whatever protocol the
//  server speaks.
//
//  Extracted from `SubsonicService`, which was for two years the only server
//  client and therefore *was* the interface: `ServerStore`, the browse tree,
//  merged search, the health rack and the station builder all called its
//  concrete methods. Jellyfin is the second protocol, so the surface those
//  callers actually use is now stated once, here, and the store builds
//  whichever client a connection's `kind` names.
//
//  The vocabulary deliberately stays Subsonic-flavoured (`albums(type:
//  "newest")`, "starred") because that is the language the call sites already
//  speak; each client translates it into its own wire terms.
//

import Foundation

/// Which wire protocol a saved server connection speaks.
///
/// Stored on disk with every `ServerConnection`. Records written before this
/// enum existed carry no `kind` at all, and *must* decode as `.subsonic` —
/// they were all Subsonic, and a decoding default is what keeps a user's
/// saved rack alive across the update.
enum ServerKind: String, Codable, CaseIterable, Sendable {
    case subsonic
    case jellyfin

    /// Namespace for track and album ids minted from this kind of server —
    /// `subsonic:<connection>:<track>` / `jellyfin:<connection>:<track>`.
    /// Two protocols can hand out the same internal id; the prefix keeps a
    /// Navidrome track and a Jellyfin track apart in favourites, downloads
    /// and merged search.
    var idPrefix: String { rawValue }
}

/// A self-hosted server the listener streams their own library from.
///
/// Everything here returns the app's own models (`Song`, `Album`,
/// `ServerArtist`, `ServerPlaylist`); protocol-specific DTOs never cross this
/// boundary. Conformers are value types built per request by
/// `ServerStore.service(for:)`, so they must be cheap to construct and safe
/// to send into task groups.
protocol MusicServerService: Sendable {
    /// The account the connection signs in as — the rack row shows it.
    var username: String { get }
    /// The owning connection's id, namespacing every minted track id.
    var libraryID: String { get }

    /// True when the server answered and accepted the credentials.
    func ping() async throws -> Bool
    /// How many media files the server says it has indexed, or nil if it
    /// won't say. Failures map to nil, never to an invented number.
    func scannedFileCount() async -> Int?

    func randomSongs(count: Int) async throws -> [Song]
    /// Tracks the listener favourited on the server itself.
    func starred() async throws -> [Song]
    func search(_ query: String) async throws -> [Song]

    /// `type` is Subsonic's ordering vocabulary — `newest`, `random`,
    /// `alphabeticalByName`, `frequent`, `recent`, `starred`. Non-Subsonic
    /// clients translate it; an unknown word falls back to alphabetical.
    func albums(type: String, count: Int, offset: Int) async throws -> [Album]
    func albumTracks(id: String) async throws -> [Song]
    func artists() async throws -> [ServerArtist]
    func artistAlbums(id: String) async throws -> [Album]
    func playlists() async throws -> [ServerPlaylist]
    func playlistTracks(id: String) async throws -> [Song]

    /// Marks a track as a favourite on the server, so the listener's
    /// favourites are the same set in every client they use.
    func star(id: String, starred: Bool) async throws

    /// A URL `AVPlayer` can open directly. Carries whatever auth the
    /// protocol needs in the URL itself — which is why these URLs must never
    /// travel in a shared playlist (see `PlaylistSharing`).
    func streamURL(id: String) -> URL?
    func coverArtURL(id: String?) -> URL?
}

extension MusicServerService {
    /// The defaults the concrete clients used to declare on their own
    /// methods, restated here because default arguments cannot live in a
    /// protocol and the call sites go through the existential.
    func randomSongs() async throws -> [Song] { try await randomSongs(count: 40) }

    func albums(type: String = "newest", count: Int = 60) async throws -> [Album] {
        try await albums(type: type, count: count, offset: 0)
    }
}

/// Subsonic already satisfies every requirement with the signatures it has
/// had all along — the protocol was written *from* it. No behaviour changes.
extension SubsonicService: MusicServerService {}
