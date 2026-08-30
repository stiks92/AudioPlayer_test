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
    @StateObject private var appleMusicFeed = SongFeed()
    @ObservedObject private var appleMusic = AppleMusicService.shared
    @ObservedObject private var serviceKeys = ServiceKeysStore.shared
    @StateObject private var appleFeed = SongFeed()
    @StateObject private var deezerFeed = SongFeed()
    @StateObject private var serverFeed = SongFeed()
    @StateObject private var archiveFeed = SongFeed()
    @StateObject private var jamendoFeed = SongFeed()

    private var localResults: [Song] { library.search(query) }

    /// A mood tile: a translated label, the term we actually search for, and
    /// the gradient that gives the tile its character.
    private struct Mood: Identifiable {
        let title: LocalizedStringKey
        let term: String
        let gradient: [Color]
        var id: String { term }
    }

    /// Rim colours from the muted, sleeve-like register the whole app now
    /// speaks (`Palette.gradientsHex`'s world) — a shelf of record tones, not
    /// the neon rainbow this grid wore before the violet purge.
    private let moods: [Mood] = [
        Mood(title: "Cinematic",  term: "Cinematic",  gradient: [Color(hex: 0x3E6E9E), Color(hex: 0x14263C)]),
        Mood(title: "Dark",       term: "Dark",       gradient: [Color(hex: 0x6E7E8C), Color(hex: 0x222A32)]),
        Mood(title: "Tense",      term: "Tense",      gradient: [Color(hex: 0xA63A3A), Color(hex: 0x2E1010)]),
        Mood(title: "Uplifting",  term: "Uplifting",  gradient: [Color(hex: 0x3E8C6E), Color(hex: 0x102E22)]),
        Mood(title: "Melancholy", term: "Melancholy", gradient: [Color(hex: 0x4A7E8C), Color(hex: 0x142E36)]),
        Mood(title: "Epic",       term: "Epic",       gradient: [Color(hex: 0xC77B4A), Color(hex: 0x4A2C18)])
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
                    archiveFeed.clear()
                    jamendoFeed.clear()
                    return
                }
                // Debounce keystrokes; task(id:) cancels the previous run.
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return }
                if serverStore.isConnected {
                    await serverFeed.load { try await serverStore.search(trimmed) }
                }
                if appleMusic.isReady {
                    await appleMusicFeed.load { try await AppleMusicService.shared.search(trimmed) }
                }
                await deezerFeed.load { try await DeezerService.shared.search(trimmed) }
                await appleFeed.load { try await iTunesService.shared.searchMusic(trimmed) }
                await audiusFeed.load { try await AudiusService.shared.search(trimmed) }
                if let clientID = serviceKeys.key(JamendoService.clientIDKey) {
                    await jamendoFeed.load { try await JamendoService(clientID: clientID).search(trimmed) }
                }
                // Last on purpose: the Archive's search index is the slowest
                // answerer here, and it must not hold up the quick shelves.
                await archiveFeed.load { try await ArchiveService.shared.search(trimmed) }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Space.m) {
            // The magnifier morphs into an × as soon as there is something to
            // clear, and tapping it clears — one glyph, both jobs.
            Button {
                guard !query.isEmpty else { return }
                query = ""
                audiusFeed.clear()
                appleFeed.clear()
                deezerFeed.clear()
                serverFeed.clear()
                archiveFeed.clear()
                jamendoFeed.clear()
            } label: {
                AnimatedIcon(glyph: .searchToX, mode: .toggle(!query.isEmpty),
                             size: 20, tint: Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(query.isEmpty)
            TextField("", text: $query,
                      prompt: Text("Songs, artists, stations…")
                        .foregroundColor(Theme.textSecondary))
                .accessibilityIdentifier(AccessibilityID.searchField)
                .focused($focused)
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .submitLabel(.search)
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
            // The subscriber's whole catalogue — full tracks, so it sits with
            // the full tracks, above the preview fold.
            if appleMusic.isReady, appleMusicFeed.state == .loaded, !appleMusicFeed.songs.isEmpty {
                sourceSection("Apple Music · your subscription", songs: appleMusicFeed.songs)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Department(title: "Audius · full tracks")
                    if audiusFeed.state == .loading {
                        AnimatedIcon(glyph: .loading, mode: .loop(true),
                                     size: 16, tint: Theme.accentSoft)
                    }
                }
                audiusResults
            }
            if jamendoFeed.state == .loaded, !jamendoFeed.songs.isEmpty {
                sourceSection("Jamendo · full tracks", songs: jamendoFeed.songs)
            }
            if archiveFeed.state == .loaded, !archiveFeed.songs.isEmpty {
                sourceSection("Internet Archive · full tracks", songs: archiveFeed.songs)
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
            let sleeves = moodSleeves
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.m),
                                GridItem(.flexible(), spacing: Space.m)], spacing: Space.m) {
                ForEach(moods) { mood in
                    Button {
                        query = mood.term
                    } label: {
                        MoodCard(mood: mood, sleeve: sleeves[mood.term])
                    }
                    .buttonStyle(BouncyButtonStyle(scale: 0.96))
                }
            }
        }
    }

    /// One real sleeve per mood, chosen deterministically from the library
    /// and spread so six moods show six different covers whenever the
    /// library has that many. The owner's rule made flesh: a mood is a
    /// record you might pull from the shelf, not a coloured rim.
    private var moodSleeves: [String: Song] {
        let pool = library.songs
        guard !pool.isEmpty else { return [:] }
        // Uniqueness is judged by the *sleeve*, not the track — several songs
        // can share one cover, and a grid with the same record twice reads as
        // a bug even when the songs differ.
        func sleeveKey(_ song: Song) -> String {
            song.artworkURL?.absoluteString ?? song.id
        }
        var usedSleeves = Set<String>()
        var out: [String: Song] = [:]
        for mood in moods {
            let hash = mood.term.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }
            var index = ((hash % pool.count) + pool.count) % pool.count
            var steps = 0
            while steps < pool.count && usedSleeves.contains(sleeveKey(pool[index])) {
                index = (index + 1) % pool.count
                steps += 1
            }
            usedSleeves.insert(sleeveKey(pool[index]))
            out[mood.term] = pool[index]
        }
        return out
    }

    /// A mood tile is a record: the sleeve fills the card, a black scrim
    /// carries the word, and the only line on it is the app-wide hairline.
    /// The muted duo is the ground *only* when the library is empty and
    /// there is no real sleeve to show.
    private struct MoodCard: View {
        let mood: Mood
        let sleeve: Song?

        var body: some View {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let sleeve {
                        ArtworkImage(song: sleeve, glyphSize: 36)
                    } else {
                        LinearGradient(colors: mood.gradient,
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }

                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.20), location: 0.52),
                    .init(color: .black.opacity(0.86), location: 1)
                ], startPoint: .top, endPoint: .bottom)

                Text(mood.title)
                    .font(.system(.title3).weight(.light))
                    .foregroundColor(.white)
                    // Cyrillic runs wide: «Кинематографично» must stay one
                    // line — same rule as every other fixed slot.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(Space.m)
            }
            .frame(height: 172)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: Space.m) {
            SonavaIcon(glyph: .wave, size: 46, tint: Theme.textTertiary)
            Text("No results for \u{201C}\(query)\u{201D}")
                .font(.headline)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}
