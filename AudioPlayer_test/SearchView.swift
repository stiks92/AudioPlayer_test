//
//  SearchView.swift
//  AudioPlayer_test
//
//  Search with a custom field and a mood grid shown when idle.
//

import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var library: MusicLibrary

    @State private var query = ""
    @FocusState private var focused: Bool

    private var results: [Song] { library.search(query) }

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
                        Text("Search")
                            .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                            .foregroundColor(Theme.textPrimary)

                        searchField

                        if query.isEmpty {
                            moodGrid
                        } else if results.isEmpty {
                            emptyState
                        } else {
                            resultsList
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 140)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.textSecondary)
            TextField("Songs, artists, albums", text: $query)
                .focused($focused)
                .foregroundColor(.white)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
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

    private var moodGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Browse moods")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(moods, id: \.0) { mood in
                    ZStack(alignment: .topLeading) {
                        LinearGradient(colors: mood.1, startPoint: .topLeading, endPoint: .bottomTrailing)
                        Text(mood.0)
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
                        if let random = library.songs.randomElement() {
                            audio.play(random, in: library.songs)
                        }
                    }
                }
            }
        }
    }

    private var resultsList: some View {
        LazyVStack(spacing: 2) {
            ForEach(results) { song in
                Button {
                    audio.play(song, in: results)
                } label: {
                    SongRow(song: song)
                }
                .buttonStyle(.plain)
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
        .padding(.top, 60)
    }
}
