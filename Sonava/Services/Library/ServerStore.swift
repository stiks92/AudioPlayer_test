//
//  ServerStore.swift
//  Sonava
//
//  The user's self-hosted (Subsonic) libraries. Non-secret config lives in a
//  JSON file; every password lives in the Keychain under its connection's id.
//
//  One connection is free. Connecting several — a home server and a NAS, work
//  and home, yours and a friend's — is a Sonava Pro perk, and Pro also searches
//  all of them at once. Lapsing never deletes a saved connection: the extras
//  simply stop being reachable until the subscription comes back.
//

import SwiftUI
import Combine

/// One saved server. The password is deliberately absent — it is in the
/// Keychain, keyed by `id`.
struct ServerConnection: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var label: String
    var urlString: String
    var username: String

    var url: URL? { URL(string: urlString) }
    /// What the UI shows: the host, falling back to whatever was typed.
    var displayName: String { label.isEmpty ? (url?.host ?? urlString) : label }
}

@MainActor
final class ServerStore: ObservableObject {

    @Published private(set) var servers: [ServerConnection] = []
    @Published private(set) var activeID: String?
    @Published var lastError: String?

    /// Mirrors the subscription, so call sites can ask "search my library"
    /// without also having to know the entitlement rules.
    @Published var isPro = false {
        didSet { if !isPro { fallBackToFreeServer() } }
    }

    /// How many connections a free listener may use.
    static let freeLimit = 1

    private let store: JSONFileStore<[ServerConnection]>
    private let activeKey = "server.active.v2"

    init(store: JSONFileStore<[ServerConnection]> = JSONFileStore("servers.json", default: [])) {
        self.store = store
        servers = store.read()
        migrateLegacySingleServer()
        let saved = UserDefaults.standard.string(forKey: activeKey)
        activeID = servers.contains { $0.id == saved } ? saved : servers.first?.id
    }

    // MARK: - Derived state

    var active: ServerConnection? { servers.first { $0.id == activeID } }
    var isConnected: Bool { active != nil }
    var host: String? { active?.displayName }

    /// The connections this listener may actually use right now. Free keeps the
    /// first; the rest stay on disk, greyed out, until Pro returns.
    var usableServers: [ServerConnection] {
        isPro ? servers : Array(servers.prefix(Self.freeLimit))
    }

    func isUsable(_ connection: ServerConnection) -> Bool {
        usableServers.contains { $0.id == connection.id }
    }

    var canAddServer: Bool { isPro || servers.count < Self.freeLimit }

    /// The active connection's client, or nil if it can't be built.
    var service: SubsonicService? { active.flatMap(service(for:)) }

    func service(for connection: ServerConnection) -> SubsonicService? {
        guard let url = connection.url,
              let password = Keychain.get(Self.passwordKey(connection.id))
        else { return nil }
        return SubsonicService(baseURL: url, username: connection.username,
                               password: password, libraryID: connection.id)
    }

    // MARK: - Editing

    /// Validates credentials against the server and, on success, saves them.
    @discardableResult
    func add(urlString: String, username: String, password: String, label: String = "") async -> Bool {
        lastError = nil
        guard canAddServer else {
            lastError = String(localized: "Connecting more than one server needs Sonava Pro.")
            return false
        }
        var normalized = urlString.trimmingCharacters(in: .whitespaces)
        if !normalized.contains("://") { normalized = "https://" + normalized }
        guard let url = URL(string: normalized), url.host != nil else {
            lastError = String(localized: "Invalid server URL.")
            return false
        }

        let id = UUID().uuidString
        let candidate = SubsonicService(baseURL: url, username: username,
                                        password: password, libraryID: id)
        do {
            guard try await candidate.ping() else {
                lastError = String(localized: "Server rejected the credentials.")
                return false
            }
        } catch {
            lastError = String(localized: "Couldn't reach the server. Check the URL and your network.")
            return false
        }

        guard save(id: id, url: url, username: username, password: password, label: label) else {
            return false
        }
        Haptics.success()
        return true
    }

    /// Persists an already-validated connection and makes it active.
    ///
    /// Split out from `add` so the credential check and the bookkeeping can be
    /// reasoned about — and tested — without needing a live server.
    @discardableResult
    func save(
        id: String = UUID().uuidString,
        url: URL,
        username: String,
        password: String,
        label: String = ""
    ) -> Bool {
        guard canAddServer else {
            lastError = String(localized: "Connecting more than one server needs Sonava Pro.")
            return false
        }
        guard Keychain.set(password, for: Self.passwordKey(id)) else {
            lastError = String(localized: "Couldn't save the password securely.")
            return false
        }
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        servers.append(
            ServerConnection(id: id,
                             label: trimmedLabel.isEmpty ? (url.host ?? url.absoluteString) : trimmedLabel,
                             urlString: url.absoluteString,
                             username: username)
        )
        activeID = id
        persist()
        return true
    }

    func select(_ connection: ServerConnection) {
        guard isUsable(connection) else { return }
        activeID = connection.id
        UserDefaults.standard.set(connection.id, forKey: activeKey)
    }

    func remove(_ connection: ServerConnection) {
        _ = Keychain.delete(Self.passwordKey(connection.id))
        servers.removeAll { $0.id == connection.id }
        if activeID == connection.id { activeID = usableServers.first?.id }
        persist()
    }

    /// Removes every connection — the "start over" escape hatch.
    func removeAll() {
        for connection in servers { _ = Keychain.delete(Self.passwordKey(connection.id)) }
        servers = []
        activeID = nil
        persist()
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

    /// Searches every usable library at once. With one server this is just that
    /// server (and its errors surface); with several, a slow or offline library
    /// can't hide the results from the others.
    func search(_ query: String) async throws -> [Song] {
        let services = usableServers.compactMap(service(for:))
        guard let first = services.first else { return [] }
        guard services.count > 1 else { return try await first.search(query) }

        return await withTaskGroup(of: [Song].self) { group in
            for service in services {
                group.addTask { (try? await service.search(query)) ?? [] }
            }
            var merged: [Song] = []
            var seen = Set<String>()
            for await songs in group {
                for song in songs where seen.insert(song.id).inserted {
                    merged.append(song)
                }
            }
            return merged
        }
    }

    // MARK: - Persistence

    private func persist() {
        store.write(servers)
        if let activeID {
            UserDefaults.standard.set(activeID, forKey: activeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeKey)
        }
    }

    static func passwordKey(_ id: String) -> String { "server.password.\(id)" }

    /// Pro gates *how many* servers you can use, not whether saved connections
    /// survive. On lapse the extras stay on disk and the active one falls back
    /// to the free slot, so nothing is silently deleted.
    private func fallBackToFreeServer() {
        guard let first = servers.first, activeID != first.id else { return }
        activeID = first.id
        UserDefaults.standard.set(first.id, forKey: activeKey)
    }

    #if DEBUG
    /// Saves plausible connections without contacting anything, so the
    /// multi-server UI (and its Pro gate) can be driven in UI tests. Debug
    /// builds only, and only ever reached from a launch argument.
    func seedDemoServers(count: Int) {
        removeAll()
        let wasPro = isPro
        isPro = true                    // seeding bypasses the gate it is testing
        for index in 0..<count {
            guard let url = URL(string: "https://server\(index + 1).example.com") else { continue }
            save(url: url, username: "listener", password: "demo",
                 label: index == 0 ? "Home server" : "Server \(index + 1)")
        }
        if let first = servers.first { activeID = first.id }
        persist()
        isPro = wasPro
    }
    #endif

    // MARK: - Migration

    private static let legacyURLKey = "server.subsonic.url"
    private static let legacyUserKey = "server.subsonic.user"
    private static let legacyPasswordKey = "server.subsonic.password"

    /// Folds a connection saved by the single-server build into the list, so
    /// upgrading doesn't silently log the user out of their own library.
    private func migrateLegacySingleServer() {
        let defaults = UserDefaults.standard
        guard servers.isEmpty,
              let urlString = defaults.string(forKey: Self.legacyURLKey),
              let username = defaults.string(forKey: Self.legacyUserKey),
              let password = Keychain.get(Self.legacyPasswordKey),
              let url = URL(string: urlString)
        else { return }

        let id = UUID().uuidString
        guard Keychain.set(password, for: Self.passwordKey(id)) else { return }
        servers = [ServerConnection(id: id, label: url.host ?? urlString,
                                    urlString: urlString, username: username)]
        activeID = id
        persist()

        _ = Keychain.delete(Self.legacyPasswordKey)
        defaults.removeObject(forKey: Self.legacyURLKey)
        defaults.removeObject(forKey: Self.legacyUserKey)
    }
}
