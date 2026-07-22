//
//  LyricsView.swift
//  Sonava
//
//  Karaoke-style synced lyrics with tap-to-seek, plus a graceful plain-text
//  and empty state.
//

import SwiftUI

@MainActor
final class LyricsLoader: ObservableObject {
    enum State: Equatable {
        case idle, loading, none, failed
        case loaded(Lyrics)
    }

    @Published private(set) var state: State = .idle
    private var loadedID: String?

    func load(for song: Song?) async {
        guard let song else { state = .none; return }
        if loadedID == song.id, case .loaded = state { return }
        loadedID = song.id
        state = .loading
        do {
            if let lyrics = try await LyricsService.shared.fetch(
                artist: song.artist, title: song.title, album: song.album, duration: nil
            ) {
                state = .loaded(lyrics)
            } else {
                state = .none
            }
        } catch {
            state = .failed
        }
    }
}

struct LyricsView: View {
    @EnvironmentObject private var audio: AudioManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var loader = LyricsLoader()

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground(colors: audio.currentSong?.gradient ?? [Theme.accent, Theme.background],
                                 animated: false)
                    .overlay(Theme.background.opacity(0.35))

                content
            }
            .foregroundColor(.white)
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(.white)
                }
            }
            .task(id: audio.currentSong) { await loader.load(for: audio.currentSong) }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch loader.state {
        case .idle, .loading:
            ProgressView().tint(.white)
        case .failed:
            message(icon: "wifi.slash", text: "Couldn't load lyrics.")
        case .none:
            message(icon: "text.quote", text: "No lyrics found for this track.")
        case .loaded(let lyrics):
            if lyrics.isSynced {
                SyncedLyricsList(lines: lyrics.synced)
            } else if let plain = lyrics.plain {
                ScrollView {
                    Text(plain)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                }
            } else {
                message(icon: "text.quote", text: "No lyrics found for this track.")
            }
        }
    }

    private func message(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundColor(.white.opacity(0.4))
            Text(text)
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

private struct SyncedLyricsList: View {
    let lines: [LyricLine]
    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var clock: PlaybackClock

    private var activeIndex: Int? {
        var index: Int?
        for (i, line) in lines.enumerated() {
            if line.time <= clock.currentTime + 0.25 { index = i } else { break }
        }
        return index
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Color.clear.frame(height: 40)
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        Text(line.text)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(index == activeIndex ? .white : .white.opacity(0.35))
                            .scaleEffect(index == activeIndex ? 1.04 : 1, anchor: .leading)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: activeIndex)
                            .id(line.id)
                            .onTapGesture {
                                audio.seek(to: line.time)
                                Haptics.selection()
                            }
                    }
                    Color.clear.frame(height: 200)
                }
                .padding(.horizontal, 24)
            }
            .onChange(of: activeIndex) { newValue in
                guard let newValue, lines.indices.contains(newValue) else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(lines[newValue].id, anchor: .center)
                }
            }
        }
    }
}
