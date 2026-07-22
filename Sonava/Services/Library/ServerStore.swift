//
//  ServerStore.swift
//  AudioPlayer_test
//
//  Owns the user's self-hosted (Subsonic) connection: persistence, connect /
//  disconnect, and typed fetchers. Non-secret config lives in UserDefaults;
//  the password lives in the Keychain.
//

import SwiftUI
import Combine

@MainActor
final class ServerStore: ObservableObject {

    @Published private(set) var isConnected = false
    @Published private(set) var host: String?
    @Published var lastError: String?

    private(set) var service: SubsonicService?

    private let urlKey = "server.subsonic.url"
    private let userKey = "server.subsonic.user"
    private let passKeychainKey = "server.subsonic.password"

    init() {
        restore()
    }

    // MARK: - Lifecycle

    private func restore() {
        guard
            let urlString = UserDefaults.standard.string(forKey: urlKey),
            let url = URL(string: urlString),
            let user = UserDefaults.standard.string(forKey: userKey),
            let pass = Keychain.get(passKeychainKey)
        else { return }
        service = SubsonicService(baseURL: url, username: user, password: pass)
        host = url.host
        isConnected = true
    }

    /// Validates credentials against the server and, on success, persists them.
    func connect(urlString: String, username: String, password: String) async -> Bool {
        lastError = nil
        var normalized = urlString.trimmingCharacters(in: .whitespaces)
        if !normalized.contains("://") { normalized = "https://" + normalized }
        guard let url = URL(string: normalized) else {
            lastError = "Invalid server URL."
            return false
        }

        let candidate = SubsonicService(baseURL: url, username: username, password: password)
        do {
            let ok = try await candidate.ping()
            guard ok else {
                lastError = "Server rejected the credentials."
                return false
            }
            service = candidate
            host = url.host
            isConnected = true
            UserDefaults.standard.set(url.absoluteString, forKey: urlKey)
            UserDefaults.standard.set(username, forKey: userKey)
            Keychain.set(password, for: passKeychainKey)
            Haptics.success()
            return true
        } catch {
            lastError = "Couldn't reach the server. Check the URL and your network."
            return false
        }
    }

    func disconnect() {
        service = nil
        host = nil
        isConnected = false
        UserDefaults.standard.removeObject(forKey: urlKey)
        UserDefaults.standard.removeObject(forKey: userKey)
        Keychain.delete(passKeychainKey)
    }

    // MARK: - Fetchers

    func randomSongs() async throws -> [Song] {
        guard let service else { return [] }
        return try await service.randomSongs()
    }

    func starred() async throws -> [Song] {
        guard let service else { return [] }
        return try await service.starred()
    }

    func search(_ query: String) async throws -> [Song] {
        guard let service else { return [] }
        return try await service.search(query)
    }
}
