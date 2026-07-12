//
//  QueueView.swift
//  AudioPlayer_test
//
//  The upcoming-tracks sheet. Tap any row to jump to it.
//

import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                AuroraBackground(colors: audio.currentSong?.gradient ?? [Theme.accent, Theme.background],
                                 animated: false)
                    .opacity(0.4)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Playing Queue")
                                    .font(.system(.title2, design: .rounded).weight(.bold))
                                Text("\(audio.queue.count) tracks")
                                    .font(.subheadline)
                                    .foregroundColor(Theme.textSecondary)
                            }
                            Spacer()
                            HStack(spacing: 10) {
                                Image(systemName: audio.isShuffling ? "shuffle.circle.fill" : "shuffle")
                                    .foregroundColor(audio.isShuffling ? Theme.accentSoft : Theme.textSecondary)
                                    .onTapGesture { withAnimation { audio.toggleShuffle() } }
                                Image(systemName: audio.repeatMode.systemImage)
                                    .foregroundColor(audio.repeatMode.isActive ? Theme.accentSoft : Theme.textSecondary)
                                    .onTapGesture { withAnimation { audio.cycleRepeat() } }
                            }
                            .font(.system(size: 18, weight: .semibold))
                        }
                        .padding(.vertical, 8)

                        ForEach(audio.queue) { song in
                            Button {
                                audio.playFromQueue(song)
                            } label: {
                                SongRow(song: song)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .foregroundColor(.white)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.accentSoft)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large, .medium])
        .preferredColorScheme(.dark)
    }
}
