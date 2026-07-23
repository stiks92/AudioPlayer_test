//
//  HomeView.swift
//  Sonava
//
//  The landing tab: greeting, recently played, featured playlists and
//  quick picks.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var proStore: ProStore
    @EnvironmentObject private var serverStore: ServerStore

    @StateObject private var trending = SongFeed()
    @StateObject private var charts = SongFeed()
    @StateObject private var serverFeed = SongFeed()
    @StateObject private var madeForYou = SongFeed()
    @State private var editorial: [RemotePlaylist] = []
    @State private var tasteSeed: [String] = []
    @State private var showSettings = false
    @State private var showAIMix = false
    @State private var showShazam = false

    private var greeting: LocalizedStringKey {
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
                        aiMixCard
                        madeForYouSection
                        popularSection
                        if !library.recentSongs.isEmpty {
                            recentlyPlayed
                        }
                        editorialSection
                        serverSection
                        trendingSection
                        quickPicks
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 140)
                }
            }
            .navigationBarHidden(true)
            .task {
                if charts.state == .idle {
                    await charts.load { try await DeezerService.shared.chartTracks() }
                }
                if editorial.isEmpty {
                    editorial = (try? await DeezerService.shared.chartPlaylists()) ?? []
                }
                if trending.state == .idle {
                    await trending.load { try await AudiusService.shared.trending() }
                }
                await loadServerIfNeeded()
                await loadMadeForYou()
            }
            .onChange(of: serverStore.isConnected) {
                Task { await loadServerIfNeeded(force: true) }
            }
            .onChange(of: library.favoriteSongs.count) {
                Task { await loadMadeForYou(force: true) }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(audio)
                    .environmentObject(proStore)
                    .environmentObject(serverStore)
            }
            .sheet(isPresented: $showAIMix) {
                AIMixView()
                    .environmentObject(audio)
                    .environmentObject(library)
                    .environmentObject(proStore)
            }
            .sheet(isPresented: $showShazam) {
                ShazamView().environmentObject(audio)
            }
        }
    }

    private func loadServerIfNeeded(force: Bool = false) async {
        guard serverStore.isConnected else {
            if serverFeed.state != .idle { serverFeed.clear() }
            return
        }
        if force || serverFeed.state == .idle {
            await serverFeed.load { try await serverStore.randomSongs() }
        }
    }

    // MARK: - From your server

    // MARK: - Made for you (taste-based)

    /// Loads recommendations from the on-device taste profile. Only refetches
    /// when the taste actually changed, so it doesn't hammer the network.
    private func loadMadeForYou(force: Bool = false) async {
        let profile = library.tasteProfile
        guard !profile.isEmpty else { madeForYou.clear(); return }
        guard force || profile.seedQueries != tasteSeed else { return }
        tasteSeed = profile.seedQueries
        let known = library.knownTrackIDs
        await madeForYou.load {
            Array(await StationService.recommendations(for: profile, excluding: known).prefix(20))
        }
    }

    @ViewBuilder
    private var madeForYouSection: some View {
        if madeForYou.state == .loaded, !madeForYou.songs.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Made for you")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(madeForYou.songs) { song in
                            Button {
                                audio.play(song, in: madeForYou.songs)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    ArtworkThumbnail(song: song, size: 130, cornerRadius: 16, showBadge: true)
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
    }

    @ViewBuilder
    private var serverSection: some View {
        if serverStore.isConnected, serverFeed.state == .loaded {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "From your server")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(serverFeed.songs) { song in
                            Button {
                                audio.play(song, in: serverFeed.songs)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    ArtworkThumbnail(song: song, size: 130, cornerRadius: 16, showBadge: true)
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
    }

    // MARK: - AI Mix banner

    private var aiMixCard: some View {
        Button {
            Haptics.impact()
            showAIMix = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Create an AI Mix")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                    Text("Describe a vibe — get an instant mix")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                if !proStore.isPro {
                    Text("PRO")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(Theme.background)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white))
                }
                Image(systemName: "chevron.right").foregroundColor(.white.opacity(0.8))
            }
            .padding(16)
            .background(
                LinearGradient(colors: [Theme.accent, Theme.accentPink, Theme.accentDeep],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Theme.accent.opacity(0.4), radius: 14, y: 8)
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.98))
    }

    // MARK: - Editor's picks (curated playlists)

    @ViewBuilder
    private var editorialSection: some View {
        if !editorial.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Editor's picks")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(editorial) { playlist in
                            NavigationLink {
                                RemotePlaylistView(playlist: playlist)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    AsyncImage(url: playlist.artworkURL) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        ZStack {
                                            LinearGradient(colors: playlist.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                                            Image(systemName: "music.note.list").font(.system(size: 34)).foregroundColor(.white.opacity(0.85))
                                        }
                                    }
                                    .frame(width: 160, height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                                    Text(playlist.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Theme.textPrimary)
                                        .lineLimit(1)
                                        .frame(width: 160, alignment: .leading)
                                }
                            }
                            .buttonStyle(BouncyButtonStyle(scale: 0.96))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Popular now (Deezer charts)

    @ViewBuilder
    private var popularSection: some View {
        if charts.state == .loaded {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Popular now")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(charts.songs) { song in
                            Button {
                                audio.play(song, in: charts.songs)
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
            Button {
                Haptics.impact()
                showShazam = true
            } label: {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(Theme.accentSoft)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(BouncyButtonStyle())
            .identified(AccessibilityID.shazamButton, label: "Discover")

            Button {
                showSettings = true
            } label: {
                Circle()
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accentSoft], startPoint: .top, endPoint: .bottom))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: proStore.isPro ? "sparkles" : "person.fill")
                            .foregroundColor(.white)
                    )
            }
            .buttonStyle(BouncyButtonStyle())
            .identified(AccessibilityID.settingsButton, label: "Settings")
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
