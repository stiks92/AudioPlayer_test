//
//  SearchView.swift
//  Sonava
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

    /// A mood tile: a translated label, the term we actually search for, and
    /// the gradient that gives the tile its character.
    private struct Mood: Identifiable {
        let title: LocalizedStringKey
        let term: String
        let gradient: [Color]
        var id: String { term }
    }

    private let moods: [Mood] = [
        Mood(title: "Cinematic",  term: "Cinematic",  gradient: [Color(hex: 0x654EA3), Color(hex: 0xEAAFC8)]),
        Mood(title: "Dark",       term: "Dark",       gradient: [Color(hex: 0x232526), Color(hex: 0x414345)]),
        Mood(title: "Tense",      term: "Tense",      gradient: [Color(hex: 0xC33764), Color(hex: 0x1D2671)]),
        Mood(title: "Uplifting",  term: "Uplifting",  gradient: [Color(hex: 0x11998E), Theme.positive]),
        Mood(title: "Melancholy", term: "Melancholy", gradient: [Color(hex: 0x355C7D), Color(hex: 0x6C5B7B)]),
        Mood(title: "Epic",       term: "Epic",       gradient: [Color(hex: 0xFF512F), Color(hex: 0xDD2476)])
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        Text("Search")
                            .font(.sonavaMasthead)
                            .foregroundColor(Theme.textPrimary)

                        searchField

                        if query.isEmpty {
                            moodGrid
                        } else {
                            resultsSections
                        }
                    }
                    .padding(.horizontal, Space.screenMargin)
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
        HStack(spacing: Space.m) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.textSecondary)
            TextField("", text: $query,
                      prompt: Text("Songs, artists, stations…")
                        .foregroundColor(Theme.textSecondary))
                .accessibilityIdentifier(AccessibilityID.searchField)
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
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .card(cornerRadius: Radius.card)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSections: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            // ── Full tracks first ──────────────────────────────
            if !localResults.isEmpty {
                sourceSection("In your library", songs: localResults)
            }
            if serverStore.isConnected, serverFeed.state == .loaded {
                sourceSection("Your server", songs: serverFeed.songs)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Department(title: "Audius · full tracks")
                    if audiusFeed.state == .loading {
                        ProgressView().tint(Theme.accentSoft)
                    }
                }
                audiusResults
            }

            // ── 30-second previews ─────────────────────────────
            if deezerFeed.state == .loaded || appleFeed.state == .loaded {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("PREVIEWS · 30 SEC")
                        .font(.system(.caption2).weight(.bold)).tracking(1)
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

    private func sourceSection(_ title: LocalizedStringKey, songs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Department(title: title)
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

    /// Moods as glass words, not painted tiles.
    ///
    /// The six tiles were gradient rectangles with the same note glyph
    /// stamped on all of them at 25% — a review called it one glyph doing six
    /// jobs, and the owner's rule since is harder: no drawn art in the frame
    /// at all. A mood has no cover, so it gets no picture — it gets its word,
    /// set large on glass, with the mood's own colour as a rim light. What
    /// carries identity is the type and the tint, which are real; nothing is
    /// pretending to be artwork.
    private var moodGrid: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Department(title: "Browse moods")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.m),
                                GridItem(.flexible(), spacing: Space.m)], spacing: Space.m) {
                ForEach(moods) { mood in
                    Button {
                        query = mood.term
                    } label: {
                        Text(mood.title)
                            .font(.system(.title3).weight(.semibold))
                            .foregroundColor(.white)
                            // Cyrillic runs wide: «Кинематографично» broke
                            // with a hyphen inside its own capsule. One line,
                            // shrinking — same rule as every other fixed slot.
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, Space.m)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background(.ultraThinMaterial,
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(colors: [mood.gradient.first?.opacity(0.9) ?? .white,
                                                                mood.gradient.last?.opacity(0.25) ?? .clear],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                                        lineWidth: 1.5)
                            )
                            .shadow(color: (mood.gradient.first ?? .clear).opacity(0.35),
                                    radius: 14, y: 6)
                    }
                    .buttonStyle(BouncyButtonStyle(scale: 0.96))
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Space.m) {
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
