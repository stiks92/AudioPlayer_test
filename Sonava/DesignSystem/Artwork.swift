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
        Image(systemName: song.isLive ? "dot.radiowaves.left.and.right" : "music.note")
            .font(.system(size: glyphSize, weight: .bold))
            .foregroundColor(.white.opacity(0.9))
    }
}

/// Small badge (AUDIUS / LIVE …) shown on remote artwork.
struct SourceBadge: View {
    let source: TrackSource

    var body: some View {
        if let text = source.badge {
            Text(text)
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.5)
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(source == .radio ? Theme.destructive : Color.black.opacity(0.55))
                )
        }
    }
}
