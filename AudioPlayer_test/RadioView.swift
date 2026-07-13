//
//  RadioView.swift
//  AudioPlayer_test
//
//  Internet radio, powered by the free Radio Browser directory.
//

import SwiftUI

struct RadioView: View {
    @EnvironmentObject private var audio: AudioManager

    @StateObject private var feed = SongFeed()
    @State private var selectedTag: String? = nil

    private let genres: [(String, String)] = [
        ("Top", ""), ("Lo-fi", "lofi"), ("Jazz", "jazz"), ("Chillout", "chillout"),
        ("Classical", "classical"), ("Electronic", "electronic"), ("News", "news"),
        ("Rock", "rock"), ("Ambient", "ambient"), ("Hip-Hop", "hip-hop")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        genreChips
                        content
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 140)
                }
            }
            .navigationBarHidden(true)
        }
        .task { await reload() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(Theme.accentSoft)
            Text("Radio")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundColor(Theme.textPrimary)
        }
    }

    private var genreChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(genres, id: \.0) { label, tag in
                    let isSelected = (selectedTag ?? "") == tag
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? Theme.background : Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(isSelected ? Color.white : Color.white.opacity(0.08))
                        )
                        .onTapGesture {
                            selectedTag = tag.isEmpty ? nil : tag
                            Task { await reload() }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch feed.state {
        case .idle, .loading:
            loading
        case .failed:
            message(icon: "wifi.slash", text: "Couldn't reach the radio directory.\nPull to retry.")
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
        VStack(spacing: 14) {
            ProgressView()
                .tint(Theme.accentSoft)
            Text("Tuning in…")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func message(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
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
