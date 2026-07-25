//
//  ServerStoreTests.swift
//  SonavaTests
//
//  Self-hosting is the app's differentiator, so the rules around it have to be
//  exactly right: one free connection, unlimited with Pro, and — the part users
//  would never forgive — a lapsed subscription must not delete a server they
//  spent an evening setting up.
//
//  `save` is used instead of `add` so the suite needs no live Subsonic server;
//  `add` is just `save` behind a ping.
//

import Testing
import Foundation
@testable import Sonava

@MainActor
@Suite(.serialized)
struct ServerStoreTests {

    private static let filename = "servers.test.json"

    private func makeStore(pro: Bool = false) -> ServerStore {
        let file = JSONFileStore<[ServerConnection]>(Self.filename, default: [])
        // Leave no passwords behind from an earlier run.
        for connection in file.read() { _ = Keychain.delete(ServerStore.passwordKey(connection.id)) }
        file.write([])
        UserDefaults.standard.removeObject(forKey: "server.active.v2")
        let store = ServerStore(store: file)
        store.isPro = pro
        return store
    }

    private func url(_ host: String) -> URL { URL(string: "https://\(host)")! }

    // MARK: - Free limit

    @Test("A free listener gets exactly one server")
    func freeLimit() {
        let store = makeStore()
        #expect(store.canAddServer)
        #expect(store.save(url: url("home.example.com"), username: "me", password: "pw"))

        #expect(store.canAddServer == false)
        #expect(store.save(url: url("nas.example.com"), username: "me", password: "pw") == false)
        #expect(store.servers.count == 1)
        #expect(store.lastError != nil)
    }

    @Test("Pro connects as many servers as it likes")
    func proIsUnlimited() {
        let store = makeStore(pro: true)
        for index in 0..<4 {
            #expect(store.save(url: url("server\(index).example.com"), username: "me", password: "pw"))
        }
        #expect(store.servers.count == 4)
        #expect(store.canAddServer)
        #expect(store.usableServers.count == 4)
    }

    // MARK: - Active connection

    @Test("The newest server becomes the active one")
    func newestBecomesActive() {
        let store = makeStore(pro: true)
        store.save(url: url("first.example.com"), username: "me", password: "pw")
        store.save(url: url("second.example.com"), username: "me", password: "pw")

        #expect(store.active?.displayName == "second.example.com")
        #expect(store.isConnected)
    }

    @Test("Switching the active server is remembered")
    func switchingIsRemembered() {
        let store = makeStore(pro: true)
        store.save(url: url("first.example.com"), username: "me", password: "pw")
        store.save(url: url("second.example.com"), username: "me", password: "pw")

        let first = store.servers[0]
        store.select(first)
        #expect(store.activeID == first.id)

        let reopened = ServerStore(store: JSONFileStore(Self.filename, default: []))
        reopened.isPro = true
        #expect(reopened.activeID == first.id)
        #expect(reopened.servers.count == 2)
    }

    // MARK: - Pro lapse

    @Test("Losing Pro hides the extra servers but never deletes them")
    func lapseKeepsServers() {
        let store = makeStore(pro: true)
        store.save(url: url("first.example.com"), username: "me", password: "pw")
        store.save(url: url("second.example.com"), username: "me", password: "pw")
        let second = store.servers[1]
        #expect(store.activeID == second.id)

        store.isPro = false

        // Nothing is lost…
        #expect(store.servers.count == 2)
        // …but only the free slot is reachable, and it becomes active.
        #expect(store.usableServers.count == 1)
        #expect(store.isUsable(second) == false)
        #expect(store.activeID == store.servers[0].id)

        // Re-subscribing restores everything with no re-entry of credentials.
        store.isPro = true
        #expect(store.usableServers.count == 2)
        #expect(store.isUsable(second))
    }

    @Test("A locked server cannot be selected")
    func lockedServerCannotBeSelected() {
        let store = makeStore(pro: true)
        store.save(url: url("first.example.com"), username: "me", password: "pw")
        store.save(url: url("second.example.com"), username: "me", password: "pw")
        let second = store.servers[1]
        store.isPro = false

        store.select(second)
        #expect(store.activeID == store.servers[0].id)
    }

    // MARK: - Removal

    @Test("Removing a server forgets its password and re-points the active one")
    func removal() {
        let store = makeStore(pro: true)
        store.save(url: url("first.example.com"), username: "me", password: "pw")
        store.save(url: url("second.example.com"), username: "me", password: "secret")
        let second = store.servers[1]
        let key = ServerStore.passwordKey(second.id)
        #expect(Keychain.get(key) == "secret")

        store.remove(second)

        #expect(store.servers.count == 1)
        #expect(store.activeID == store.servers[0].id)
        #expect(Keychain.get(key) == nil, "the password outlived the connection")
    }

    @Test("Removing everything leaves a clean, disconnected store")
    func removeAll() {
        let store = makeStore(pro: true)
        store.save(url: url("first.example.com"), username: "me", password: "pw")
        store.save(url: url("second.example.com"), username: "me", password: "pw")
        let keys = store.servers.map { ServerStore.passwordKey($0.id) }

        store.removeAll()

        #expect(store.servers.isEmpty)
        #expect(store.isConnected == false)
        #expect(store.service == nil)
        for key in keys { #expect(Keychain.get(key) == nil) }
    }

    // MARK: - Clients

    @Test("Each connection gets a client namespaced to its own library")
    func clientsAreNamespaced() {
        let store = makeStore(pro: true)
        store.save(url: url("first.example.com"), username: "a", password: "pw")
        store.save(url: url("second.example.com"), username: "b", password: "pw")

        let first = store.service(for: store.servers[0])
        let second = store.service(for: store.servers[1])
        #expect(first?.username == "a")
        #expect(second?.username == "b")
        // Two libraries must not be able to mint the same track id.
        #expect(first?.libraryID != second?.libraryID)
        #expect(store.service?.libraryID == store.servers[1].id)
    }

    @Test("Searching with no server returns nothing rather than failing")
    func searchWithoutServers() async throws {
        let store = makeStore()
        let results = try await store.search("anything")
        #expect(results.isEmpty)
    }

    // MARK: - Migration

    @Test("A server saved by the single-server build is carried over")
    func migratesLegacyConnection() {
        let file = JSONFileStore<[ServerConnection]>(Self.filename, default: [])
        file.write([])
        UserDefaults.standard.set("https://legacy.example.com", forKey: "server.subsonic.url")
        UserDefaults.standard.set("legacyuser", forKey: "server.subsonic.user")
        _ = Keychain.set("legacypass", for: "server.subsonic.password")

        let store = ServerStore(store: file)

        #expect(store.servers.count == 1)
        let migrated = store.servers[0]
        #expect(migrated.username == "legacyuser")
        #expect(migrated.displayName == "legacy.example.com")
        #expect(store.activeID == migrated.id)
        #expect(Keychain.get(ServerStore.passwordKey(migrated.id)) == "legacypass")

        // The old home is cleared so the migration cannot run twice.
        #expect(UserDefaults.standard.string(forKey: "server.subsonic.url") == nil)
        #expect(Keychain.get("server.subsonic.password") == nil)

        store.removeAll()
    }
}
