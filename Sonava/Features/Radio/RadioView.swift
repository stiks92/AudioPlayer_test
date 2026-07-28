//
//  RadioView.swift
//  Sonava
//
//  Internet radio, powered by the free Radio Browser directory.
//

import SwiftUI

struct RadioView: View {
    @EnvironmentObject private var audio: AudioManager

    @StateObject private var feed = SongFeed()
    @State private var selectedTag: String? = nil

    /// Radio Browser is queried by English tag; only the label translates.
    private let genres: [FilterChip<String>] = [
        FilterChip("Top", ""), FilterChip("Lo-fi", "lofi"), FilterChip("Jazz", "jazz"),
        FilterChip("Chillout", "chillout"), FilterChip("Classical", "classical"),
        FilterChip("Electronic", "electronic"), FilterChip("News", "news"),
        FilterChip("Rock", "rock"), FilterChip("Ambient", "ambient"),
        FilterChip("Hip-Hop", "hip-hop")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Space.screenMargin) {
                        header
                        genreChips
                        content
                    }
                    .padding(.horizontal, Space.screenMargin)
                    .padding(.top, 8)
                    .padding(.bottom, 140)
                }
            }
            .navigationBarHidden(true)
        }
        .task { await reload() }
    }

    private var header: some View {
        Text("Radio")
            .font(.sonavaDisplay)
            .foregroundColor(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var genreChips: some View {
        FilterChipRow(chips: genres,
                      selection: Binding(get: { selectedTag ?? "" },
                                         set: { selectedTag = $0.isEmpty ? nil : $0 })) { _ in
            Task { await reload() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch feed.state {
        case .idle, .loading:
            loading
        case .failed:
            Button { Task { await reload() } } label: {
                message(icon: "wifi.slash", text: "Couldn't reach the radio directory.\nTap to retry.")
            }
            .buttonStyle(.plain)
        case .empty:
            message(icon: "magnifyingglass", text: "No stations found for this genre.")
        case .loaded:
            LazyVStack(spacing: 2) {
                ForEach(feed.songs) { station in
                    Button {
                        audio.play(station, in: feed.songs)
                    } label: {
                        SongRow(song: station)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var loading: some View {
        VStack(spacing: Space.l) {
            ProgressView()
                .tint(Theme.accentSoft)
            Text("Tuning in…")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func message(icon: String, text: LocalizedStringKey) -> some View {
        VStack(spacing: Space.m) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundColor(Theme.textTertiary)
            Text(text)
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }

    private func reload() async {
        let tag = selectedTag
        await feed.load {
            if let tag {
                return try await RadioBrowserService.shared.stations(tag: tag)
            } else {
                return try await RadioBrowserService.shared.trending()
            }
        }
    }
}
