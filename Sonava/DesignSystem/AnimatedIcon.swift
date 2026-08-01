//
//  AnimatedIcon.swift
//  Sonava
//
//  Animated micro-glyphs. The owner's brief was explicit: no static stock
//  iconography where motion can carry meaning — downloaded packs welcome,
//  and this is one: useAnimations (MIT, react-useanimations 2.10.0), a set
//  of stroke icons whose animation *is* their state change — a heart that
//  fills, a plus that becomes an ×, a search glass that becomes a close.
//  Plus Airbnb's sample burst heart for the one place that deserves
//  celebration rather than a state flip.
//
//  Every JSON in the pack is authored in black; `tint` recolours every
//  stroke and fill at render time via a wildcard keypath, so the same asset
//  serves any token — ivory, destructive, a sleeve colour — and the pack
//  never fights the palette.
//
//  Reduce Motion contract: toggles and bursts jump to their end state,
//  loops hold their first frame. State is always legible; only the journey
//  is skipped.
//

import SwiftUI
import Lottie

/// A bundled micro-animation; the raw value is the resource filename.
enum AnimatedGlyph: String {
    case heart
    /// Airbnb's TwitterHeart: outline → burst → filled. For the player.
    case heartBurst
    /// A living pulse line — the "now playing" indicator.
    case activity
    case microphone = "microphone2"
    case download
    case infinity
    /// Plus morphs to ×. Add-to-playlist / dismiss pairs.
    case plusToX
    /// Magnifier morphs to ×.
    case searchToX
    case settings = "settings2"
    case skipBack, skipForward
    case volume
    case loading = "loading3"
    case checkmark, star, bookmark, share, radioButton, explore
}

/// How an `AnimatedIcon` is driven.
enum AnimatedIconMode: Equatable {
    /// Rests at either end; flipping the flag animates between them.
    /// The natural mode for state icons (heart, bookmark, plusToX).
    case toggle(Bool)
    /// Plays start-to-end once each time the counter changes.
    case burst(Int)
    /// Loops while active, holds the first frame while not (spinners, pulses).
    case loop(Bool)
}

struct AnimatedIcon: View {
    let glyph: AnimatedGlyph
    var mode: AnimatedIconMode
    var size: CGFloat = 24
    var tint: Color = Theme.textPrimary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LottieView(animation: Self.animation(glyph.rawValue))
            .playbackMode(playbackMode)
            .configure { [tint] view in
                view.setValueProvider(
                    ColorValueProvider(tint.lottie),
                    keypath: AnimationKeypath(keypath: "**.Color")
                )
            }
            // A burst must restart even though two consecutive playback
            // modes compare equal; recreating the view is the reliable way.
            .id(burstID)
            .frame(width: size, height: size)
            .allowsHitTesting(false)
    }

    private var burstID: Int {
        if case .burst(let n) = mode { return n }
        return 0
    }

    private var playbackMode: LottiePlaybackMode {
        switch mode {
        case .toggle(let on):
            if reduceMotion { return .paused(at: .progress(on ? 1 : 0)) }
            return .playing(.toProgress(on ? 1 : 0, loopMode: .playOnce))
        case .burst:
            return reduceMotion ? .paused(at: .progress(1))
                                : .playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce))
        case .loop(let active):
            return active && !reduceMotion
                ? .playing(.fromProgress(0, toProgress: 1, loopMode: .loop))
                : .paused(at: .progress(0))
        }
    }

    /// Synchronized-group resources are copied flat into the bundle, but a
    /// future project-format change could preserve the folder — try both so
    /// the pack survives either layout.
    private static func animation(_ name: String) -> LottieAnimation? {
        LottieAnimation.named(name) ?? LottieAnimation.named(name, subdirectory: "Animations")
    }
}

private extension Color {
    /// Lottie's colour type, resolved through UIKit so palette tokens work.
    var lottie: LottieColor {
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return LottieColor(r: r, g: g, b: b, a: a)
    }
}

#if DEBUG
/// Every glyph in every mode on one screen — the pack's contact sheet,
/// reached with `-openAnimLab`. Exists so a capture can verify recolouring
/// and motion before any glyph is woven into a real screen.
struct AnimatedIconLab: View {
    @State private var on = false
    @State private var fires = 0

    private let toggles: [AnimatedGlyph] = [.heart, .heartBurst, .plusToX, .searchToX,
                                            .checkmark, .star, .bookmark, .radioButton]
    private let loops: [AnimatedGlyph] = [.activity, .microphone, .loading, .infinity,
                                          .settings, .volume, .explore, .download]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: Space.xl) {
                grid(of: toggles.map { ($0, AnimatedIconMode.toggle(on)) }, tint: Theme.accent)
                grid(of: loops.map { ($0, .loop(true)) }, tint: Theme.textPrimary)
                grid(of: [(.skipBack, .burst(fires)), (.skipForward, .burst(fires)),
                          (.share, .burst(fires)), (.heartBurst, .toggle(on))],
                     tint: Theme.destructive)
            }
            .padding(Space.xl)
        }
        .task {
            // Let the capture see mid-flight and end states without a tap.
            try? await Task.sleep(for: .milliseconds(600))
            on = true
            fires += 1
        }
    }

    private func grid(of items: [(AnimatedGlyph, AnimatedIconMode)], tint: Color) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: Space.xl) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                AnimatedIcon(glyph: item.0, mode: item.1, size: 36, tint: tint)
            }
        }
    }
}
#endif
