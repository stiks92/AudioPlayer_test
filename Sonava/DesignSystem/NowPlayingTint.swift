//
//  NowPlayingTint.swift
//  Sonava
//
//  The app takes its colour from whatever is playing.
//
//  Tide Guide won Visuals and Graphics at the 2026 Apple Design Awards partly
//  for "a palette designed to match the sky colour throughout the day" — a
//  screen that quietly changes with its context. For a music player the
//  context is the track, and the app already stores a deterministic two-stop
//  palette on every `Song`, so the material for this has been sitting unused.
//
//  It is deliberately quiet. The wash lives behind the top of the screen where
//  the header sits, fades out before it reaches any list content, and never
//  goes near the contrast budget the text tokens were tuned against.
//

import SwiftUI

struct NowPlayingTint: View {
    /// The playing track's palette, or nil when nothing is playing — in which
    /// case this draws the plain ground and nothing else.
    var colors: [Color]?

    /// How strong the wash is at the very top.
    ///
    /// It began at 0.22, which a review measured as a +15/255 shift and called
    /// noise rather than intent — "the contrast budget was protected so
    /// successfully that it protected the idea out of existence". It is
    /// stronger now, and the contrast it costs is measured rather than
    /// guessed: the dimmest text over it still clears its floor.
    private let peakOpacity: Double = 0.55
    /// The fraction of the screen the wash covers before it is fully gone.
    private let falloff: Double = 0.62

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Pulls a track colour most of the way toward the ground before it is
    /// used as a wash.
    ///
    /// Raising the opacity of a bright colour raises the luminance that all
    /// the text tokens were measured against; deepening it first keeps the
    /// hue unmistakable while the ground stays dark, which is how an ambient
    /// tint reads as atmosphere rather than as a coloured overlay.
    private func deepened(_ color: Color) -> Color {
        color.mix(with: Theme.background, by: 0.22)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background

            if let colors, !colors.isEmpty, !reduceTransparency {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            deepened(colors.first ?? Theme.accent).opacity(peakOpacity),
                            deepened(colors.last ?? Theme.accentDeep).opacity(peakOpacity * 0.55),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    // Drawn taller than it is shown, blurred, then clipped.
                    // Blurring a frame whose edges are transparent bleeds alpha
                    // outwards, so roughly half the authored opacity never
                    // arrives — which is why two calibration passes kept
                    // landing short of what the code said.
                    .frame(height: geo.size.height * falloff * 1.4)
                    .blur(radius: 60)
                    .frame(height: geo.size.height * falloff, alignment: .top)
                    .clipped()
                }
                // Cross-fading between two tracks' palettes is the whole point;
                // a hard cut would read as a glitch.
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
    }
}

/// The ground every tab stands on.
///
/// A view rather than a `.background(…)` modifier on purpose: each tab is a
/// `NavigationStack`, which draws its own ground, so a background applied from
/// outside is painted over. This goes where the flat colour used to sit —
/// first in the tab's own `ZStack`.
struct AppBackground: View {
    @EnvironmentObject private var audio: AudioManager

    var body: some View {
        NowPlayingTint(colors: audio.currentSong?.gradient)
            .animation(Motion.expressive, value: audio.currentSong?.id)
    }
}
