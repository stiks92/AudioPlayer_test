//
//  Artwork.swift
//  Sonava
//
//  Renders a track's artwork: the cover image (AsyncImage — works for both
//  remote URLs and local file URLs) when there is one, falling back to a glyph
//  over the track's gradient. The app bundles no artwork of its own.
//

import SwiftUI

/// Fills its frame; callers apply size / clipping / shadow.
struct ArtworkImage: View {
    let song: Song
    var glyphSize: CGFloat = 24

    var body: some View {
        ZStack {
            LinearGradient(colors: song.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)

            if let url = song.artworkURL {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.35))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .empty, .failure:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
    }

    /// No cover art (or it failed to load): the track's gradient carries a
    /// glyph. Sonava bundles no artwork, so there is nothing else to show.
    private var fallback: some View {
        // The most-seen glyph in the app: every cover that has not loaded, or
        // does not exist, is this. A borrowed one here is a borrowed one
        // everywhere.
        SonavaIcon(glyph: song.isLive ? .radio : .note,
                   size: glyphSize * 1.25,
                   tint: .white.opacity(0.9))
    }
}

/// Small badge (AUDIUS / LIVE …) shown on remote artwork.
struct SourceBadge: View {
    let source: TrackSource
    /// The artwork this badge sits on. Below `compactThreshold` the word does
    /// not fit and the badge becomes a dot.
    var artworkSide: CGFloat = 200

    /// A 52pt row thumbnail cannot hold the word "AUDIUS": it wrapped to two
    /// lines reading "AU / DI…" over the sleeve — a caption arguing with the
    /// picture it is captioning. Above this size the word fits; below it, the
    /// provenance is a dot, and the word lives in the accessibility label
    /// where it is still readable by anyone who needs it.
    private static let compactThreshold: CGFloat = 96

    var body: some View {
        if let text = source.badge {
            if artworkSide < Self.compactThreshold {
                Circle()
                    .fill(source == .radio ? Theme.live : Theme.accentSoft)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().strokeBorder(Theme.background.opacity(0.6), lineWidth: 1.5))
                    .accessibilityLabel(Text(text))
            } else {
                word(text)
            }
        }
    }

    private func word(_ text: String) -> some View {
        Text(text)
                // Was `.heavy` with tracking, which made a third-party
                // catalogue's name heavier than the track title beneath it —
                // the loudest thing on the artwork was the name of the
                // service, not the music.
                .font(.system(.caption2).weight(.semibold))
                .foregroundColor(.white.opacity(0.92))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    // A fixed fill rather than translucent black. Over one row
                    // of covers `black.opacity(0.55)` rendered plum, olive and
                    // indigo — the same badge in three colours, which is not a
                    // badge. `LIVE` keeps its own colour because there it is
                    // the status, not the provenance.
                    Capsule().fill(source == .radio ? Theme.destructive
                                                    : Theme.background.opacity(0.78))
                )
                .lineLimit(1)
                .fixedSize()
    }
}
