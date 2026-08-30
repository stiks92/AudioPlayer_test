//
//  JellyfinService.swift
//  Sonava
//
//  Client for the Jellyfin API — the second server protocol on the rack,
//  next to Subsonic. Lets a user stream their own self-hosted library from
//  the most active self-hosted media server there is. The API is fully open;
//  no vendor keys.
//
//  API: https://api.jellyfin.org — verified against the official docs and
//  the reference authorization note (gist.github.com/nielsvanvelzen/…):
//
//  * Sign-in is `POST /Users/AuthenticateByName` with `{"Username","Pw"}`
//    and an `Authorization: MediaBrowser Client="…", Device="…",
//    DeviceId="…", Version="…"` header; the response carries `AccessToken`
//    and `User.Id`. The token is long-lived and is stored in the Keychain
//    exactly as `ServerStore` stores a Subsonic password. Every later call
//    adds `Token="…"` to the same header. (`X-Emby-Authorization` is the
//    deprecated spelling — 10.11 warns on it, 10.13 removes it — so this
//    client never sends it.)
//  * The library is `GET /Items?userId=…` with `IncludeItemTypes`,
//    `Recursive`, `SortBy`, `searchTerm`, `Fields` — the modern flat route,
//    used instead of the deprecated `/Users/{userId}/Items` path.
//  * Streaming is `GET /Audio/{id}/universal`, the endpoint every official
//    client uses: it direct-plays the original file when its container is in
//    the accepted list (ours names all the audio containers a music library
//    plausibly holds) and falls back to HLS/AAC only for the exotic rest.
//    Chosen over `/Audio/{id}/stream?static=true`, which serves the same
//    bytes but has shipped with wrong Content-Types and `Accept-Ranges:
//    none` on some versions — exactly the two headers AVPlayer trips over.
//    The token rides in the URL as `api_key`, because AVPlayer and
//    AsyncImage cannot attach headers; these URLs therefore must never
//    travel in a shared playlist, and `PlaylistSharing` already strips
//    server-track URLs for exactly this reason.
//
//  Songs from here carry `source: .subsonic` deliberately — that case means
//  "the listener's own server" everywhere it is switched on (SERVER badge,
//  downloadable, station-owned tier, identity-only sharing), and every one
//  of those answers is equally true of a Jellyfin box. The `jellyfin:` id
//  prefix is what tells the tracks apart.
//

import Foundation

struct JellyfinService {
    let baseURL: URL
    /// The account name the connection signs in as. Not used on the wire —
    /// Jellyfin auths by token — but the rack row states who is signed in.
    let username: String
    /// Jellyfin scopes the library by user, not by credentials alone.
    let userID: String
    /// The long-lived session token minted at connect time.
    let accessToken: String
    /// Namespaces track ids — same job as `SubsonicService.libraryID`.
    let libraryID: String

    static let clientName = "Sonava"
    static let clientVersion = "1.0"
    static let deviceName = "iPhone"

    // MARK: - Identity

    /// A stable per-install device id. Jellyfin uses it to tell sessions
    /// apart on the server's dashboard; a fresh one per request would fill
    /// that dashboard with ghosts.
    static var deviceID: String {
        let key = "jellyfin.device.id"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let minted = UUID().uuidString
        UserDefaults.standard.set(minted, forKey: key)
        return minted
    }

    /// The `MediaBrowser` authorization header, exactly as the spec wants
    /// it: comma-separated `Key="value"` pairs. A pure function so the tests
    /// can pin the format without a server.
    static func authorizationHeader(token: String?, deviceID: String) -> String {
        var pairs = [
            "Client=\"\(clientName)\"",
            "Device=\"\(deviceName)\"",
            "DeviceId=\"\(deviceID)\"",
            "Version=\"\(clientVersion)\"",
        ]
        if let token { pairs.append("Token=\"\(token)\"") }
        return "MediaBrowser " + pairs.joined(separator: ", ")
    }

    // MARK: - Networking

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    enum AuthError: Error {
        /// The server answered and said no — wrong username or password.
        case rejected
    }

    /// What a successful sign-in yields; both halves are needed to build a
    /// working service later.
    struct AuthSession: Equatable, Sendable {
        let accessToken: String
        let userID: String
    }

    /// Signs in and returns the token + user id that every later request
    /// needs. Static because it runs before a service can exist.
    static func authenticate(baseURL: URL, username: String, password: String) async throws -> AuthSession {
        let url = baseURL.appendingPathComponent("Users")
            .appendingPathComponent("AuthenticateByName")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authorizationHeader(token: nil, deviceID: deviceID),
                         forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(AuthRequest(Username: username, Pw: password))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        // 401 is the server *rejecting the credentials*, which the connect
        // screen must say in different words than "couldn't reach it".
        if http.statusCode == 401 || http.statusCode == 403 { throw AuthError.rejected }
        guard 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }
        return try parseAuthResponse(data)
    }

    /// Split from `authenticate` so the response shape is testable against a
    /// captured payload without a network.
    static func parseAuthResponse(_ data: Data) throws -> AuthSession {
        let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)
        guard let token = decoded.accessToken, let user = decoded.user?.id else {
            throw URLError(.cannotParseResponse)
        }
        return AuthSession(accessToken: token, userID: user)
    }

    private func request(_ path: [String], _ query: [URLQueryItem] = [],
                         method: String = "GET") throws -> URLRequest {
        var url = baseURL
        for component in path { url.appendPathComponent(component) }
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let final = comps.url else { throw URLError(.badURL) }
        var request = URLRequest(url: final)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.authorizationHeader(token: accessToken, deviceID: Self.deviceID),
                         forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func get<T: Decodable>(_ path: [String], _ query: [URLQueryItem] = [],
                                   as type: T.Type) async throws -> T {
        try JSONDecoder().decode(T.self, from: await send(request(path, query)))
    }

    private func items(_ query: [URLQueryItem]) async throws -> [JellyfinItem] {
        let base = [URLQueryItem(name: "userId", value: userID)]
        return try await get(["Items"], base + query, as: JellyfinItemsPage.self).items ?? []
    }

    /// The item fields a `Song` is built from that Jellyfin does not send
    /// unless asked — the media source is where container and bit rate live.
    private static let songFields = URLQueryItem(name: "Fields", value: "MediaSources")

    // MARK: - Requests

    /// `GET /System/Info` — answers only with a valid token, so a true here
    /// means both "reachable" and "still signed in".
    func ping() async throws -> Bool {
        _ = try await send(request(["System", "Info"]))
        return true
    }

    /// `GET /Items/Counts` — `SongCount` is the honest analogue of
    /// Subsonic's scanned-files number: media items, not albums, not
    /// necessarily playable. Failures map to nil, never to a guess.
    func scannedFileCount() async -> Int? {
        try? await get(["Items", "Counts"],
                       [URLQueryItem(name: "userId", value: userID)],
                       as: JellyfinCounts.self).songCount
    }

    func randomSongs(count: Int = 40) async throws -> [Song] {
        try await items([
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "SortBy", value: "Random"),
            URLQueryItem(name: "Limit", value: String(count)),
            Self.songFields,
        ]).map(map)
    }

    func starred() async throws -> [Song] {
        try await items([
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Filters", value: "IsFavorite"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            Self.songFields,
        ]).map(map)
    }

    func search(_ query: String) async throws -> [Song] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await items([
            URLQueryItem(name: "searchTerm", value: trimmed),
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Limit", value: "50"),
            Self.songFields,
        ]).map(map)
    }

    /// Subsonic's shelf vocabulary, translated. An unknown word falls back
    /// to alphabetical rather than failing — a shelf in the wrong order
    /// beats no shelf.
    func albums(type: String = "newest", count: Int = 60, offset: Int = 0) async throws -> [Album] {
        var query = [
            URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Limit", value: String(count)),
            URLQueryItem(name: "StartIndex", value: String(offset)),
        ]
        switch type {
        case "newest":
            query += [URLQueryItem(name: "SortBy", value: "DateCreated"),
                      URLQueryItem(name: "SortOrder", value: "Descending")]
        case "recent":
            query += [URLQueryItem(name: "SortBy", value: "DatePlayed"),
                      URLQueryItem(name: "SortOrder", value: "Descending")]
        case "frequent":
            query += [URLQueryItem(name: "SortBy", value: "PlayCount"),
                      URLQueryItem(name: "SortOrder", value: "Descending")]
        case "random":
            query.append(URLQueryItem(name: "SortBy", value: "Random"))
        case "starred":
            query += [URLQueryItem(name: "Filters", value: "IsFavorite"),
                      URLQueryItem(name: "SortBy", value: "SortName")]
        default:
            query += [URLQueryItem(name: "SortBy", value: "SortName"),
                      URLQueryItem(name: "SortOrder", value: "Ascending")]
        }
        return try await items(query).map(mapAlbum)
    }

    /// One album's tracks, in record order — disc first, then track number.
    func albumTracks(id: String) async throws -> [Song] {
        try await items([
            URLQueryItem(name: "ParentId", value: id),
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "SortBy", value: "ParentIndexNumber,IndexNumber,SortName"),
            Self.songFields,
        ]).map(map)
    }

    /// `GET /Artists` — every performing artist in the user's library, the
    /// dedicated route rather than an `/Items` filter.
    func artists() async throws -> [ServerArtist] {
        let page = try await get(["Artists"], [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "SortBy", value: "SortName"),
        ], as: JellyfinItemsPage.self)
        return (page.items ?? []).map {
            ServerArtist(id: $0.id, name: $0.name ?? "Unknown artist",
                         // Jellyfin's artist rows don't always carry a count;
                         // 0 is shown as "0 albums" rather than invented.
                         albumCount: $0.albumCount ?? $0.childCount ?? 0,
                         artworkURL: primaryImageURL(for: $0))
        }
    }

    func artistAlbums(id: String) async throws -> [Album] {
        try await items([
            URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "ArtistIds", value: id),
            URLQueryItem(name: "SortBy", value: "ProductionYear,SortName"),
            URLQueryItem(name: "SortOrder", value: "Descending"),
        ]).map(mapAlbum)
    }

    func playlists() async throws -> [ServerPlaylist] {
        try await items([
            URLQueryItem(name: "IncludeItemTypes", value: "Playlist"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "SortBy", value: "SortName"),
        ]).map {
            ServerPlaylist(id: $0.id, name: $0.name ?? "Playlist",
                           songCount: $0.childCount ?? 0,
                           duration: $0.runTimeTicks.map { Double($0) / 10_000_000 },
                           artworkURL: primaryImageURL(for: $0))
        }
    }

    /// `GET /Playlists/{id}/Items` — the dedicated route keeps the order the
    /// listener gave the playlist, which `/Items?ParentId=` does not promise.
    func playlistTracks(id: String) async throws -> [Song] {
        let page = try await get(["Playlists", id, "Items"], [
            URLQueryItem(name: "userId", value: userID),
            Self.songFields,
        ], as: JellyfinItemsPage.self)
        return (page.items ?? []).map(map)
    }

    /// `POST`/`DELETE /Users/{userId}/FavoriteItems/{id}` — favourites are
    /// one set across every client the listener uses.
    func star(id: String, starred: Bool) async throws {
        _ = try await send(request(["Users", userID, "FavoriteItems", id],
                                   method: starred ? "POST" : "DELETE"))
    }

    // MARK: - URLs

    func streamURL(id: String) -> URL? {
        var url = baseURL
        for component in ["Audio", id, "universal"] { url.appendPathComponent(component) }
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "UserId", value: userID),
            URLQueryItem(name: "DeviceId", value: Self.deviceID),
            URLQueryItem(name: "api_key", value: accessToken),
            // Every container a music library plausibly holds, so the server
            // direct-plays the original file rather than transcoding it —
            // the same "the bytes you ripped" promise Subsonic's `stream`
            // makes, and what keeps offline downloads real files.
            URLQueryItem(name: "Container",
                         value: "opus,webm|opus,mp3,aac,m4a|aac,m4b|aac,flac,webma,webm|webma,wav,ogg,alac,m4a|alac,aiff"),
            // The escape hatch for anything exotic: transcode to AAC in HLS,
            // which AVPlayer plays from the same URL.
            URLQueryItem(name: "TranscodingContainer", value: "ts"),
            URLQueryItem(name: "TranscodingProtocol", value: "hls"),
            URLQueryItem(name: "AudioCodec", value: "aac"),
        ]
        return comps.url
    }

    func coverArtURL(id: String?) -> URL? {
        guard let id else { return nil }
        var url = baseURL
        for component in ["Items", id, "Images", "Primary"] { url.appendPathComponent(component) }
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "fillWidth", value: "512"),
            URLQueryItem(name: "quality", value: "90"),
            // Some servers gate images behind auth; the token costs nothing
            // when they don't.
            URLQueryItem(name: "api_key", value: accessToken),
        ]
        return comps.url
    }

    /// The sleeve for an item: its own primary image when it has one, the
    /// album's otherwise (tracks usually don't carry their own art tag).
    private func primaryImageURL(for item: JellyfinItem) -> URL? {
        if item.imageTags?.primary != nil { return coverArtURL(id: item.id) }
        if item.albumPrimaryImageTag != nil, let albumID = item.albumId {
            return coverArtURL(id: albumID)
        }
        return nil
    }

    // MARK: - Mapping

    private func map(_ item: JellyfinItem) -> Song {
        let media = item.mediaSources?.first
        return Song(
            id: "jellyfin:\(libraryID):\(item.id)",
            title: item.name ?? "Untitled",
            artist: item.artists?.first ?? item.albumArtist ?? "Unknown artist",
            album: item.album ?? "Library",
            source: .subsonic,
            fileExtension: media?.container ?? "",
            artworkURL: primaryImageURL(for: item),
            streamURL: streamURL(id: item.id),
            gradientHex: Palette.hex(forSeed: item.id),
            durationSeconds: item.runTimeTicks.map { Double($0) / 10_000_000 },
            trackNumber: item.indexNumber,
            year: item.productionYear,
            // Jellyfin reports bits per second; the app speaks kbit/s.
            bitRate: media?.bitrate.map { $0 / 1000 },
            credits: item.artistItems?.map { TrackCredit(id: $0.id, name: $0.name) } ?? [],
            isStarredOnServer: item.userData?.isFavorite ?? false
        )
    }

    private func mapAlbum(_ item: JellyfinItem) -> Album {
        Album(id: "jellyfin:\(libraryID):\(item.id)",
              title: item.name ?? "Album",
              artist: item.albumArtist ?? item.artists?.first ?? "Unknown artist",
              songs: [],
              year: item.productionYear,
              artworkURL: primaryImageURL(for: item),
              serverID: item.id,
              trackCountHint: item.childCount)
    }
}

// MARK: - DTOs

/// Every list answer arrives as `{"Items":[…],"TotalRecordCount":n}`.
private struct JellyfinItemsPage: Decodable {
    let items: [JellyfinItem]?
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

/// The slice of Jellyfin's `BaseItemDto` the app reads — one DTO for songs,
/// albums, artists and playlists, because the server sends them all in the
/// same envelope. Everything optional: a DTO that only decodes when the
/// server sends exactly what we imagined breaks on the next server.
private struct JellyfinItem: Decodable {
    let id: String
    let name: String?
    let album: String?
    let albumId: String?
    let albumArtist: String?
    let artists: [String]?
    let artistItems: [JellyfinNameRef]?
    /// Duration in ticks — 10,000,000 per second.
    let runTimeTicks: Int64?
    let indexNumber: Int?
    let productionYear: Int?
    let childCount: Int?
    let albumCount: Int?
    let imageTags: JellyfinImageTags?
    let albumPrimaryImageTag: String?
    let userData: JellyfinUserData?
    let mediaSources: [JellyfinMediaSource]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case album = "Album"
        case albumId = "AlbumId"
        case albumArtist = "AlbumArtist"
        case artists = "Artists"
        case artistItems = "ArtistItems"
        case runTimeTicks = "RunTimeTicks"
        case indexNumber = "IndexNumber"
        case productionYear = "ProductionYear"
        case childCount = "ChildCount"
        case albumCount = "AlbumCount"
        case imageTags = "ImageTags"
        case albumPrimaryImageTag = "AlbumPrimaryImageTag"
        case userData = "UserData"
        case mediaSources = "MediaSources"
    }
}

private struct JellyfinNameRef: Decodable {
    let id: String
    let name: String
    enum CodingKeys: String, CodingKey { case id = "Id", name = "Name" }
}

private struct JellyfinImageTags: Decodable {
    let primary: String?
    enum CodingKeys: String, CodingKey { case primary = "Primary" }
}

private struct JellyfinUserData: Decodable {
    let isFavorite: Bool?
    enum CodingKeys: String, CodingKey { case isFavorite = "IsFavorite" }
}

private struct JellyfinMediaSource: Decodable {
    let container: String?
    /// Bits per second.
    let bitrate: Int?
    enum CodingKeys: String, CodingKey { case container = "Container", bitrate = "Bitrate" }
}

private struct JellyfinCounts: Decodable {
    let songCount: Int?
    enum CodingKeys: String, CodingKey { case songCount = "SongCount" }
}

private struct AuthRequest: Encodable {
    let Username: String
    let Pw: String
}

private struct AuthResponse: Decodable {
    let accessToken: String?
    let user: AuthUser?
    enum CodingKeys: String, CodingKey { case accessToken = "AccessToken", user = "User" }

    struct AuthUser: Decodable {
        let id: String?
        enum CodingKeys: String, CodingKey { case id = "Id" }
    }
}

extension JellyfinService: MusicServerService {}

#if DEBUG
extension JellyfinService {
    /// Decoding hooks for tests — same rationale as Subsonic's: the mapping
    /// from a server's JSON to the app's models is where a client actually
    /// breaks, so it is exercised against captured payloads, without the
    /// network.
    private func decodePage(_ json: String) throws -> [JellyfinItem] {
        try JSONDecoder().decode(JellyfinItemsPage.self, from: Data(json.utf8)).items ?? []
    }

    func songsForTesting(json: String) throws -> [Song] {
        try decodePage(json).map(map)
    }

    func albumsForTesting(json: String) throws -> [Album] {
        try decodePage(json).map(mapAlbum)
    }

    func artistsForTesting(json: String) throws -> [ServerArtist] {
        try decodePage(json).map {
            ServerArtist(id: $0.id, name: $0.name ?? "Unknown artist",
                         albumCount: $0.albumCount ?? $0.childCount ?? 0,
                         artworkURL: primaryImageURL(for: $0))
        }
    }

    func playlistsForTesting(json: String) throws -> [ServerPlaylist] {
        try decodePage(json).map {
            ServerPlaylist(id: $0.id, name: $0.name ?? "Playlist",
                           songCount: $0.childCount ?? 0,
                           duration: $0.runTimeTicks.map { Double($0) / 10_000_000 },
                           artworkURL: primaryImageURL(for: $0))
        }
    }
}
#endif
