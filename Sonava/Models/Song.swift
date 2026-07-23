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
        gradientHex: [UInt]
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

    static func == (lhs: Song, rhs: Song) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
