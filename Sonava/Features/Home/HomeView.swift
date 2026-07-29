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
    @EnvironmentObject private var scrobble: ScrobbleStore
    @EnvironmentObject private var history: ListeningHistory

    @StateObject private var trending = SongFeed()
    @StateObject private var charts = SongFeed()
    @StateObject private var serverFeed = SongFeed()
    @StateObject private var madeForYou = SongFeed()
    @State private var editorial: [RemotePlaylist] = []
    @State private var tasteSeed: [String] = []
    @State private var showSettings = false
    @State private var showAIMix = false
    @State private var showShazam = false
    @State private var showStats = false

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
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xxl) {
                        header
                        aiMixCard
                        statsCard
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
                    .padding(.horizontal, Space.screenMargin)
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
                    .environmentObject(scrobble)
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
            .sheet(isPresented: $showStats) {
                StatsView()
                    .environmentObject(history)
                    .environmentObject(proStore)
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
            VStack(alignment: .leading, spacing: Space.l) {
                SectionHeader(title: "Made for you")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.l) {
                        ForEach(madeForYou.songs) { song in
                            Button {
                                audio.play(song, in: madeForYou.songs)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    ArtworkThumbnail(song: song, size: 130, cornerRadius: Radius.card, showBadge: true)
                                    Text(song.title)
                                        .font(.system(.footnote).weight(.semibold))
                                        .foregroundColor(Theme.textPrimary)
                                        .lineLimit(1)
                                        .frame(width: 130, alignment: .leading)
                                }
                            }
                            .buttonStyle(BouncyButtonStyle(scale: 0.95))
                        }
                    }
                }
                .carouselBleed()
            }
        }
    }

    @ViewBuilder
    private var serverSection: some View {
        if serverStore.isConnected, serverFeed.state == .loaded {
            VStack(alignment: .leading, spacing: Space.l) {
                SectionHeader(title: "From your server")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.l) {
                        ForEach(serverFeed.songs) { song in
                            Button {
                                audio.play(song, in: serverFeed.songs)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    ArtworkThumbnail(song: song, size: 130, cornerRadius: Radius.card, showBadge: true)
                                    Text(song.title)
                                        .font(.system(.footnote).weight(.semibold))
                                        .foregroundColor(Theme.textPrimary)
                                        .lineLimit(1)
                                        .frame(width: 130, alignment: .leading)
                                }
                            }
                            .buttonStyle(BouncyButtonStyle(scale: 0.95))
                        }
                    }
                }
                .carouselBleed()
            }
        }
    }

    // MARK: - AI Mix banner

    private var aiMixCard: some View {
        Button {
            Haptics.impact()
            showAIMix = true
        } label: {
            HStack(spacing: Space.l) {
                Image(systemName: "sparkles")
                    .font(.system(.title).weight(.bold))
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Create an AI Mix")
                        .font(.system(.body).weight(.bold))
                        .foregroundColor(.white)
                    Text("Describe a vibe — get an instant mix")
                        .font(.system(.caption))
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                if !proStore.isPro {
                    Text("PRO")
                        .font(.system(.caption2).weight(.heavy))
                        .foregroundColor(Theme.background)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white))
                }
                Image(systemName: "chevron.right").foregroundColor(.white.opacity(0.8))
            }
            .padding(Space.l)
            // The gradient peaks magenta mid-card, which put this copy at
            // 1.9:1. `StatsShareCard` solves the identical problem on the
            // identical gradient with a scrim; same answer here.
            .background(Theme.proGradient.overlay(Color.black.opacity(0.25)))
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.98))
    }

    // MARK: - Editor's picks (curated playlists)

    @ViewBuilder
    private var editorialSection: some View {
        if !editorial.isEmpty {
            VStack(alignment: .leading, spacing: Space.l) {
                SectionHeader(title: "Editor's picks")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.l) {
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
                                            Image(systemName: "music.note.list").font(.system(.largeTitle)).foregroundColor(.white.opacity(0.85))
                                        }
                                    }
                                    .frame(width: 160, height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                                    Text(playlist.title)
                                        .font(.system(.footnote).weight(.semibold))
                                        .foregroundColor(Theme.textPrimary)
                                        .lineLimit(1)
                                        .frame(width: 160, alignment: .leading)
                                }
                            }
                            .buttonStyle(BouncyButtonStyle(scale: 0.96))
                        }
                    }
                }
                .carouselBleed()
            }
        }
    }

    // MARK: - Popular now (Deezer charts)

    @ViewBuilder
    private var popularSection: some View {
        if charts.state == .loaded {
            VStack(alignment: .leading, spacing: Space.l) {
                SectionHeader(title: "Popular now")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.l) {
                        ForEach(charts.songs) { song in
                            Button {
                                audio.play(song, in: charts.songs)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    ArtworkThumbnail(song: song, size: 150, cornerRadius: Radius.card, showBadge: true)
                                    Text(song.title)
                                        .font(.system(.footnote).weight(.semibold))
                                        .foregroundColor(Theme.textPrimary)
                                        .lineLimit(1)
                                        .frame(width: 150, alignment: .leading)
                                    Text(song.artist)
                                        .font(.system(.caption2))
                                        .foregroundColor(Theme.textSecondary)
                                        .lineLimit(1)
                                        .frame(width: 150, alignment: .leading)
                                }
                            }
                            .buttonStyle(BouncyButtonStyle(scale: 0.95))
                        }
                    }
                }
                .carouselBleed()
            }
        }
    }

    // MARK: - Trending on Audius (live)

    @ViewBuilder
    private var trendingSection: some View {
        switch trending.state {
        case .idle, .empty:
            EmptyView()
        case .failed:
            // A shelf that failed to load is not a shelf with nothing in it,
            // and the difference matters to someone on a bad connection.
            ShelfFailure(title: "Trending on Audius") {
                Task { await trending.load { try await AudiusService.shared.trending() } }
            }
        case .loading:
            ShelfPlaceholder(title: "Trending on Audius")
        case .loaded:
            VStack(alignment: .leading, spacing: Space.l) {
                SectionHeader(title: "Trending on Audius")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.l) {
                        ForEach(trending.songs) { song in
                            Button {
                                audio.play(song, in: trending.songs)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    ArtworkThumbnail(song: song, size: 150, cornerRadius: Radius.card, showBadge: true)
                                    Text(song.title)
                                        .font(.system(.footnote).weight(.semibold))
                                        .foregroundColor(Theme.textPrimary)
                                        .lineLimit(1)
                                        .frame(width: 150, alignment: .leading)
                                    Text(song.artist)
                                        .font(.system(.caption2))
                                        .foregroundColor(Theme.textSecondary)
                                        .lineLimit(1)
                                        .frame(width: 150, alignment: .leading)
                                }
                            }
                            .buttonStyle(BouncyButtonStyle(scale: 0.95))
                        }
                    }
                }
                .carouselBleed()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.sonavaDisplay)
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
                // Both header buttons must be one species and one size. The
                // left one used to draw its circle *inside* the glyph
                // (`waveform.circle.fill`), which rendered 26.7pt against the
                // right one's 40 — a 33% break in a two-item cluster.
                headerButtonFace("waveform", tint: Theme.accentSoft)
            }
            .buttonStyle(BouncyButtonStyle())
            .hitTarget()
            .identified(AccessibilityID.shazamButton, label: "Discover")

            Button {
                showSettings = true
            } label: {
                // `sparkles` belongs to AI Mix; using it here too pointed one
                // glyph at two unrelated destinations in the same viewport.
                headerButtonFace(proStore.isPro ? "person.fill" : "person",
                                 tint: Theme.accentSoft)
            }
            .buttonStyle(BouncyButtonStyle())
            .hitTarget()
            .identified(AccessibilityID.settingsButton, label: "Settings")
        }
    }

    /// One shape, one size, for every control in the header.
    private func headerButtonFace(_ symbol: String, tint: Color) -> some View {
        Circle()
            .fill(Theme.surfaceElevated)
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(.body).weight(.semibold))
                    .foregroundColor(tint)
            )
            .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    // MARK: - Your Sound

    /// Hidden until there is something to show — an empty stats card on a fresh
    /// install is noise, not a feature.
    @ViewBuilder
    private var statsCard: some View {
        if history.hasHistory {
            StatsTeaserCard(stats: history.stats(range: .week)) {
                Haptics.impact()
                showStats = true
            }
        }
    }

    // MARK: - Recently played

    private var recentlyPlayed: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionHeader(title: "Recently played")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.l) {
                    ForEach(library.recentSongs) { song in
                        Button {
                            audio.play(song, in: library.songs)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ArtworkThumbnail(song: song, size: 130, cornerRadius: Radius.card)
                                Text(song.title)
                                    .font(.system(.footnote).weight(.semibold))
                                    .foregroundColor(Theme.textPrimary)
                                    .lineLimit(1)
                                    .frame(width: 130, alignment: .leading)
                            }
                        }
                        .buttonStyle(BouncyButtonStyle(scale: 0.95))
                    }
                }
            }
            .carouselBleed()
        }
    }

    // MARK: - Quick picks

    private var quickPicks: some View {
        VStack(alignment: .leading, spacing: Space.m) {
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
