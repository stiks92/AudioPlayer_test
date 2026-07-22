//
//  PodcastFeedService.swift
//  Sonava
//
//  Fetches and parses a podcast RSS feed into playable episodes (`Song`s).
//  Uses Foundation's XMLParser — no third-party dependencies.
//

import SwiftUI

final class PodcastFeedService: Sendable {
    static let shared = PodcastFeedService()

    private let session = URLSession(configuration: .default)

    func episodes(for podcast: Podcast) async throws -> [Song] {
        var request = URLRequest(url: podcast.feedURL)
        request.setValue(Net.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        let parser = FeedParser(podcast: podcast)
        return parser.parse(data)
    }
}

// MARK: - RSS parsing

private final class FeedParser: NSObject, XMLParserDelegate {
    private let podcast: Podcast
    private var channelImage: URL?
    private var episodes: [Song] = []

    private var insideItem = false
    private var buffer = ""
    private var itemTitle = ""
    private var itemEnclosure: String?
    private var itemArtwork: String?
    private var itemGUID: String?

    init(podcast: Podcast) {
        self.podcast = podcast
    }

    func parse(_ data: Data) -> [Song] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return Array(episodes.prefix(100))
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        buffer = ""
        switch elementName {
        case "item":
            insideItem = true
            itemTitle = ""
            itemEnclosure = nil
            itemArtwork = nil
            itemGUID = nil
        case "enclosure":
            let type = attributeDict["type"] ?? "audio"
            if type.contains("audio") { itemEnclosure = attributeDict["url"] }
        case "itunes:image":
            if let href = attributeDict["href"] {
                if insideItem { itemArtwork = href }
                else if channelImage == nil { channelImage = URL(string: href) }
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "title":
            if insideItem { itemTitle = text }
        case "guid":
            if insideItem { itemGUID = text }
        case "url":
            if !insideItem, channelImage == nil, !text.isEmpty { channelImage = URL(string: text) }
        case "item":
            finalizeItem()
            insideItem = false
        default:
            break
        }
        buffer = ""
    }

    private func finalizeItem() {
        guard let enclosure = itemEnclosure, let streamURL = URL(string: enclosure) else { return }
        let artwork = itemArtwork.flatMap(URL.init(string:)) ?? channelImage ?? podcast.artworkURL
        let title = itemTitle.isEmpty ? podcast.title : itemTitle
        episodes.append(
            Song(
                id: "podcast:\(itemGUID ?? enclosure)",
                title: title,
                artist: podcast.title,
                album: podcast.author.isEmpty ? "Podcast" : podcast.author,
                source: .podcast,
                artworkURL: artwork,
                streamURL: streamURL,
                gradientHex: podcast.gradientHex
            )
        )
    }
}
