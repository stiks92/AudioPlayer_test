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

    /// The host on its own, for the screen that is about infrastructure. A
    /// named connection otherwise hides the one fact a self-hoster navigates
    /// by — "Home server" tells you nothing about which box answered.
    var host: String { url?.host ?? urlString }

    /// Whether the connection is encrypted. Shown rather than assumed: a plain
    /// `http://` server on a LAN is a legitimate setup, and quietly implying a
    /// padlock over it would be a lie about the user's own network.
    var isSecure: Bool { url?.scheme?.lowercased() == "https" }

    /// The address as typed, scheme included, on every row.
    ///
    /// The first attempt showed `http://` only on the insecure row, on the
    /// theory that the exception is what needs stating. A review pointed out
    /// what that actually asks of the reader: the *absence* of a prefix means
    /// encrypted — a negative signal nothing on the screen teaches, on two
    /// rows out of three. Spelling both costs one word and asks nothing.
    var addressLine: String {
        guard let scheme = url?.scheme?.lowercased() else { return host }
        return "\(scheme)://\(host)"
    }
}

/// What we actually know about a connection, as opposed to what the screen
/// could invent about it.
///
/// Every field here is either measured or absent. `files` is nil until a server
/// answers `getScanStatus`, and a nil renders as nothing at all — a row never
/// shows a placeholder number, because a fabricated library size on the screen
/// that exists to make self-hosters trust their own setup is worse than a
/// blank.
struct ServerHealth: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case unknown
        case checking
        case online
        case unreachable
    }

    var state: State = .unknown
    /// Round trip of the last successful ping, in seconds.
    var latency: TimeInterval?
    /// Media files the server reports having indexed, when it says.
    var files: Int?
    var checkedAt: Date?
}

private extension Duration {
    /// `components` is (seconds, attoseconds); the row wants one number.
    var seconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}

@MainActor
final class ServerStore: ObservableObject {

    @Published private(set) var servers: [ServerConnection] = []
    @Published private(set) var activeID: String?
    @Published var lastError: String?

    /// Measured reachability per connection id. Deliberately not persisted:
    /// a status carried over from a previous launch is a claim about the
    /// network as it was, presented as if it were now.
    @Published private(set) var healthByID: [String: ServerHealth] = [:]

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

    // MARK: - Reachability

    func health(for connection: ServerConnection) -> ServerHealth {
        healthByID[connection.id] ?? ServerHealth()
    }

    /// Pings every saved connection at once and records what came back.
    ///
    /// Locked connections are probed too. A lapsed subscriber deciding whether
    /// to renew should be able to see that their other libraries are still
    /// there and still answering; hiding that would make the gate feel like
    /// confiscation.
    func refreshHealth() async {
        #if DEBUG
        if isDemoSeeded { return }
        #endif
        let probes: [(String, SubsonicService)] = servers.compactMap { connection in
            service(for: connection).map { (connection.id, $0) }
        }
        guard !probes.isEmpty else { return }

        for (id, _) in probes {
            healthByID[id, default: ServerHealth()].state = .checking
        }

        await withTaskGroup(of: (String, ServerHealth).self) { group in
            for (id, service) in probes {
                group.addTask {
                    let clock = ContinuousClock()
                    let started = clock.now
                    let reachable = (try? await service.ping()) ?? false
                    let elapsed = clock.now - started
                    guard reachable else {
                        return (id, ServerHealth(state: .unreachable, checkedAt: Date()))
                    }
                    return (id, ServerHealth(
                        state: .online,
                        latency: elapsed.seconds,
                        files: await service.scannedFileCount(),
                        checkedAt: Date()
                    ))
                }
            }
            for await (id, result) in group { healthByID[id] = result }
        }
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
        healthByID[connection.id] = nil
        if activeID == connection.id { activeID = usableServers.first?.id }
        persist()
    }

    /// Removes every connection — the "start over" escape hatch.
    func removeAll() {
        for connection in servers { _ = Keychain.delete(Self.passwordKey(connection.id)) }
        servers = []
        healthByID = [:]
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
    /// Set when the connections came from `-seedServers`. Those hosts do not
    /// resolve, so probing them would paint the whole rack red — which is a
    /// true statement about `nas.local` and a useless one about the design.
    /// Never set outside a debug launch argument.
    private(set) var isDemoSeeded = false

    /// Saves plausible connections without contacting anything, so the
    /// multi-server UI (and its Pro gate) can be driven in UI tests. Debug
    /// builds only, and only ever reached from a launch argument.
    func seedDemoServers(count: Int) {
        removeAll()
        isDemoSeeded = true
        let wasPro = isPro
        isPro = true                    // seeding bypasses the gate it is testing
        // Hosts a self-hoster would recognise, rather than server1/2/3: the
        // rack is meant to look like somebody's actual infrastructure.
        let hosts = ["navidrome.home.arpa", "nas.local", "airsonic.example.net"]
        let labels = ["Home server", "Attic NAS", "Friend's library"]
        for index in 0..<count {
            let host = hosts[index % hosts.count]
            let scheme = index == 1 ? "http" : "https"   // a LAN box on plain http is a real setup
            guard let url = URL(string: "\(scheme)://\(host)") else { continue }
            save(url: url, username: index == 2 ? "guest" : "listener", password: "demo",
                 label: labels[index % labels.count])
        }
        if let first = servers.first { activeID = first.id }
        persist()
        isPro = wasPro

        // Seeded health, because these hosts do not exist and a real probe
        // would say so. Fixed values, not random ones — a UI test that reads a
        // latency must get the same number every run. The third is deliberately
        // unreachable: a rack that can only draw its happy state is a rack
        // whose failure state has never been looked at.
        let seeded: [ServerHealth] = [
            ServerHealth(state: .online, latency: 0.012, files: 12_431, checkedAt: Date()),
            ServerHealth(state: .online, latency: 0.048, files: 3_207, checkedAt: Date()),
            ServerHealth(state: .unreachable, checkedAt: Date())
        ]
        for (index, connection) in servers.enumerated() {
            healthByID[connection.id] = seeded[index % seeded.count]
        }
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
