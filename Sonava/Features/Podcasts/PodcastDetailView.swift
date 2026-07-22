//
//  PodcastDetailView.swift
//  Sonava
//
//  A podcast's episodes, streamed through the shared playback engine.
//

import SwiftUI

struct PodcastDetailView: View {
    let podcast: Podcast

    @EnvironmentObject private var audio: AudioManager
    @StateObject private var episodes = SongFeed()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    header
                    content
                }
                .padding(.bottom, 120)
            }
        }
        .foregroundColor(.white)
        .navigationTitle(podcast.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if episodes.state == .idle {
                await episodes.load { try await PodcastFeedService.shared.episodes(for: podcast) }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            AsyncImage(url: podcast.artworkURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    LinearGradient(colors: podcast.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "mic.fill").font(.system(size: 50)).foregroundColor(.white.opacity(0.85))
                }
            }
            .frame(width: 180, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: podcast.gradient.first?.opacity(0.5) ?? .clear, radius: 20, y: 12)

            VStack(spacing: 6) {
                Text(podcast.title)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                Text(podcast.author)
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, 20)

            if episodes.state == .loaded, let latest = episodes.songs.first {
                Button {
                    audio.play(latest, in: episodes.songs)
                } label: {
                    Label("Play latest", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundColor(Theme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(BouncyButtonStyle(scale: 0.97))
                .padding(.horizontal, 40)
            }
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch episodes.state {
        case .idle, .loading:
            ProgressView().tint(Theme.accentSoft).padding(.top, 40)
        case .failed:
            infoText("Couldn't load episodes.")
        case .empty:
            infoText("No episodes found.")
        case .loaded:
            LazyVStack(spacing: 2) {
                ForEach(episodes.songs) { episode in
                    Button {
                        audio.play(episode, in: episodes.songs)
                    } label: {
                        SongRow(song: episode)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func infoText(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(Theme.textSecondary)
            .padding(.top, 40)
    }
}
