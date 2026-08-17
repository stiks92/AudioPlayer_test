//
//  PlaylistSharing.swift
//  Sonava
//
//  Turns a playlist into a shareable `sonava://` link and back. This is the
//  viral loop: a playlist someone shares carries the whole thing — every
//  streaming track re-imports and plays on the recipient's device.
//
//  ## Why the link carries identity, never credentials
//
//  The first version encoded whole `Song` values. A Subsonic track's
//  `streamURL` and `artworkURL` are authenticated endpoints — they carry
//  `u`, `t` (salted MD5 of the password) and `s` as query items, and that
//  token replays forever. So sharing a playlist that contained one track
//  from a home server handed working credentials for that server to every
//  person who ever saw the link, in a payload nobody would think to read.
//
//  A shared track is therefore *identity plus public URLs*: title, artist,
//  album, source, duration, and a stream URL only when the source has no
//  credentials to leak. Server tracks travel as `host` + the server's own
//  track id and are re-resolved on arrival against the recipient's *own*
//  connection to that host — so a family sharing one Navidrome still works,
//  with each side using its own login. No connection to that host means the
//  track imports as an unplayable entry, which is what a shared local file
//  has always done.
//
//  Legacy links (v1, full `Song` payloads) still import — with the same
//  redaction applied on the way in, because a link minted before this file
//  existed is exactly the one carrying someone's password token.
//

import Foundation

enum PlaylistSharing {

    static let scheme = "sonava"
    static let host = "playlist"

    /// Sources whose stream URL is a plain public link — safe to carry.
    /// `.subsonic` is deliberately absent: its URLs are authenticated.
    private static let publicSources: Set<TrackSource> = [
        // Apple Music ships identity only (a catalogue id, no stream, no
        // credentials): the receiver's own subscription resolves it — the
        // same recipient-side re-resolution the server tracks use.
        .audius, .deezer, .itunes, .radio, .podcast, .jamendo, .archive, .appleMusic
    ]

    // MARK: - Wire format

    /// One track on the wire. Short keys because the payload rides inside a
    /// URL, and a 40-track playlist is otherwise a link nothing will paste.
    private struct SharedTrack: Codable {
        let i: String            // id
        let t: String            // title
        let a: String            // artist
        let b: String            // album
        let s: String            // source raw value
        let u: URL?              // stream URL — public sources only
        let k: URL?              // artwork URL — public sources only
        let d: Double?           // duration, seconds
        let h: String?           // server host, for re-resolving server tracks
        let r: String?           // the server's own track id

        init(_ song: Song) {
            let isPublic = publicSources.contains(song.source)
            i = song.id
            t = song.title
            a = song.artist
            b = song.album
            s = song.source.rawValue
            u = isPublic ? song.streamURL : nil
            k = isPublic ? song.artworkURL : nil
            d = song.durationSeconds
            if song.source == .subsonic {
                // `subsonic:<libraryID>:<serverTrackID>` — the library id is a
                // local UUID and means nothing to the recipient; the host and
                // the server's own id are what travel.
                let parts = song.id.split(separator: ":", maxSplits: 2).map(String.init)
                r = parts.count == 3 ? parts[2] : nil
                h = song.streamURL?.host
            } else {
                r = nil
                h = nil
            }
        }

        /// Back to a `Song`, resolving server tracks against the recipient's
        /// own connection when there is one.
        func song(resolver: ServerResolver?) -> Song {
            let source = TrackSource(rawValue: s) ?? .audius
            if source == .subsonic, let host = h, let trackID = r,
               let resolved = resolver?(host, trackID, t, a, b, d) {
                return resolved
            }
            return Song(
                id: i,
                title: t,
                artist: a,
                album: b,
                source: source,
                artworkURL: k,
                streamURL: u,
                isLive: source == .radio,
                gradientHex: Palette.hex(forSeed: i),
                durationSeconds: d
            )
        }
    }

    /// Rebuilds a server track using the recipient's own credentials for that
    /// host, or nil when they have no connection to it.
    typealias ServerResolver = (_ host: String, _ trackID: String,
                                _ title: String, _ artist: String,
                                _ album: String, _ duration: Double?) -> Song?

    private struct Payload: Codable {
        let v: Int
        let name: String
        let tracks: [SharedTrack]
    }

    /// The old wire format, decoded only so existing links keep working.
    private struct LegacyPayload: Codable {
        let name: String
        let tracks: [Song]
    }

    // MARK: - Encode / decode

    /// Encodes a playlist into a `sonava://playlist?d=<base64url>` link.
    static func link(for playlist: UserPlaylist) -> URL? {
        let payload = Payload(v: 2, name: playlist.name,
                              tracks: playlist.tracks.map(SharedTrack.init))
        guard let data = try? JSONEncoder().encode(payload) else { return nil }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "d", value: base64URLEncode(data))]
        return components.url
    }

    /// Decodes an incoming link back into a playlist, or nil if it isn't ours.
    ///
    /// `resolver` is how server tracks come back to life on this device; pass
    /// nil (or return nil from it) and they import as entries that won't play.
    static func playlist(from url: URL, resolver: ServerResolver? = nil) -> UserPlaylist? {
        guard url.scheme == scheme, url.host == host,
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "d" })?.value,
              let data = base64URLDecode(value)
        else { return nil }

        if let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            // A fresh id so importing never collides with the sender's playlist.
            return UserPlaylist(name: payload.name,
                                tracks: payload.tracks.map { $0.song(resolver: resolver) })
        }
        // A link minted by an older build carries whole `Song` values —
        // including, for server tracks, the sender's replayable auth token.
        // Round-tripping through `SharedTrack` strips it on the way in.
        if let legacy = try? JSONDecoder().decode(LegacyPayload.self, from: data) {
            return UserPlaylist(name: legacy.name,
                                tracks: legacy.tracks.map { SharedTrack($0).song(resolver: resolver) })
        }
        return nil
    }

    /// A short human line to accompany the link in a share sheet.
    static func message(for playlist: UserPlaylist) -> String {
        String(localized: "\(playlist.name) — a playlist on Sonava")
    }

    // MARK: - base64url (URL-safe, no padding)

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        return Data(base64Encoded: s)
    }
}
