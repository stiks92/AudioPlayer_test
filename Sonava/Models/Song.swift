//
//  Song.swift
//  Sonava
//
//  Universal track model. A track can be a bundled file, a remote
//  streaming track (e.g. Audius), or a live radio station — all screens
//  work against this single type.
//

import SwiftUI

/// Where a track's audio comes from.
enum TrackSource: String, Codable {
    case local          // bundled resource
    case audius         // Audius direct-stream catalogue
    case radio          // internet radio (live stream)
    case subsonic       // user's self-hosted server (Navidrome/Airsonic/…)
    case itunes         // Apple/iTunes 30-second previews
    case deezer         // Deezer 30-second previews
    case jamendo
    case archive
    case podcast

    var badge: String? {
        switch self {
        case .local:    return nil
        case .audius:   return "AUDIUS"
        case .radio:    return "LIVE"
        case .subsonic: return "SERVER"
        case .itunes:   return "PREVIEW"
        case .deezer:   return "PREVIEW"
        case .jamendo:  return "JAMENDO"
        case .archive:  return "ARCHIVE"
        case .podcast:  return "PODCAST"
        }
    }

    /// Whether a track from this source may be saved for offline listening.
    /// Only full-length, rights-clean sources qualify: never 30-second
    /// previews, never live radio, and local files are already offline.
    var isDownloadable: Bool {
        switch self {
        case .audius, .subsonic, .jamendo, .archive: return true
        case .local, .radio, .itunes, .deezer, .podcast: return false
        }
    }
}

struct Song: Identifiable, Equatable, Hashable, Codable {
    /// Stable, globally-unique id, e.g. `local:song1` or `audius:aBc12`.
    let id: String
    let title: String
    let artist: String
    let album: String
    let source: TrackSource
    /// Bundled resource name (nil for remote tracks).
    let fileName: String?
    let fileExtension: String
    /// Cover art, if any: a remote URL, or a file URL for a local track whose
    /// embedded artwork we extracted on import. Absent → the gradient shows.
    let artworkURL: URL?
    /// Remote audio stream, if any.
    let streamURL: URL?
    /// Live stream (radio) — has no fixed duration / scrubbing.
    let isLive: Bool
    /// Two-stop gradient stored as hex so `Song` stays `Codable`.
    let gradientHex: [UInt]

    // What the source truthfully knows about the recording, or nil. Subsonic
    // has been returning all four on every track while the DTO decoded five
    // fields and discarded the rest — so every list row in the app had nothing
    // to say about length, order, vintage or quality. All optional: unknown
    // stays absent, never invented.
    /// Length in seconds.
    let durationSeconds: Double?
    /// Position on the record.
    let trackNumber: Int?
    /// Release year.
    let year: Int?
    /// Encoded bit rate, kbit/s.
    let bitRate: Int?
    /// Track ReplayGain in dB, when the source publishes one (Subsonic does).
    /// Saves the app measuring a file it can be told about — see
    /// `LoudnessAnalyzer.gain(fromReplayGain:)`.
    let replayGain: Double?
    /// Everyone credited on the track, when the source distinguishes them.
    /// A collaboration used to arrive as one comma-joined string, so tapping
    /// "Burial & Four Tet" searched for a performer that does not exist.
    let credits: [TrackCredit]
    /// Starred on the server. Favourites should be one set across every
    /// client the listener uses, not a per-app opinion.
    let isStarredOnServer: Bool

    /// `3:47` for the margin, or nil when the length is unknown.
    var durationText: String? {
        guard let seconds = durationSeconds, seconds > 0 else { return nil }
        return seconds.asClock
    }

    /// The track's theme gradient.
    var gradient: [Color] { gradientHex.colors }

    init(
        id: String,
        title: String,
        artist: String,
        album: String,
        source: TrackSource = .local,
        fileName: String? = nil,
        fileExtension: String = "mp3",
        artworkURL: URL? = nil,
        streamURL: URL? = nil,
        isLive: Bool = false,
        gradientHex: [UInt],
        durationSeconds: Double? = nil,
        trackNumber: Int? = nil,
        year: Int? = nil,
        bitRate: Int? = nil,
        replayGain: Double? = nil,
        credits: [TrackCredit] = [],
        isStarredOnServer: Bool = false
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.source = source
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.artworkURL = artworkURL
        self.streamURL = streamURL
        self.isLive = isLive
        self.gradientHex = gradientHex
        self.durationSeconds = durationSeconds
        self.trackNumber = trackNumber
        self.year = year
        self.bitRate = bitRate
        self.replayGain = replayGain
        self.credits = credits
        self.isStarredOnServer = isStarredOnServer
    }

    /// Playable URL. Local tracks are files the user imported, which live in
    /// the app's Media directory — Sonava bundles no audio of its own.
    var url: URL? {
        switch source {
        case .local:
            return fileName.map { LocalFileStore.mediaDirectory.appendingPathComponent($0) }
        default:
            return streamURL
        }
    }

    var isRemote: Bool { source != .local }

    /// Full-length streaming track (not a 30-second preview) — the ones worth
    /// downloading and the ones the UI must not disguise as previews.
    var isFullLength: Bool { source != .itunes && source != .deezer }

    /// Whether this track may be saved for offline listening, and has a stream
    /// to save. Local tracks are already offline; previews and radio never
    /// qualify.
    var isDownloadable: Bool { source.isDownloadable && streamURL != nil }

    static func == (lhs: Song, rhs: Song) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One credited artist on a track.
struct TrackCredit: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
}
