//
//  QueueView.swift
//  Sonava
//
//  The playing queue: jump to any track, reorder Up Next, and swipe to
//  remove. Now Playing is pinned on top.
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
                    .opacity(0.35)
                    .ignoresSafeArea()

                List {
                    if let current = audio.currentSong {
                        Section {
                            SongRow(song: current)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } header: {
                            header("Now Playing")
                        }
                    }

                    if !audio.upNext.isEmpty {
                        Section {
                            ForEach(audio.upNext) { song in
                                Button {
                                    audio.playFromQueue(song)
                                } label: {
                                    SongRow(song: song)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                            .onMove { audio.moveUpNext(from: $0, to: $1) }
                            .onDelete { audio.removeUpNext(at: $0) }
                        } header: {
                            upNextHeader
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 10)
            }
            .foregroundColor(.white)
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton().foregroundColor(Theme.accentSoft)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(Theme.accentSoft)
                }
            }
        }
        .presentationDetents([.large, .medium])
        .preferredColorScheme(.dark)
    }

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(Theme.textSecondary)
            .textCase(nil)
    }

    private var upNextHeader: some View {
        HStack {
            Text("Up Next")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Button {
                withAnimation { audio.toggleShuffle() }
            } label: {
                Image(systemName: "shuffle")
                    .foregroundColor(audio.isShuffling ? Theme.accentSoft : Theme.textSecondary)
            }
            Button {
                withAnimation { audio.cycleRepeat() }
            } label: {
                Image(systemName: audio.repeatMode.systemImage)
                    .foregroundColor(audio.repeatMode.isActive ? Theme.accentSoft : Theme.textSecondary)
            }
        }
        .textCase(nil)
        .font(.system(size: 15, weight: .semibold))
    }
}
