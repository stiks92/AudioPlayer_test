//
//  PlaylistSharing.swift
//  Sonava
//
//  Turns a playlist into a shareable `sonava://` link and back. This is the
//  viral loop: a playlist someone shares carries the whole thing — every
//  streaming track re-imports and plays on the recipient's device (local
//  files travel as entries but need the owner's audio, so they simply won't
//  play). No server involved; the playlist rides inside the link itself.
//

import Foundation

enum PlaylistSharing {

    static let scheme = "sonava"
    static let host = "playlist"

    /// The self-contained payload a link carries.
    private struct Payload: Codable {
        let name: String
        let tracks: [Song]
    }

    /// Encodes a playlist into a `sonava://playlist?d=<base64url>` link.
    static func link(for playlist: UserPlaylist) -> URL? {
        let payload = Payload(name: playlist.name, tracks: playlist.tracks)
        guard let data = try? JSONEncoder().encode(payload) else { return nil }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "d", value: base64URLEncode(data))]
        return components.url
    }

    /// Decodes an incoming link back into a playlist, or nil if it isn't ours.
    static func playlist(from url: URL) -> UserPlaylist? {
        guard url.scheme == scheme, url.host == host,
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "d" })?.value,
              let data = base64URLDecode(value),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }

        // A fresh id so importing never collides with the sender's playlist.
        return UserPlaylist(name: payload.name, tracks: payload.tracks)
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
