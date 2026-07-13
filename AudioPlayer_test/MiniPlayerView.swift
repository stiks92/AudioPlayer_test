//
//  MiniPlayerView.swift
//  AudioPlayer_test
//
//  Compact transport that lives above the tab bar and expands into the
//  full Now Playing scene when tapped.
//

import SwiftUI

struct MiniPlayerView: View {
    var namespace: Namespace.ID
    let onExpand: () -> Void

    @EnvironmentObject private var audio: AudioManager

    var body: some View {
        if let song = audio.currentSong {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ArtworkImage(song: song, glyphSize: 16)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .matchedGeometryEffect(id: "artwork", in: namespace)

                    VStack(alignment: .leading, spacing: 2) {
                        MarqueeText(text: song.title, font: .system(size: 14, weight: .semibold))
                            .frame(height: 18)
                        Text(song.artist)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    Button {
                        audio.togglePlayPause()
                    } label: {
                        Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(BouncyButtonStyle())

                    Button {
                        audio.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(BouncyButtonStyle())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                // Progress line
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.14))
                        Rectangle()
                            .fill(LinearGradient(colors: song.gradient, startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(audio.progress))
                    }
                }
                .frame(height: 2)
            }
            .background(
                ZStack {
                    LinearGradient(colors: song.gradient.map { $0.opacity(0.35) },
                                   startPoint: .leading, endPoint: .trailing)
                    Rectangle().fill(.ultraThinMaterial)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture(perform: onExpand)
        }
    }
}
