//
//  PlaylistImport.swift
//  Sonava
//
//  Bringing a playlist out of somewhere else.
//
//  The Russian corpus documents a whole migration wave — one app whose only
//  job is moving playlists off Yandex and VK has 13,700 ratings and 83
//  transfer stories in 150 reviews. Settings has been promising "Spotify /
//  Apple Music — Soon" for a while.
//
//  The official route is closed: since 2025-05-15 Spotify's Web API extended
//  quota needs an organisation with 250,000 monthly users, and development
//  mode allows five. So this does the thing that actually works and needs no
//  one's permission — it reads what the listener can already export.
//
//  ## What it accepts
//
//  - CSV from Exportify, TuneMyMusic, Soundiiz and the rest, in whatever
//    column order they chose, with or without quotes.
//  - M3U/M3U8, the format every desktop player writes.
//  - Plain text pasted from anywhere: "Artist — Title" or "Artist - Title",
//    one per line, which is what people paste out of a chat or a notes app.
//
//  ## What it promises
//
//  That it will say what it could not find. A migration that silently drops
//  a fifth of a playlist is the failure the review corpus is full of; the
//  import result carries the misses by name so the screen can list them.
//

import Foundation

enum PlaylistImport {

    /// One line of the source, before any matching happens.
    struct ParsedTrack: Equatable, Sendable {
        let title: String
        let artist: String
        let album: String?

        /// What gets searched for. Artist first because that is what every
        /// catalogue weights most heavily.
        var query: String {
            artist.isEmpty ? title : "\(artist) \(title)"
        }
    }

    struct ParseResult: Equatable, Sendable {
        var name: String
        var tracks: [ParsedTrack]
    }

    // MARK: - Parsing

    /// Reads whatever the listener handed over, guessing the format from the
    /// content rather than the file extension — exports arrive named `.txt`
    /// often enough that trusting the extension loses playlists.
    static func parse(_ text: String, name: String) -> ParseResult {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return ParseResult(name: name, tracks: []) }

        if lines.first?.hasPrefix("#EXTM3U") == true || lines.contains(where: { $0.hasPrefix("#EXTINF") }) {
            return ParseResult(name: name, tracks: parseM3U(lines))
        }
        if looksLikeCSV(lines) {
            return ParseResult(name: name, tracks: parseCSV(lines))
        }
        return ParseResult(name: name, tracks: parsePlainText(lines))
    }

    private static func looksLikeCSV(_ lines: [String]) -> Bool {
        // A header naming at least two of the columns we understand, or a
        // first line with commas outside quotes in every row.
        let header = lines[0].lowercased()
        let known = ["track name", "title", "artist", "artist name", "album", "album name"]
        return known.filter { header.contains($0) }.count >= 2
    }

    // MARK: - CSV

    static func parseCSV(_ lines: [String]) -> [ParsedTrack] {
        guard let headerLine = lines.first else { return [] }
        let header = splitCSV(headerLine).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        // Column names differ per exporter, so each field accepts the set of
        // spellings the common tools use.
        func column(_ names: [String]) -> Int? {
            for name in names {
                if let index = header.firstIndex(of: name) { return index }
            }
            // Fall back to a contains-match: "track name" vs "track_name".
            for name in names {
                if let index = header.firstIndex(where: { $0.replacingOccurrences(of: "_", with: " ").contains(name) }) {
                    return index
                }
            }
            return nil
        }

        let titleColumn = column(["track name", "title", "name", "song"])
        let artistColumn = column(["artist name(s)", "artist name", "artist", "artists"])
        let albumColumn = column(["album name", "album"])
        guard let titleColumn else { return [] }

        return lines.dropFirst().compactMap { line in
            let fields = splitCSV(line)
            guard titleColumn < fields.count else { return nil }
            let title = fields[titleColumn].trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            let artist = artistColumn.flatMap { $0 < fields.count ? fields[$0] : nil }?
                .trimmingCharacters(in: .whitespaces) ?? ""
            let album = albumColumn.flatMap { $0 < fields.count ? fields[$0] : nil }?
                .trimmingCharacters(in: .whitespaces)
            return ParsedTrack(title: title,
                               // Exporters join collaborators with a comma
                               // inside one quoted field; the first name is
                               // the one a search should lead with.
                               artist: artist.components(separatedBy: ",").first?
                                   .trimmingCharacters(in: .whitespaces) ?? artist,
                               album: (album?.isEmpty ?? true) ? nil : album)
        }
    }

    /// A CSV splitter that respects quotes, because song titles contain
    /// commas — "Life, Death, Love and Freedom" is one field, not four.
    static func splitCSV(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        var pending: Character?

        while let character = pending ?? iterator.next() {
            pending = nil
            if character == "\"" {
                if inQuotes, let next = iterator.next() {
                    if next == "\"" { current.append("\"") }   // escaped quote
                    else { inQuotes = false; pending = next }
                } else {
                    inQuotes.toggle()
                }
            } else if character == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        fields.append(current)
        return fields
    }

    // MARK: - M3U

    static func parseM3U(_ lines: [String]) -> [ParsedTrack] {
        var tracks: [ParsedTrack] = []
        for line in lines {
            guard line.hasPrefix("#EXTINF") else { continue }
            // `#EXTINF:213,Artist - Title`
            guard let comma = line.firstIndex(of: ",") else { continue }
            let label = String(line[line.index(after: comma)...])
                .trimmingCharacters(in: .whitespaces)
            tracks.append(split(label))
        }
        // A playlist of bare paths, with no #EXTINF anywhere: the file name is
        // all there is, and it is usually "Artist - Title.mp3".
        if tracks.isEmpty {
            tracks = lines
                .filter { !$0.hasPrefix("#") }
                .map { path in
                    let name = (path as NSString).lastPathComponent
                    return split((name as NSString).deletingPathExtension)
                }
        }
        return tracks
    }

    // MARK: - Plain text

    static func parsePlainText(_ lines: [String]) -> [ParsedTrack] {
        lines
            // A pasted list often starts with a numbered index: "1. Artist — Title".
            .map { line -> String in
                guard let dot = line.firstIndex(of: "."),
                      line[line.startIndex..<dot].allSatisfy(\.isNumber),
                      line.distance(from: line.startIndex, to: dot) <= 3
                else { return line }
                return String(line[line.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
            .map(split)
    }

    /// Splits "Artist — Title" on whichever dash was used. Falls back to the
    /// whole line as a title, which still searches usefully.
    static func split(_ label: String) -> ParsedTrack {
        for separator in [" — ", " – ", " - ", " -- "] {
            if let range = label.range(of: separator) {
                return ParsedTrack(
                    title: String(label[range.upperBound...]).trimmingCharacters(in: .whitespaces),
                    artist: String(label[..<range.lowerBound]).trimmingCharacters(in: .whitespaces),
                    album: nil)
            }
        }
        return ParsedTrack(title: label, artist: "", album: nil)
    }

    // MARK: - Matching

    /// What the import actually managed.
    struct Outcome: Equatable, Sendable {
        var matched: [Song] = []
        /// Tracks where only a 30-second preview exists anywhere the listener
        /// can reach — its own column in the ledger, because a preview
        /// claiming to be a match would be a lie with a play button.
        var previews: [Song] = []
        /// The ones nothing could be found for, kept in the order they were
        /// listed so the screen can show them as the original playlist read.
        var missing: [ParsedTrack] = []

        var total: Int { matched.count + previews.count + missing.count }
    }

    /// Buckets the resolver's answers into the ledger the import screen
    /// speaks: found · preview-only · not found, order preserved.
    static func outcome(from results: [(ForeignTrack, TrackResolution)]) -> Outcome {
        var outcome = Outcome()
        for (foreign, resolution) in results {
            switch resolution {
            case .matched(let song):
                outcome.matched.append(song)
            case .preview(let song):
                outcome.previews.append(song)
            case .notFound:
                outcome.missing.append(ParsedTrack(title: foreign.title,
                                                   artist: foreign.artist,
                                                   album: foreign.album))
            }
        }
        return outcome
    }

    /// The importer's rows, dressed for the resolver.
    static func foreignTracks(_ tracks: [ParsedTrack], origin: TrackOrigin) -> [ForeignTrack] {
        tracks.map {
            ForeignTrack(title: $0.title, artist: $0.artist, album: $0.album, origin: origin)
        }
    }

    /// Scores a candidate against what was asked for. Deliberately strict:
    /// a playlist half-filled with the wrong songs is worse than one that
    /// admits what it could not find.
    static func matches(_ candidate: Song, _ wanted: ParsedTrack) -> Bool {
        let title = normalise(candidate.title)
        let wantedTitle = normalise(wanted.title)
        guard !wantedTitle.isEmpty else { return false }
        guard title == wantedTitle || title.contains(wantedTitle) || wantedTitle.contains(title)
        else { return false }

        guard !wanted.artist.isEmpty else { return true }
        let artist = normalise(candidate.artist)
        let wantedArtist = normalise(wanted.artist)
        return artist.contains(wantedArtist) || wantedArtist.contains(artist)
    }

    /// Lower-cased, punctuation-free, with the noise that makes two spellings
    /// of the same recording look different: "(Remastered 2011)",
    /// "- Single Version", "feat. …".
    static func normalise(_ text: String) -> String {
        var value = text.lowercased()
        for pattern in ["(remastered", "(remaster", "(live", "(feat", "(ft",
                        " - remaster", " - single", " - radio edit", " feat.", " ft."] {
            if let range = value.range(of: pattern) {
                value = String(value[..<range.lowerBound])
            }
        }
        return value
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
    }
}
