//
//  TransportMorph.swift
//  Sonava
//
//  Play and pause are one shape.
//
//  Every player on the phone cross-fades one glyph out and another in, because
//  `Image(systemName:)` gives you two unrelated bitmaps and nothing else is
//  possible. Owning the paths makes a different thing available: the triangle
//  can *split* and stand up into two bars, and the bars can lean back into a
//  triangle. It is the most-pressed control in the app, so it is the one worth
//  spending a shape on.
//
//  ## How a morph between different topologies is done
//
//  A triangle is one subpath and a pause is two, which cannot be interpolated
//  directly. The trick is to describe both as the *same* eight points — two
//  quadrilaterals — and move the points:
//
//  - Paused, the quads are two upright bars.
//  - Playing, the left quad is the left half of the triangle and the right quad
//    is its tip, with two of its corners collapsed onto the apex.
//
//  Sliding those eight points between the two sets is the whole animation, and
//  because it is expressed through `animatableData` SwiftUI drives it with
//  whatever spring the call site is already using.
//

import SwiftUI

struct PlayPauseShape: Shape {
    /// 0 = play, 1 = pause.
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    // Authored on the icon set's 24pt grid so this control sits in the same
    // family as everything around it.
    private static let grid: CGFloat = 24

    /// Left quad, then right quad; four corners each, clockwise from top-left.
    ///
    /// Authored to fill the grid, not to sit politely inside it. The first
    /// version spanned 6.2–17.8 of 24 — 48% of its own frame — so at the call
    /// sites, which pass a size the way every other icon does, the mark came
    /// out at 17pt inside a 76pt button and read as a typo.
    private static let playPoints: [CGPoint] = [
        CGPoint(x: 3.6, y: 2.4),  CGPoint(x: 12.5, y: 7.2),
        CGPoint(x: 12.5, y: 16.8), CGPoint(x: 3.6, y: 21.6),
        CGPoint(x: 12.5, y: 7.2), CGPoint(x: 21.4, y: 12.0),
        CGPoint(x: 21.4, y: 12.0), CGPoint(x: 12.5, y: 16.8)
    ]

    private static let pausePoints: [CGPoint] = [
        CGPoint(x: 3.4, y: 3.0),  CGPoint(x: 9.2, y: 3.0),
        CGPoint(x: 9.2, y: 21.0), CGPoint(x: 3.4, y: 21.0),
        CGPoint(x: 14.8, y: 3.0), CGPoint(x: 20.6, y: 3.0),
        CGPoint(x: 20.6, y: 21.0), CGPoint(x: 14.8, y: 21.0)
    ]

    /// Which corners may be rounded while playing.
    ///
    /// Not all of them. The two quads meet along a shared edge to form the
    /// triangle, and rounding the corners on that edge pulls each half away
    /// from the other — the screenshot showed the triangle split into a slab
    /// and a detached tip. The interior corners stay sharp at `progress == 0`
    /// and round up as the shape becomes two bars, where every corner is
    /// exterior and every corner should be soft.
    private static let playCornerRounding: [CGFloat] = [
        1, 0, 0, 1,   // left half: outer corners only
        0, 1, 1, 0    // right half: the apex only
    ]

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let t = CGFloat(min(max(progress, 0), 1))
        let corner = 2.1 / Self.grid * s

        func point(_ index: Int) -> CGPoint {
            let a = Self.playPoints[index]
            let b = Self.pausePoints[index]
            return CGPoint(x: (a.x + (b.x - a.x) * t) / Self.grid * s,
                           y: (a.y + (b.y - a.y) * t) / Self.grid * s)
        }

        func radius(_ index: Int) -> CGFloat {
            let playR = Self.playCornerRounding[index]
            return corner * (playR + (1 - playR) * t)
        }

        var path = Path()
        for quad in 0..<2 {
            let base = quad * 4
            let corners = (0..<4).map { point(base + $0) }
            // Starting halfway up the left edge, the first corner met is
            // `corners[0]`. Passing `corners[1]` there — an off-by-one — put a
            // notch in the top of every bar, which the screenshot showed as a
            // bite taken out of the shape.
            path.move(to: midpoint(corners[3], corners[0]))
            for index in 0..<4 {
                path.addArc(tangent1End: corners[index],
                            tangent2End: corners[(index + 1) % 4],
                            radius: radius(base + index))
            }
            path.closeSubpath()
        }
        return path
    }

    private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}

/// The transport glyph: one shape that leans between the two states.
struct PlayPauseGlyph: View {
    let isPlaying: Bool
    var size: CGFloat = 24
    var tint: Color = .white

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PlayPauseShape(progress: isPlaying ? 1 : 0)
            .fill(tint)
            .frame(width: size, height: size)
            // Reduce Motion gets the same two shapes without the journey
            // between them: the control still reads correctly, it just arrives.
            .animation(reduceMotion ? .none : Motion.press, value: isPlaying)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Morph") {
    struct Demo: View {
        @State private var playing = false
        var body: some View {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: Space.xxl) {
                    PlayPauseGlyph(isPlaying: playing, size: 96)
                    Button("Toggle") { playing.toggle() }
                        .buttonStyle(PrimaryCapsuleButtonStyle())
                        .padding(.horizontal, Space.xxl)
                }
            }
        }
    }
    return Demo()
}
#endif

// MARK: - Shared geometry between the two players

/// Ids for the elements that travel between the mini player and the full one.
///
/// A constant rather than a string literal at each end, because a geometry
/// match that does not match fails silently: the element simply cross-fades,
/// which looks like a design decision rather than a typo.
enum PlayerTransition {
    static let artwork = "player.artwork"
}

/// A transport key with nothing behind it: the reference's controls are bare
/// white glyphs floating on black, and a circle would be chrome it never asked
/// for.
struct BareTransportButton: View {
    let glyph: SonavaIcon.Glyph
    var size: CGFloat = 28
    let action: () -> Void

    init(glyph: SonavaIcon.Glyph, size: CGFloat = 28, action: @escaping () -> Void) {
        self.glyph = glyph; self.size = size; self.action = action
    }

    var body: some View {
        Button(action: action) {
            SonavaIcon(glyph: glyph, size: size)
                .frame(width: Space.hitTarget + 8, height: Space.hitTarget + 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.9))
    }
}

/// A circular cover that turns like a record while playback runs.
///
/// One rotation every seven seconds — slow enough to feel mechanical rather
/// than busy. The angle accumulates through a `TimelineView` so pausing
/// freezes the disc where it is instead of snapping it back to twelve.
struct SpinningDisc: View {
    let song: Song
    var side: CGFloat = 36
    var isSpinning: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isSpinning)) { timeline in
            let angle = isSpinning
                ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 7) / 7 * 360
                : 0
            ArtworkImage(song: song, glyphSize: side * 0.4)
                .frame(width: side, height: side)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .overlay(Circle().fill(.black.opacity(0.9)).frame(width: side * 0.14))
                .rotationEffect(.degrees(angle))
        }
    }
}
