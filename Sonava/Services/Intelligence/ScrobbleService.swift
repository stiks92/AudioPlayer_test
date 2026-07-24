//
//  ScrobbleService.swift
//  Sonava
//
//  Scrobbling to ListenBrainz — an audiophile-favourite, and a Sonava Pro
//  feature. ListenBrainz is the open, privacy-respecting alternative to
//  Last.fm: a user token, no third-party SDK, JSON over HTTPS.
//
//  Docs: https://listenbrainz.readthedocs.io/en/latest/users/api/core.html
//

import Foundation

/// Builds and submits ListenBrainz payloads. The payload building is pure so it
/// can be unit-tested without the network.
struct ScrobbleService: Sendable {

    enum ListenType: String {
        case playingNow = "playing_now"
        case single
    }

    private let endpoint = URL(string: "https://api.listenbrainz.org/1/submit-listens")!

    /// The JSON body ListenBrainz expects. `listenedAt` is omitted for
    /// "playing_now" (the spec requires it absent) and set for a real listen.
    static func payload(listenType: ListenType, song: Song, listenedAt: Date?) -> [String: Any] {
        var trackMetadata: [String: Any] = [
            "artist_name": song.artist,
            "track_name": song.title,
        ]
        if !song.album.isEmpty {
            trackMetadata["release_name"] = song.album
        }
        trackMetadata["additional_info"] = [
            "media_player": "Sonava",
            "submission_client": "Sonava",
            "music_service_name": song.source.rawValue,
        ]

        var listen: [String: Any] = ["track_metadata": trackMetadata]
        if listenType == .single, let listenedAt {
            listen["listened_at"] = Int(listenedAt.timeIntervalSince1970)
        }

        return ["listen_type": listenType.rawValue, "payload": [listen]]
    }

    /// Only full-length music with real metadata is worth scrobbling — never
    /// radio or podcasts (excluded by source, not just the live flag) and never
    /// 30-second previews.
    static func isScrobblable(_ song: Song) -> Bool {
        guard song.isFullLength, !song.isLive,
              song.source != .radio, song.source != .podcast,
              !song.artist.trimmingCharacters(in: .whitespaces).isEmpty,
              !song.title.trimmingCharacters(in: .whitespaces).isEmpty
        else { return false }
        return true
    }

    /// Submits a listen. Returns whether it was accepted; failures are swallowed
    /// by the caller (a dropped scrobble must never interrupt playback).
    func submit(listenType: ListenType, song: Song, token: String, listenedAt: Date? = nil) async -> Bool {
        guard Self.isScrobblable(song) else { return false }
        let body = Self.payload(listenType: listenType, song: song, listenedAt: listenedAt)
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return false }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        request.timeoutInterval = 12

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    /// Validates a token by submitting nothing meaningful — the validate-token
    /// endpoint — so the user gets immediate feedback when connecting.
    func validate(token: String) async -> Bool {
        var request = URLRequest(url: URL(string: "https://api.listenbrainz.org/1/validate-token")!)
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return json["valid"] as? Bool == true
    }
}
