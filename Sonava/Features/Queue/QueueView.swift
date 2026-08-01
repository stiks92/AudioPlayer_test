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
                Color.black.ignoresSafeArea()
                LinearGradient(stops: [
                    .init(color: ((audio.sleeveHex?.colors ?? audio.currentSong?.gradient)?.first
                                  ?? Theme.accent).opacity(0.5), location: 0),
                    .init(color: .black, location: 0.55)
                ], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .animation(Motion.fade, value: audio.sleeveHex)

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
            }
            .doneToolbar { dismiss() }
        }
        .presentationDetents([.large, .medium])
        .preferredColorScheme(.dark)
    }

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(.footnote).weight(.bold))
            .foregroundColor(Theme.textSecondary)
            .textCase(nil)
    }

    private var upNextHeader: some View {
        HStack {
            Text("Up Next")
                .font(.system(.footnote).weight(.bold))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Button {
                withAnimation { audio.toggleShuffle() }
            } label: {
                SonavaIcon(glyph: .shuffle, size: 18)
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
        .font(.system(.subheadline).weight(.semibold))
    }
}
