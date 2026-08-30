//
//  ArchiveService.swift
//  Sonava
//
//  The Internet Archive's audio stacks — live concert recordings the bands
//  themselves allow taping of (etree), Creative Commons netlabels, and
//  digitised 78 rpm shellac. Keyless, legal, full-length streams.
//
//  Two calls per question: `advancedsearch` finds *items* (a concert, a
//  netlabel release, a shellac side), then the `metadata` API lists each
//  item's files, and every derived MP3 becomes a Song with a direct
//  `/download/…` stream URL. The mapping is split into static functions so
//  tests exercise it against captured payloads without a network.
//
//  Docs: https://archive.org/developers/  (advancedsearch + metadata APIs)
//

import Foundation

actor ArchiveService: TrackProvider {

    static let shared = ArchiveService()

    nonisolated let id = "archive"
    nonisolated let displayName = "Internet Archive"

    /// The stacks worth a music player's time: concert tapes, netlabels,
    /// 78 rpm transfers. All freely streamable by the collections' own terms.
    private static let collections =
        "(collection:(etree) OR collection:(netlabels) OR collection:(78rpm))"

    // MARK: TrackProvider

    func trending() async throws -> [Song] {
#if DEBUG
        if DemoCatalog.isActive { return DemoCatalog.trending }
        #endif
        let query = Net.encode("\(Self.collections) AND format:(MP3)")
        let url = URL(string: "https://archive.org/advancedsearch.php?q=\(query)"
            + "&fl%5B%5D=identifier&fl%5B%5D=title&fl%5B%5D=creator&fl%5B%5D=year"
            + "&rows=6&output=json&sort%5B%5D=" + Net.encode("week desc"))!
        let envelope = try await Net.getJSON(url, as: ArchiveSearchEnvelope.self)
        return await songs(for: envelope.response.docs)
    }

    func search(_ query: String) async throws -> [Song] {
#if DEBUG
        if DemoCatalog.isActive { return DemoCatalog.searchResults }
        #endif
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let term = Net.encode("\(trimmed) AND \(Self.collections) AND format:(MP3)")
        let url = URL(string: "https://archive.org/advancedsearch.php?q=\(term)"
            + "&fl%5B%5D=identifier&fl%5B%5D=title&fl%5B%5D=creator&fl%5B%5D=year"
            + "&rows=6&output=json")!
        let envelope = try await Net.getJSON(url, as: ArchiveSearchEnvelope.self)
        return await songs(for: envelope.response.docs)
    }

    // MARK: - Item files

    /// One metadata call per found item, in parallel; each item contributes a
    /// handful of tracks so one 30-song concert doesn't drown the list.
    private func songs(for docs: [ArchiveDoc]) async -> [Song] {
        await withTaskGroup(of: (Int, [Song]).self) { group in
            for (index, doc) in docs.enumerated() {
                group.addTask {
                    let url = URL(string: "https://archive.org/metadata/\(Net.encode(doc.identifier))")!
                    guard let metadata = try? await Net.getJSON(url, as: ArchiveMetadataEnvelope.self) else {
                        return (index, [])
                    }
                    return (index, Array(Self.songs(from: metadata, fallback: doc).prefix(5)))
                }
            }
            var buckets: [(Int, [Song])] = []
            for await bucket in group { buckets.append(bucket) }
            return buckets.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
    }

    // MARK: - Mapping (static so tests reach it without the network)

    static func docs(fromSearchJSON data: Data) throws -> [ArchiveDoc] {
        try JSONDecoder().decode(ArchiveSearchEnvelope.self, from: data).response.docs
    }

    static func songs(fromMetadataJSON data: Data, fallback: ArchiveDoc? = nil) throws -> [Song] {
        let envelope = try JSONDecoder().decode(ArchiveMetadataEnvelope.self, from: data)
        return songs(from: envelope, fallback: fallback)
    }

    static func songs(from envelope: ArchiveMetadataEnvelope, fallback: ArchiveDoc? = nil) -> [Song] {
        let meta = envelope.metadata
        guard let identifier = meta?.identifier ?? fallback?.identifier else { return [] }
        let itemTitle = meta?.title ?? fallback?.title
        let itemCreator = meta?.creator ?? fallback?.creator
        let year = meta?.year ?? fallback?.year
        let artwork = URL(string: "https://archive.org/services/img/\(Net.encode(identifier))")

        return envelope.files.compactMap { file in
            // Only derived MP3s: the FLAC originals would double every track,
            // and AVPlayer streams MP3 everywhere.
            guard let format = file.format, format.localizedCaseInsensitiveContains("mp3"),
                  !file.name.isEmpty else { return nil }
            guard let encodedName = file.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let stream = URL(string: "https://archive.org/download/\(Net.encode(identifier))/\(encodedName)")
            else { return nil }
            let title = file.title
                ?? ((file.name as NSString).lastPathComponent as NSString).deletingPathExtension
            return Song(
                id: "archive:\(identifier)/\(file.name)",
                title: title,
                artist: file.creator ?? itemCreator ?? "Internet Archive",
                album: file.album ?? itemTitle ?? "Internet Archive",
                source: .archive,
                fileExtension: (file.name as NSString).pathExtension.lowercased(),
                artworkURL: artwork,
                streamURL: stream,
                gradientHex: Palette.hex(forSeed: identifier),
                durationSeconds: seconds(fromLength: file.length),
                trackNumber: trackNumber(from: file.track),
                year: year,
                bitRate: file.bitrate.flatMap(Double.init).flatMap { $0 > 0 ? Int($0) : nil }
            )
        }
    }

    /// The metadata API reports length as "05:23", "1:02:33" or "39.5"
    /// depending on the deriver's mood. All of them are seconds in the end.
    static func seconds(fromLength raw: String?) -> Double? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if raw.contains(":") {
            let parts = raw.split(separator: ":").map { Double($0) }
            guard parts.allSatisfy({ $0 != nil }), !parts.isEmpty else { return nil }
            let value = parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
            return value > 0 ? value : nil
        }
        guard let value = Double(raw), value > 0 else { return nil }
        return value
    }

    /// "01", "5" or "5/12" — the position, never the disc arithmetic.
    static func trackNumber(from raw: String?) -> Int? {
        guard let raw else { return nil }
        return raw.split(separator: "/").first.flatMap { Int($0) }
    }
}

// MARK: - DTOs

struct ArchiveSearchEnvelope: Decodable {
    let response: ArchiveSearchResponse
}

struct ArchiveSearchResponse: Decodable {
    let docs: [ArchiveDoc]
}

/// One found item. `creator` arrives as a string *or* an array of strings,
/// and `year` as a number or a string — the search index is older than JSON
/// discipline, so the decoder shrugs instead of throwing.
struct ArchiveDoc: Decodable {
    let identifier: String
    let title: String?
    let creator: String?
    let year: Int?

    enum CodingKeys: String, CodingKey { case identifier, title, creator, year }

    init(identifier: String, title: String?, creator: String?, year: Int?) {
        self.identifier = identifier
        self.title = title
        self.creator = creator
        self.year = year
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try c.decode(String.self, forKey: .identifier)
        title = try? c.decode(String.self, forKey: .title)
        if let one = try? c.decode(String.self, forKey: .creator) {
            creator = one
        } else {
            creator = (try? c.decode([String].self, forKey: .creator))?.first
        }
        if let number = try? c.decode(Int.self, forKey: .year) {
            year = number
        } else {
            year = (try? c.decode(String.self, forKey: .year)).flatMap { Int($0) }
        }
    }
}

struct ArchiveMetadataEnvelope: Decodable {
    let metadata: ArchiveItemMetadata?
    let files: [ArchiveFileEntry]

    enum CodingKeys: String, CodingKey { case metadata, files }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metadata = try? c.decode(ArchiveItemMetadata.self, forKey: .metadata)
        files = (try? c.decode([ArchiveFileEntry].self, forKey: .files)) ?? []
    }
}

struct ArchiveItemMetadata: Decodable {
    let identifier: String?
    let title: String?
    let creator: String?
    let year: Int?

    enum CodingKeys: String, CodingKey { case identifier, title, creator, year }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try? c.decode(String.self, forKey: .identifier)
        title = try? c.decode(String.self, forKey: .title)
        if let one = try? c.decode(String.self, forKey: .creator) {
            creator = one
        } else {
            creator = (try? c.decode([String].self, forKey: .creator))?.first
        }
        if let text = try? c.decode(String.self, forKey: .year) {
            year = Int(text)
        } else {
            year = try? c.decode(Int.self, forKey: .year)
        }
    }
}

/// One file inside an item. Everything is a string in this API — sizes,
/// track numbers, bit rates — because the records predate the types.
struct ArchiveFileEntry: Decodable {
    let name: String
    let format: String?
    let title: String?
    let creator: String?
    let album: String?
    let track: String?
    let length: String?
    let bitrate: String?

    enum CodingKeys: String, CodingKey {
        case name, format, title, creator, album, track, length, bitrate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        format = try? c.decode(String.self, forKey: .format)
        title = try? c.decode(String.self, forKey: .title)
        creator = try? c.decode(String.self, forKey: .creator)
        album = try? c.decode(String.self, forKey: .album)
        track = try? c.decode(String.self, forKey: .track)
        length = try? c.decode(String.self, forKey: .length)
        bitrate = try? c.decode(String.self, forKey: .bitrate)
    }
}
