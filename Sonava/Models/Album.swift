//
//  Album.swift
//  Sonava
//
//  The app had no album. That is worth stating plainly, because it is the
//  largest hole in a music player and it went unnoticed through eight rounds of
//  design review: `Song.album` was a `String` carried around for search and
//  lyrics lookup, and nothing ever grouped by it. There was no way to see a
//  record, and no way to play one in order — the one thing a person who owns
//  their music does most.
//
//  ## Why grouping is not trivial here
//
//  `Song.album` is free text and every remote source fills it with a
//  placeholder rather than a real title: Audius tracks arrive as "Audius",
//  imported files as "My files", Subsonic sometimes as "Library". Grouping
//  naively would produce one enormous fake album per service, which is worse
//  than having none.
//
//  So an album is only formed when the data supports one: a title that is not
//  a known placeholder, and every track agreeing on the artist. Everything else
//  stays loose tracks. The result is fewer albums than a naive grouping and all
//  of them real.
//

import Foundation

struct Album: Identifiable, Equatable, Sendable {
    /// Title and artist together, because two artists can share a title.
    let id: String
    let title: String
    let artist: String
    /// In the order the source gave them, which for a ripped folder is disc
    /// order and is the only ordering the app can honestly claim.
    let songs: [Song]

    var trackCount: Int { songs.count }
    /// The sleeve. Whichever track has art; a record has one cover, not five.
    var artwork: Song? { songs.first { $0.artworkURL != nil } ?? songs.first }

    /// Titles a source uses when it has nothing to say. Grouping on these would
    /// invent one giant album per service.
    private static let placeholders: Set<String> = [
        "audius", "my files", "library", "deezer", "itunes", "jamendo",
        "archive", "radio", "podcast", "unknown album", "unknown", ""
    ]

    /// Groups tracks into the albums they actually describe.
    ///
    /// A group becomes an album only when the title is real and every track
    /// agrees on the artist — a folder of assorted singles that happens to
    /// share an "album" string is a folder, not a record.
    static func group(_ songs: [Song], minimumTracks: Int = 2) -> [Album] {
        let buckets = Dictionary(grouping: songs) { song in
            "\(song.album.lowercased())|\(song.artist.lowercased())"
        }
        return buckets.compactMap { _, tracks -> Album? in
            guard let first = tracks.first else { return nil }
            let title = first.album.trimmingCharacters(in: .whitespaces)
            guard !placeholders.contains(title.lowercased()) else { return nil }
            guard tracks.count >= minimumTracks else { return nil }
            guard Set(tracks.map(\.artist)).count == 1 else { return nil }
            return Album(id: "\(title.lowercased())|\(first.artist.lowercased())",
                         title: title,
                         artist: first.artist,
                         songs: tracks)
        }
        // Longest first: the records someone actually ripped come before the
        // two-track odds and ends.
        .sorted { ($0.trackCount, $1.title) > ($1.trackCount, $0.title) }
    }
}
