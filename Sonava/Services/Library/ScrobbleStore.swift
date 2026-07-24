//
//  ScrobbleStore.swift
//  Sonava
//
//  Owns the ListenBrainz connection: the token (in the Keychain), the on/off
//  state, and the fire-and-forget submission of "now playing" and completed
//  listens. A dropped scrobble is never allowed to affect playback.
//

import Foundation
import Combine

@MainActor
final class ScrobbleStore: ObservableObject {

    @Published private(set) var isConnected = false
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: enabledKey) }
    }
    @Published var lastError: String?
    @Published private(set) var isConnecting = false

    private let service = ScrobbleService()
    private let tokenKey = "listenbrainz.token.v1"
    private let enabledKey = "listenbrainz.enabled.v1"

    init() {
        isEnabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
        isConnected = Keychain.get(tokenKey) != nil
    }

    private var token: String? { Keychain.get(tokenKey) }

    /// Should we be scrobbling right now?
    var isActive: Bool { isConnected && isEnabled }

    // MARK: - Connect

    /// Validates the token against ListenBrainz and, on success, stores it.
    func connect(token rawToken: String) async -> Bool {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return false }
        isConnecting = true
        defer { isConnecting = false }

        guard await service.validate(token: token) else {
            lastError = String(localized: "That token wasn't accepted. Check it and try again.")
            return false
        }
        Keychain.set(token, for: tokenKey)
        isConnected = true
        lastError = nil
        return true
    }

    func disconnect() {
        Keychain.delete(tokenKey)
        isConnected = false
    }

    // MARK: - Submit

    func scrobbleNowPlaying(_ song: Song) {
        guard isActive, let token, ScrobbleService.isScrobblable(song) else { return }
        Task { _ = await service.submit(listenType: .playingNow, song: song, token: token) }
    }

    /// A track finished (or was played enough to count). Submitted with the
    /// current time, which is what ListenBrainz records.
    func scrobbleListen(_ song: Song, at date: Date = Date()) {
        guard isActive, let token, ScrobbleService.isScrobblable(song) else { return }
        Task { _ = await service.submit(listenType: .single, song: song, token: token, listenedAt: date) }
    }
}
