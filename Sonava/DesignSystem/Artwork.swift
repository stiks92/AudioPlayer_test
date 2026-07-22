//
//  Artwork.swift
//  Sonava
//
//  Renders a track's artwork: remote image (AsyncImage) when available,
//  falling back to the bundled asset for local tracks or a tasteful glyph
//  over the track's gradient for remote tracks.
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

    @ViewBuilder
    private var fallback: some View {
        if song.source == .local {
            Image(song.artworkName)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: song.isLive ? "dot.radiowaves.left.and.right" : "music.note")
                .font(.system(size: glyphSize, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
        }
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
