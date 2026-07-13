//
//  HomeView.swift
//  AudioPlayer_test
//
//  The landing tab: greeting, recently played, featured playlists and
//  quick picks.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var library: MusicLibrary

    @StateObject private var trending = SongFeed()

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Late night vibes"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        if !library.recentSongs.isEmpty {
                            recentlyPlayed
                        }
                        trendingSection
                        featured
                        quickPicks
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 140)
                }
            }
            .navigationBarHidden(true)
            .task {
                if trending.state == .idle {
                    await trending.load { try await AudiusService.shared.trending() }
                }
            }
        }
    }

    // MARK: - Trending on Audius (live)

    @ViewBuilder
    private var trendingSection: some View {
        switch trending.state {
        case .idle, .failed, .empty:
            EmptyView()
        case .loading:
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Trending on Audius")
                HStack(spacing: 14) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Theme.surface)
                            .frame(width: 150, height: 190)
                            .redacted(reason: .placeholder)
                    }
                }
            }
        case .loaded:
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Trending on Audius")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(trending.songs) { song in
                            Button {
                                audio.play(song, in: trending.songs)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    ArtworkThumbnail(song: song, size: 150, cornerRadius: 18, showBadge: true)
                                    Text(song.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Theme.textPrimary)
                                        .lineLimit(1)
                                        .frame(width: 150, alignment: .leading)
                                    Text(song.artist)
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.textSecondary)
                                        .lineLimit(1)
                                        .frame(width: 150, alignment: .leading)
                                }
                            }
                            .buttonStyle(BouncyButtonStyle(scale: 0.95))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.system(.title, design: .rounded).weight(.heavy))
                    .foregroundColor(Theme.textPrimary)
                Text("What do you feel like hearing?")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Circle()
                .fill(LinearGradient(colors: [Theme.accent, Theme.accentSoft], startPoint: .top, endPoint: .bottom))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "person.fill").foregroundColor(.white))
        }
    }

    // MARK: - Recently played

    private var recentlyPlayed: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Recently played")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(library.recentSongs) { song in
                        Button {
                            audio.play(song, in: library.songs)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ArtworkThumbnail(song: song, size: 130, cornerRadius: 18)
                                Text(song.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Theme.textPrimary)
                                    .lineLimit(1)
                                    .frame(width: 130, alignment: .leading)
                            }
                        }
                        .buttonStyle(BouncyButtonStyle(scale: 0.95))
                    }
                }
            }
        }
    }

    // MARK: - Featured playlists

    private var featured: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Featured")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(library.playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlist: playlist)
                        } label: {
                            PlaylistHeroCard(playlist: playlist)
                        }
                        .buttonStyle(BouncyButtonStyle(scale: 0.96))
                    }
                }
            }
        }
    }

    // MARK: - Quick picks

    private var quickPicks: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Quick picks")
            LazyVStack(spacing: 2) {
                ForEach(library.songs.prefix(8)) { song in
                    Button {
                        audio.play(song, in: library.songs)
                    } label: {
                        SongRow(song: song)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct PlaylistHeroCard: View {
    let playlist: Playlist

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: playlist.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: playlist.systemImage)
                .font(.system(size: 60, weight: .bold))
                .foregroundColor(.white.opacity(0.22))
                .offset(x: 90, y: -40)

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text(playlist.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .padding(16)
        }
        .frame(width: 220, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: playlist.gradient.first?.opacity(0.5) ?? .clear, radius: 16, y: 10)
    }
}
