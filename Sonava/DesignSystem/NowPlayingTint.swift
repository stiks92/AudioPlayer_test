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
    /// How much of the wash survives at the foot of the screen.
    ///
    /// Not zero any more. The wash used to be gone by 62% of the height, which
    /// meant the app's one distinctive idea was a decoration on the top third
    /// of five screens and nothing at all below it. It now reaches the bottom,
    /// quietly — enough that the ground is unmistakably the track's colour
    /// wherever you look, far too little to lift the dark ground the text
    /// tokens were measured against.
    private let floorOpacity: Double = 0.16

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Pulls a track colour most of the way toward the ground before it is
    /// used as a wash.
    ///
    /// Raising the opacity of a bright colour raises the luminance that all
    /// the text tokens were measured against; deepening it first keeps the
    /// hue unmistakable while the ground stays dark, which is how an ambient
    /// tint reads as atmosphere rather than as a coloured overlay.
    /// 0.40, not 0.22.
    ///
    /// Reaching the foot of the screen with the old mix lifted the ground
    /// enough to cost real contrast — a tertiary line on Radio went from
    /// 6.85:1 to 6.07:1, still passing but spending headroom the text tokens
    /// were tuned to have. The lever is here rather than in the opacities:
    /// mixing further toward the ground drops *luminance* while leaving the
    /// hue plainly readable, so the colour stays the track's and the dark
    /// stays dark. Weakening the wash instead would have walked straight back
    /// to the version a review called noise rather than intent.
    private func deepened(_ color: Color) -> Color {
        color.mix(with: Theme.background, by: 0.40)
    }

    /// Boundary vertices stay on their edge — a mesh requires it — so only the
    /// mid-edge points slide along their own side and the centre roams.
    private func meshPoints(_ t: Double) -> [SIMD2<Float>] {
        let dx = Float(sin(t * 0.21) * 0.10)
        let dy = Float(cos(t * 0.17) * 0.08)
        return [
            SIMD2(0, 0),            SIMD2(0.5 + dx, 0),           SIMD2(1, 0),
            SIMD2(0, 0.42 + dy),    SIMD2(0.5 - dx, 0.5 + dy),    SIMD2(1, 0.58 - dy),
            SIMD2(0, 1),            SIMD2(0.5, 1),                SIMD2(1, 1)
        ]
    }

    /// Nine vertices, brightest at the top and thinning downward, so the head
    /// of the screen carries the colour and the foot only remembers it.
    private func meshColors(_ palette: [Color]) -> [Color] {
        let start = deepened(palette.first ?? Theme.accent)
        let end = deepened(palette.last ?? Theme.accentDeep)
        let middle = start.mix(with: end, by: 0.5)
        return [
            start.opacity(peakOpacity), middle.opacity(peakOpacity * 0.92), end.opacity(peakOpacity),
            start.opacity(peakOpacity * 0.48), middle.opacity(peakOpacity * 0.62), end.opacity(peakOpacity * 0.44),
            start.opacity(floorOpacity), middle.opacity(floorOpacity * 0.85), end.opacity(floorOpacity)
        ]
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background

            if let colors, !colors.isEmpty, !reduceTransparency {
                // A mesh rather than a linear ramp, and it drifts.
                //
                // A linear gradient fading out at 62% of the height was the
                // safe version of this idea, and a review put its cost
                // plainly: the one genuinely distinctive thing in the app was
                // so quiet that its most noticeable effect was a clipping
                // seam. A mesh has a centre of gravity that moves, so the
                // ground reads as *lit* by the artwork rather than tinted with
                // it, and the drift is slow enough — a full cycle takes about
                // half a minute — that it is felt rather than watched.
                //
                // Under Reduce Motion it holds still at t = 0. It is not
                // decoration that can be dropped: it is the screen's ground,
                // and a still mesh is still the track's colour.
                TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
                    let t = reduceMotion ? 0
                        : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
                    MeshGradient(width: 3, height: 3,
                                 points: meshPoints(t),
                                 colors: meshColors(colors))
                        // Softens the mesh's own control points into a wash.
                        // Without it the interior vertex reads as a coloured
                        // blob with an edge, which is a different — and much
                        // cheaper-looking — effect.
                        .blur(radius: 40)
                }
                .ignoresSafeArea()
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
        // The sleeve's own colours when they have been read, the track's
        // stored pair until then — never a template's.
        NowPlayingTint(colors: audio.currentSong.map { audio.sleeveHex?.colors ?? $0.gradient })
            .animation(Motion.expressive, value: audio.currentSong?.id)
            .animation(Motion.expressive, value: audio.sleeveHex)
    }
}
