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
                        Button {
                            withAnimation(Motion.expressive) { audio.toggleCrateMix() }
                        } label: {
                            HStack(spacing: Space.s) {
                                SonavaIcon(glyph: .shuffle, size: 14,
                                           tint: audio.isCrateMixActive ? Theme.background : Theme.accentSoft)
                                Text("Crate Mix")
                            }
                        }
                        .buttonStyle(audio.isCrateMixActive
                                     ? AnyButtonStyle(PrimaryCapsuleButtonStyle(expands: false))
                                     : AnyButtonStyle(SecondaryCapsuleButtonStyle(expands: false)))
                        .accessibilityIdentifier("queue.crateMix")
                        Section {
                            ForEach(audio.upNext) { song in
                                let transition = audio.isCrateMixActive
                                    ? audio.crateMixTransitions[song.id] : nil
                                Button {
                                    audio.playFromQueue(song)
                                } label: {
                                    HStack(spacing: Space.s) {
                                        SongRow(song: song)
                                        if let transition {
                                            TransitionChip(transition: transition)
                                        }
                                    }
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
                SonavaIcon(glyph: audio.repeatMode.glyph, size: 19,
                           tint: audio.repeatMode.isActive ? Theme.accentSoft : Theme.textSecondary)
            }
        }
        .textCase(nil)
        .font(.system(.subheadline).weight(.semibold))
    }
}


/// The planner's verdict on how this row will be entered — quiet, machine
/// face, honest about the no-stretch bands.
private struct TransitionChip: View {
    let transition: CrateMix.Transition

    var body: some View {
        Text(label)
            .font(.sonavaFact)
            .foregroundColor(tint)
            .padding(.horizontal, Space.s)
            .padding(.vertical, 3)
            .background(Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 1))
            .lineLimit(1)
            .fixedSize()
    }

    private var label: LocalizedStringKey {
        switch transition {
        case .beatMatched: return "beat-matched"
        case .shortBlend: return "short blend"
        case .plainFade: return "fade"
        }
    }

    private var tint: Color {
        switch transition {
        case .beatMatched: return Theme.accentSoft
        case .shortBlend: return Theme.textSecondary
        case .plainFade: return Theme.textTertiary
        }
    }
}
