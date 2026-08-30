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
        // Leave no credentials behind from an earlier run — passwords and
        // Jellyfin tokens alike.
        for connection in file.read() {
            _ = Keychain.delete(ServerStore.passwordKey(connection.id))
            _ = Keychain.delete(ServerStore.tokenKey(connection.id))
        }
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

    // MARK: - Protocols on one rack

    @Test("A record saved before `kind` existed decodes as Subsonic, never as nothing")
    func legacyRecordDecodesAsSubsonic() throws {
        // Byte-for-byte what the pre-Jellyfin build wrote to servers.json.
        let legacy = """
        [{"id":"OLD-1","label":"Home server","urlString":"https://music.home.arpa","username":"me"}]
        """
        let decoded = try JSONDecoder().decode([ServerConnection].self, from: Data(legacy.utf8))
        #expect(decoded.count == 1)
        #expect(decoded[0].kind == .subsonic)
        #expect(decoded[0].jellyfinUserID == nil)
        #expect(decoded[0].username == "me")
    }

    @Test("A Jellyfin connection round-trips its kind and user id through JSON")
    func jellyfinRecordRoundTrips() throws {
        let connection = ServerConnection(id: "JF-1", label: "Media box",
                                          urlString: "https://jf.home.arpa",
                                          username: "alice", kind: .jellyfin,
                                          jellyfinUserID: "user-1")
        let data = try JSONEncoder().encode([connection])
        let decoded = try JSONDecoder().decode([ServerConnection].self, from: data)
        #expect(decoded[0].kind == .jellyfin)
        #expect(decoded[0].jellyfinUserID == "user-1")
    }

    @Test("The factory builds the client each connection's kind names")
    func factoryFollowsKind() {
        let store = makeStore(pro: true)
        store.save(url: url("music.example.com"), username: "a", password: "pw")
        store.save(url: url("jelly.example.com"), username: "b", password: "pw",
                   kind: .jellyfin, jellyfinUserID: "user-1", jellyfinToken: "tok-1")

        #expect(store.service(for: store.servers[0]) is SubsonicService)
        #expect(store.service(for: store.servers[1]) is JellyfinService)
        #expect(store.service(for: store.servers[1])?.username == "b")
        // Two protocols must not be able to mint colliding track ids either.
        #expect(store.service(for: store.servers[0])?.libraryID
                != store.service(for: store.servers[1])?.libraryID)
        store.removeAll()
    }

    @Test("A Jellyfin connection without its token yields no service, not a broken one")
    func jellyfinWithoutTokenIsUnbuildable() {
        let store = makeStore(pro: true)
        store.save(url: url("jelly.example.com"), username: "b", password: "pw",
                   kind: .jellyfin, jellyfinUserID: "user-1", jellyfinToken: nil)
        #expect(store.service(for: store.servers[0]) == nil)
        store.removeAll()
    }

    @Test("Removing a Jellyfin server forgets its token along with its password")
    func removalForgetsToken() {
        let store = makeStore(pro: true)
        store.save(url: url("jelly.example.com"), username: "b", password: "pw",
                   kind: .jellyfin, jellyfinUserID: "user-1", jellyfinToken: "tok-9")
        let connection = store.servers[0]
        #expect(Keychain.get(ServerStore.tokenKey(connection.id)) == "tok-9")

        store.remove(connection)

        #expect(Keychain.get(ServerStore.tokenKey(connection.id)) == nil,
                "the token outlived the connection")
        #expect(Keychain.get(ServerStore.passwordKey(connection.id)) == nil)
    }

    @Test("A shared track re-resolves against a Jellyfin host with this listener's own session")
    func sharedTrackResolvesThroughJellyfin() {
        let store = makeStore(pro: true)
        store.save(url: url("jelly.example.com"), username: "b", password: "pw",
                   kind: .jellyfin, jellyfinUserID: "user-1", jellyfinToken: "tok-1")

        let song = store.resolveSharedTrack(host: "jelly.example.com", trackID: "tr-9",
                                            title: "T", artist: "A", album: "B",
                                            duration: 120)

        #expect(song?.id == "jellyfin:\(store.servers[0].id):tr-9")
        #expect(song?.source == .subsonic)
        #expect(song?.streamURL?.path == "/Audio/tr-9/universal")
        #expect(song?.streamURL?.query?.contains("api_key=tok-1") == true)
        store.removeAll()
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
