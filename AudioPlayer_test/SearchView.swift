//
//  SearchView.swift
//  AudioPlayer_test
//
//  Unified search: the local library + live results from Audius, with a
//  mood grid shown when idle.
//

import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var serverStore: ServerStore

    @State private var query = ""
    @FocusState private var focused: Bool
    @StateObject private var audiusFeed = SongFeed()
    @StateObject private var appleFeed = SongFeed()
    @StateObject private var deezerFeed = SongFeed()
    @StateObject private var serverFeed = SongFeed()

    private var localResults: [Song] { library.search(query) }

    private let moods: [(String, [Color])] = [
        ("Cinematic", [Color(hex: 0x654EA3), Color(hex: 0xEAAFC8)]),
        ("Dark", [Color(hex: 0x232526), Color(hex: 0x414345)]),
        ("Tense", [Color(hex: 0xC33764), Color(hex: 0x1D2671)]),
        ("Uplifting", [Color(hex: 0x11998E), Color(hex: 0x38EF7D)]),
        ("Melancholy", [Color(hex: 0x355C7D), Color(hex: 0x6C5B7B)]),
        ("Epic", [Color(hex: 0xFF512F), Color(hex: 0xDD2476)])
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text(L("Search"))
                            .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                            .foregroundColor(Theme.textPrimary)

                        searchField

                        if query.isEmpty {
                            moodGrid
                        } else {
                            resultsSections
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 140)
                }
            }
            .navigationBarHidden(true)
            .task(id: query) {
                let trimmed = query.trimmingCharacters(in: .whitespaces)
                guard trimmed.count >= 2 else {
                    audiusFeed.clear()
                    appleFeed.clear()
                    deezerFeed.clear()
                    serverFeed.clear()
                    return
                }
                // Debounce keystrokes; task(id:) cancels the previous run.
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return }
                if serverStore.isConnected {
                    await serverFeed.load { try await serverStore.search(trimmed) }
                }
                await deezerFeed.load { try await DeezerService.shared.search(trimmed) }
                await appleFeed.load { try await iTunesService.shared.searchMusic(trimmed) }
                await audiusFeed.load { try await AudiusService.shared.search(trimmed) }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.textSecondary)
            TextField(L("Songs, artists, stations…"), text: $query)
                .focused($focused)
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                    audiusFeed.clear()
                    appleFeed.clear()
                    deezerFeed.clear()
                    serverFeed.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glass(cornerRadius: 16)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSections: some View {
        VStack(alignment: .leading, spacing: 22) {
            // ── Full tracks first ──────────────────────────────
            if !localResults.isEmpty {
                sourceSection("In your library", songs: localResults)
            }
            if serverStore.isConnected, serverFeed.state == .loaded {
                sourceSection("Your server", songs: serverFeed.songs)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    SectionHeader(title: "Audius · full tracks")
                    if audiusFeed.state == .loading {
                        ProgressView().tint(Theme.accentSoft)
                    }
                }
                audiusResults
            }

            // ── 30-second previews ─────────────────────────────
            if deezerFeed.state == .loaded || appleFeed.state == .loaded {
                VStack(alignment: .leading, spacing: 12) {
                    Text("PREVIEWS · 30 SEC")
                        .font(.system(size: 11, weight: .bold)).tracking(1)
                        .foregroundColor(Theme.textTertiary)
                    if deezerFeed.state == .loaded {
                        sourceSection("Deezer", songs: deezerFeed.songs)
                    }
                    if appleFeed.state == .loaded {
                        sourceSection("Apple Music", songs: appleFeed.songs)
                    }
                }
            }

            if localResults.isEmpty && audiusFeed.state == .empty
                && appleFeed.state == .empty && deezerFeed.state == .empty {
                emptyState
            }
        }
    }

    private func sourceSection(_ title: String, songs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title)
            songList(songs)
        }
    }

    @ViewBuilder
    private var audiusResults: some View {
        switch audiusFeed.state {
        case .loaded:
            songList(audiusFeed.songs)
        case .failed:
            Text("Couldn't reach Audius. Check your connection.")
                .font(.footnote)
                .foregroundColor(Theme.textTertiary)
        case .idle, .loading, .empty:
            if audiusFeed.state == .empty {
                Text("No Audius tracks matched.")
                    .font(.footnote)
                    .foregroundColor(Theme.textTertiary)
            } else {
                EmptyView()
            }
        }
    }

    private func songList(_ songs: [Song]) -> some View {
        LazyVStack(spacing: 2) {
            ForEach(songs) { song in
                Button {
                    audio.play(song, in: songs)
                } label: {
                    SongRow(song: song, showBadge: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var moodGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Browse moods")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(moods, id: \.0) { mood in
                    ZStack(alignment: .topLeading) {
                        LinearGradient(colors: mood.1, startPoint: .topLeading, endPoint: .bottomTrailing)
                        Text(L(mood.0))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .padding(14)
                        Image(systemName: "music.note")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white.opacity(0.25))
                            .rotationEffect(.degrees(25))
                            .offset(x: 70, y: 40)
                    }
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .onTapGesture {
                        query = mood.0
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 46))
                .foregroundColor(Theme.textTertiary)
            Text("No results for \u{201C}\(query)\u{201D}")
                .font(.headline)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}
