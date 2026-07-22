//
//  RemotePlaylistView.swift
//  AudioPlayer_test
//
//  Tracks of a curated (Deezer) playlist.
//

import SwiftUI

struct RemotePlaylistView: View {
    let playlist: RemotePlaylist

    @EnvironmentObject private var audio: AudioManager
    @StateObject private var feed = SongFeed()

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
        .navigationTitle(playlist.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if feed.state == .idle {
                await feed.load { try await DeezerService.shared.playlistTracks(playlist.fetchID) }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            AsyncImage(url: playlist.artworkURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    LinearGradient(colors: playlist.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note.list").font(.system(size: 50)).foregroundColor(.white.opacity(0.85))
                }
            }
            .frame(width: 200, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: playlist.gradient.first?.opacity(0.5) ?? .clear, radius: 20, y: 12)

            VStack(spacing: 6) {
                Text(playlist.title)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                Text(playlist.subtitle)
                    .font(.subheadline).foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, 20)

            if feed.state == .loaded, let first = feed.songs.first {
                HStack(spacing: 16) {
                    Button {
                        if audio.isShuffling { audio.toggleShuffle() }
                        audio.play(first, in: feed.songs)
                    } label: {
                        Label(L("Play"), systemImage: "play.fill")
                            .font(.headline).foregroundColor(Theme.background)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Capsule().fill(Color.white))
                    }
                    .buttonStyle(BouncyButtonStyle(scale: 0.96))

                    Button {
                        if !audio.isShuffling { audio.toggleShuffle() }
                        audio.play(feed.songs.randomElement() ?? first, in: feed.songs)
                    } label: {
                        Label(L("Shuffle"), systemImage: "shuffle")
                            .font(.headline).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .glass(cornerRadius: 30)
                    }
                    .buttonStyle(BouncyButtonStyle(scale: 0.96))
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch feed.state {
        case .idle, .loading:
            ProgressView().tint(Theme.accentSoft).padding(.top, 40)
        case .failed:
            Text(L("Couldn't reach Audius. Check your connection."))
                .font(.subheadline).foregroundColor(Theme.textSecondary).padding(.top, 40)
        case .empty:
            Text(L("No results")).font(.subheadline).foregroundColor(Theme.textSecondary).padding(.top, 40)
        case .loaded:
            LazyVStack(spacing: 2) {
                ForEach(feed.songs) { song in
                    Button { audio.play(song, in: feed.songs) } label: {
                        SongRow(song: song, showBadge: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}
