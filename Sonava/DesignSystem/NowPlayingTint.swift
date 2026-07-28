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

    /// How strong the wash is at the very top. Low on purpose: the header's
    /// secondary line is the dimmest text over it, and this has to leave that
    /// measurement alone.
    private let peakOpacity: Double = 0.22
    /// The fraction of the screen the wash covers before it is fully gone.
    private let falloff: Double = 0.45

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background

            if let colors, !colors.isEmpty, !reduceTransparency {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            (colors.first ?? Theme.accent).opacity(peakOpacity),
                            (colors.last ?? Theme.accentDeep).opacity(peakOpacity * 0.45),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geo.size.height * falloff)
                    // A wide blur so the two stops read as one atmosphere
                    // rather than as a banded gradient.
                    .blur(radius: 60)
                }
                // Cross-fading between two tracks' palettes is the whole point;
                // a hard cut would read as a glitch.
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Colours a screen's ground from the track that is playing.
    func nowPlayingTint(_ song: Song?) -> some View {
        background(NowPlayingTint(colors: song?.gradient))
            .animation(Motion.expressive, value: song?.id)
    }
}
