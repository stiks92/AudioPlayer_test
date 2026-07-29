//
//  MiniPlayerView.swift
//  Sonava
//
//  Compact transport that lives above the tab bar and expands into the
//  full Now Playing scene when tapped.
//

import SwiftUI

struct MiniPlayerView: View {
    /// Where the mini player is being shown.
    enum Style {
        /// iOS 26's tab-view accessory slot. The system draws the glass, the
        /// shape and the shadow, and morphs it as the tab bar contracts — so
        /// the view must bring content only.
        case accessory
        /// Floated above the tab bar ourselves, on iOS 18–25.
        case docked
    }

    var style: Style = .docked
    let namespace: Namespace.ID
    let onExpand: () -> Void

    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var clock: PlaybackClock

    /// A permanently moving element is exactly what this setting exists to
    /// calm; the bars rest at their floor rather than disappearing, so the
    /// row keeps its shape.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The accessory slot is short and the system owns its chrome, so the
    /// docked layout's artwork and padding do not fit it.
    private var artworkSide: CGFloat { style == .accessory ? 36 : 44 }
    private var horizontalPadding: CGFloat { style == .accessory ? Space.m : Space.s + 2 }
    private var verticalPadding: CGFloat { style == .accessory ? Space.xs + 2 : Space.s }

    var body: some View {
        if let song = audio.currentSong {
            VStack(spacing: 0) {
                HStack(spacing: Space.m) {
                    ArtworkImage(song: song, glyphSize: 14)
                        .frame(width: artworkSide, height: artworkSide)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.inner(Radius.control, inset: 3),
                                                    style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        MarqueeText(text: song.title, font: .subheadline.weight(.semibold))
                            .frame(height: 18)
                        Text(song.artist)
                            .font(.sonavaRowMeta)
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: Space.xs)

                    // The one element on screen 100% of the time, and it was a
                    // static glyph beside dead space. It breathes with the
                    // actual output level, in the playing track's own colours —
                    // the same palette that tints the ground behind it, so the
                    // two finally say the same thing.
                    AudioVisualizerView(
                        level: clock.audioLevel,
                        isActive: audio.isPlaying && !reduceMotion,
                        barCount: 7,
                        tint: song.gradient.first ?? Theme.accentSoft
                    )
                    .frame(width: 34, height: 20)
                    .accessibilityHidden(true)

                    Button {
                        audio.togglePlayPause()
                    } label: {
                        PlayPauseGlyph(isPlaying: audio.isPlaying, size: 19)
                            .font(.system(.body).weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: Space.hitTarget, height: Space.hitTarget)
                    }
                    .buttonStyle(BouncyButtonStyle())
                    .accessibilityIdentifier(AccessibilityID.playPauseButton)
                    .accessibilityLabel(Text(audio.isPlaying ? "Pause" : "Play"))

                    Button {
                        audio.next()
                    } label: {
                        SonavaIcon(glyph: .next, size: 19)
                            .font(.system(.subheadline).weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: Space.hitTarget, height: Space.hitTarget)
                    }
                    .buttonStyle(BouncyButtonStyle())
                    .accessibilityLabel(Text("Next"))
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)

                // A hairline of progress, docked only. In the accessory slot the
                // system rounds and insets the capsule, so a full-bleed rule at
                // its bottom edge reads as a rendering artefact.
                if style == .docked {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Theme.hairline)
                            Rectangle()
                                .fill(LinearGradient(colors: song.gradient,
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * CGFloat(clock.progress))
                        }
                    }
                    .frame(height: 2)
                }
            }
            .modifier(MiniPlayerSurface(style: style, gradient: song.gradient))
            .contentShape(Rectangle())
            .onTapGesture(perform: onExpand)
            .accessibilityIdentifier(AccessibilityID.miniPlayer)
        }
    }
}

/// The chrome around the mini player, which the system owns in the accessory
/// slot and we own when docked.
private struct MiniPlayerSurface: ViewModifier {
    let style: MiniPlayerView.Style
    let gradient: [Color]

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .accessory:
            // The system owns the glass here, so this adds no surface of its
            // own — but glass samples whatever is scrolled beneath it, which
            // meant the mini player took its colour from a passing tile while
            // the ground behind it took its colour from the playing track.
            // Two colour systems, two different tracks, 200pt apart.
            //
            // A wash from *this* track sits under the glass so the two agree,
            // faint enough to leave the label contrast alone.
            content.background(
                LinearGradient(colors: gradient.map { $0.opacity(0.30) },
                               startPoint: .leading, endPoint: .trailing)
            )
        case .docked:
            content
                .background(
                    ZStack {
                        LinearGradient(colors: gradient.map { $0.opacity(0.35) },
                                       startPoint: .leading, endPoint: .trailing)
                        Rectangle().fill(.ultraThinMaterial)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                .padding(.horizontal, Space.m)
        }
    }
}
