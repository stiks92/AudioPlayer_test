//
//  SonavaIcons.swift
//  Sonava
//
//  The app's own icon set, drawn rather than borrowed.
//
//  A design review named the problem exactly: a stock SF Symbol is fine as a
//  label beside text in a settings row, and a tell the moment it becomes the
//  hero of a screen, a tile, an empty state or a tab. `sparkles` — used seven
//  times here — is the universal "a machine made this" mark. Nothing on any of
//  the thirteen screens had been made specifically for this app except its
//  waveform mark, which appeared on one screen.
//
//  ## The language
//
//  Every glyph is built from the same two primitives the app mark is built
//  from: **capsules and arcs**, with rounded terminals. Stroke weight, cap
//  style and the grid are shared, so a row of these reads as one family rather
//  than as a collection.
//
//  - 24×24 grid, coordinates expressed as fractions of the frame so a glyph is
//    identical at 18pt and at 64pt.
//  - Stroke is `Icon.stroke` × the scale factor, round cap, round join.
//  - Optical weight over mathematical weight: a glyph made mostly of verticals
//    reads heavier than one made of arcs at the same stroke, so a few are drawn
//    a hair lighter. Where that happens it is noted on the shape.
//
//  ## Why drawn and not downloaded
//
//  A downloaded pack would be somebody else's language, and every free set is
//  already in a thousand apps — the same anonymity in a different typeface.
//  Drawing them costs a file and makes the set ours: it can echo the mark, and
//  it can carry meanings no general-purpose pack has, like "this server is
//  answering" or "this band is boosted".
//

import SwiftUI
import UIKit

// MARK: - Shared geometry

enum Icon {
    /// Stroke weight at a 24pt glyph. Scales with the frame.
    static let stroke: CGFloat = 2
    /// The grid every path is authored on.
    static let grid: CGFloat = 24

    static func style(for size: CGFloat, weight: CGFloat = stroke) -> StrokeStyle {
        StrokeStyle(lineWidth: weight * size / grid, lineCap: .round, lineJoin: .round)
    }
}

/// Draws one of the app's glyphs at a given size.
///
/// A view rather than a `Shape` because several glyphs are two shapes — an
/// outline plus a filled accent — and because the fill and stroke roles differ
/// per glyph.
struct SonavaIcon: View {
    enum Glyph {
        case home, search, radio, podcasts, library
        case play, pause, next, previous, shuffle
        case aiMix, equalizer, download, note, streak, heart, server, stats
        case chevronRight, chevronDown, more, sleep, infinity
        case restore, shield, scrobble, wave, lock, close, plus
        case repeatAll, repeatOne, person, palette
    }

    let glyph: Glyph
    var size: CGFloat = 24
    var tint: Color = .white

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let path = Self.path(for: glyph, size: s)
            context.stroke(path.stroked, with: .color(tint), style: Icon.style(for: s, weight: path.weight))
            if let filled = path.filled {
                context.fill(filled, with: .color(tint))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: - The glyphs

    struct Drawing {
        var stroked: Path
        var filled: Path?
        var weight: CGFloat = Icon.stroke
    }

    static func path(for glyph: Glyph, size s: CGFloat) -> Drawing {
        /// Grid coordinate → point.
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x / Icon.grid * s, y: y / Icon.grid * s)
        }
        /// A capsule bar centred on `x`, from `y0` to `y1`, drawn as a stroke
        /// so it inherits the family's round terminals.
        func bar(_ path: inout Path, x: CGFloat, from y0: CGFloat, to y1: CGFloat) {
            path.move(to: p(x, y0))
            path.addLine(to: p(x, y1))
        }

        var stroked = Path()
        var filled: Path?
        var weight = Icon.stroke

        switch glyph {
        case .home:
            // A roof drawn as one arc-cornered stroke rather than the system's
            // hard gable: the family has no sharp corners anywhere else.
            stroked.move(to: p(3.5, 10.5))
            stroked.addQuadCurve(to: p(12, 3.5), control: p(6.5, 6.2))
            stroked.addQuadCurve(to: p(20.5, 10.5), control: p(17.5, 6.2))
            stroked.move(to: p(5.5, 9.6))
            stroked.addLine(to: p(5.5, 19))
            stroked.addQuadCurve(to: p(7.5, 20.5), control: p(5.5, 20.5))
            stroked.addLine(to: p(16.5, 20.5))
            stroked.addQuadCurve(to: p(18.5, 19), control: p(18.5, 20.5))
            stroked.addLine(to: p(18.5, 9.6))

        case .search:
            // The lens is a circle and the handle a capsule at the same angle
            // as the mark's bars are spaced — 45°, so it lines up optically
            // with everything else in the bar.
            stroked.addEllipse(in: CGRect(x: p(3.5, 3.5).x, y: p(3.5, 3.5).y,
                                          width: p(12, 0).x, height: p(12, 0).x))
            stroked.move(to: p(14.2, 14.2))
            stroked.addLine(to: p(20, 20))

        case .radio:
            // Waves rising from a source.
            //
            // Two earlier drawings failed in ways only the gallery could show.
            // Four arcs either side of a dot closed into a rounded box, because
            // `addArc` on a path with a current point draws a line to the arc's
            // start first — each arc is its own `Path` now. Then three arcs
            // spaced 3.8 units apart merged into a solid fan at a 2-unit
            // stroke. Two arcs, well separated, is what reads.
            let source = p(12, 19.2)
            filled = Path(ellipseIn: CGRect(x: source.x - 1.7 / Icon.grid * s,
                                            y: source.y - 1.7 / Icon.grid * s,
                                            width: 3.4 / Icon.grid * s,
                                            height: 3.4 / Icon.grid * s))
            // Two arcs, not three. At three the 3.8-unit spacing was barely
            // wider than the 2-unit stroke and they merged into a solid fan.
            for radius in [5.4, 10.8] as [CGFloat] {
                var arc = Path()
                arc.addArc(center: source, radius: radius / Icon.grid * s,
                           startAngle: .degrees(222), endAngle: .degrees(318),
                           clockwise: false)
                stroked.addPath(arc)
            }

        case .podcasts:
            // A capsule head on a cradle — the head is the same capsule the
            // mark is made of, stood upright.
            stroked.addRoundedRect(in: CGRect(x: p(9.2, 2.8).x, y: p(9.2, 2.8).y,
                                              width: p(5.6, 0).x, height: p(10.4, 0).x),
                                   cornerSize: CGSize(width: p(2.8, 0).x, height: p(2.8, 0).x))
            stroked.move(to: p(5.6, 11.6))
            stroked.addQuadCurve(to: p(18.4, 11.6), control: p(12, 19.6))
            bar(&stroked, x: 12, from: 17.6, to: 21)

        case .library:
            // Three capsule bars of the mark's own proportions, laid on their
            // side. The tab that holds your music is drawn from the app's mark.
            stroked.move(to: p(4, 6.5));  stroked.addLine(to: p(20, 6.5))
            stroked.move(to: p(4, 12));   stroked.addLine(to: p(15, 12))
            stroked.move(to: p(4, 17.5)); stroked.addLine(to: p(18, 17.5))

        case .play:
            // Rounded at every corner, which the system triangle is not.
            filled = {
                var path = Path()
                path.move(to: p(7.5, 4.6))
                path.addLine(to: p(19.4, 11.2))
                path.addQuadCurve(to: p(19.4, 12.8), control: p(20.4, 12))
                path.addLine(to: p(7.5, 19.4))
                path.addQuadCurve(to: p(6, 18.4), control: p(6, 19.4))
                path.addLine(to: p(6, 5.6))
                path.addQuadCurve(to: p(7.5, 4.6), control: p(6, 4.6))
                path.closeSubpath()
                return path
            }()

        case .pause:
            weight = 4.4          // two bars read light at the family stroke
            bar(&stroked, x: 8.6, from: 5.4, to: 18.6)
            bar(&stroked, x: 15.4, from: 5.4, to: 18.6)

        case .next, .previous:
            let mirror: (CGFloat) -> CGFloat = { glyph == .next ? $0 : Icon.grid - $0 }
            filled = {
                var path = Path()
                path.move(to: p(mirror(5.5), 5.2))
                path.addLine(to: p(mirror(14.5), 11.3))
                path.addQuadCurve(to: p(mirror(14.5), 12.7), control: p(mirror(15.4), 12))
                path.addLine(to: p(mirror(5.5), 18.8))
                path.closeSubpath()
                return path
            }()
            bar(&stroked, x: mirror(17.8), from: 5.6, to: 18.4)
            weight = 2.6

        case .shuffle:
            // Two paths that swap sides. Drawn as S-bends rather than straight
            // diagonals: crossing two straight lines at the centre reads as an
            // X — scissors, a close, a delete — not as two routes trading
            // places, which is what shuffling is.
            for flipped in [false, true] {
                let near: CGFloat = flipped ? 16.4 : 7.6
                let far: CGFloat = flipped ? 7.6 : 16.4
                stroked.move(to: p(3.4, near))
                stroked.addLine(to: p(7.4, near))
                stroked.addCurve(to: p(16.2, far),
                                 control1: p(12.4, near), control2: p(11.2, far))
                stroked.addLine(to: p(19.4, far))
            }
            // Heads on the two ends that leave the frame, so the eye has a
            // direction to follow.
            for y in [7.6, 16.4] as [CGFloat] {
                stroked.move(to: p(17.0, y - 2.3))
                stroked.addLine(to: p(20.0, y))
                stroked.addLine(to: p(17.0, y + 2.3))
            }

        case .aiMix:
            // Replaces `sparkles`, which is the single most recognisable
            // "generated app" glyph there is and was used seven times.
            //
            // It is the app's own mark with its middle bar carried upward and
            // a point of light leaving it: the waveform *becoming* something.
            // The meaning is specific to this feature, which is the thing no
            // general-purpose icon pack can do.
            weight = 2.2
            bar(&stroked, x: 5.2, from: 13.5, to: 17.5)
            bar(&stroked, x: 9.0, from: 10.5, to: 20.5)
            bar(&stroked, x: 12.8, from: 6.5, to: 21)
            bar(&stroked, x: 16.6, from: 12.5, to: 19)
            filled = {
                var path = Path()
                let c = p(18.6, 5.4)
                let r = 2.9 / Icon.grid * s
                for index in 0..<4 {
                    let angle = Double(index) * .pi / 2
                    let tip = CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
                    let next = Double(index + 1) * .pi / 2
                    let nextTip = CGPoint(x: c.x + cos(next) * r, y: c.y + sin(next) * r)
                    if index == 0 { path.move(to: tip) }
                    path.addQuadCurve(to: nextTip, control: c)
                }
                path.closeSubpath()
                return path
            }()

        case .equalizer:
            // Two tracks with knobs at different heights — the screen it opens,
            // in miniature, rather than the system's three abstract sliders.
            weight = 2
            bar(&stroked, x: 8, from: 3.5, to: 20.5)
            bar(&stroked, x: 16, from: 3.5, to: 20.5)
            filled = {
                var path = Path()
                let r = 2.6 / Icon.grid * s
                for (x, y) in [(8.0, 9.0), (16.0, 15.0)] as [(CGFloat, CGFloat)] {
                    let c = p(x, y)
                    path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                }
                return path
            }()

        case .download:
            // Into a tray with a rounded lip, not a bare arrow: downloads land
            // somewhere in this app, and the glyph says so.
            stroked.move(to: p(12, 3.5))
            stroked.addLine(to: p(12, 14.2))
            stroked.move(to: p(7.6, 10.2))
            stroked.addLine(to: p(12, 14.6))
            stroked.addLine(to: p(16.4, 10.2))
            stroked.move(to: p(4.5, 15.5))
            stroked.addLine(to: p(4.5, 18.5))
            stroked.addQuadCurve(to: p(7, 20.5), control: p(4.5, 20.5))
            stroked.addLine(to: p(17, 20.5))
            stroked.addQuadCurve(to: p(19.5, 18.5), control: p(19.5, 20.5))
            stroked.addLine(to: p(19.5, 15.5))

        case .note:
            // The head is the mark's capsule, tilted. Used wherever artwork is
            // missing, so it is seen more than any other glyph in the set.
            stroked.move(to: p(9.5, 17.5))
            stroked.addLine(to: p(9.5, 5.2))
            stroked.addLine(to: p(19, 3.2))
            stroked.addLine(to: p(19, 15))
            filled = {
                var path = Path()
                for (x, y) in [(7.0, 17.6), (16.5, 15.1)] as [(CGFloat, CGFloat)] {
                    let c = p(x, y)
                    let rx = 2.9 / Icon.grid * s
                    let ry = 2.4 / Icon.grid * s
                    path.addEllipse(in: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
                }
                return path
            }()

        case .streak:
            // A flame leans. The first attempt was symmetrical about its own
            // axis and rendered as an egg: a flame is recognised by the curl
            // at its tip and by *not* being the same on both sides.
            stroked.move(to: p(13.6, 2.4))
            stroked.addQuadCurve(to: p(10.6, 9.6), control: p(9.4, 5.4))
            stroked.addQuadCurve(to: p(6.4, 8.2), control: p(8.2, 9.4))
            stroked.addQuadCurve(to: p(4.8, 14.8), control: p(4.4, 11.6))
            stroked.addQuadCurve(to: p(12, 21.4), control: p(5.2, 19.4))
            stroked.addQuadCurve(to: p(19.2, 14.8), control: p(18.8, 19.4))
            stroked.addQuadCurve(to: p(13.6, 2.4), control: p(19.6, 8.0))
            stroked.closeSubpath()

        case .heart:
            stroked.move(to: p(12, 20.2))
            stroked.addQuadCurve(to: p(3.6, 10.4), control: p(3.6, 16.4))
            stroked.addQuadCurve(to: p(12, 8.2), control: p(3.6, 3.4))
            stroked.addQuadCurve(to: p(20.4, 10.4), control: p(20.4, 3.4))
            stroked.addQuadCurve(to: p(12, 20.2), control: p(20.4, 16.4))
            stroked.closeSubpath()

        case .server:
            // Two racked units with a status lamp each — the shape a
            // self-hoster actually has in the cupboard.
            for y in [6.0, 14.0] as [CGFloat] {
                stroked.addRoundedRect(in: CGRect(x: p(3.5, y).x, y: p(3.5, y).y,
                                                  width: p(17, 0).x, height: p(4.6, 0).x),
                                       cornerSize: CGSize(width: p(1.6, 0).x, height: p(1.6, 0).x))
            }
            filled = {
                var path = Path()
                let r = 1.15 / Icon.grid * s
                for y in [8.3, 16.3] as [CGFloat] {
                    let c = p(17.2, y)
                    path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                }
                return path
            }()

        case .stats:
            // Bars in the mark's proportions again, so the listening-stats
            // screen and the app icon share a silhouette.
            weight = 3.2
            bar(&stroked, x: 5.5, from: 15.5, to: 20)
            bar(&stroked, x: 12, from: 8.5, to: 20)
            bar(&stroked, x: 18.5, from: 4, to: 20)

        case .chevronRight:
            // Disclosure. Drawn a hair lighter: two bare strokes read heavier
            // than an arc-built glyph at the same weight.
            weight = 1.8
            stroked.move(to: p(10, 7))
            stroked.addLine(to: p(15, 12))
            stroked.addLine(to: p(10, 17))

        case .chevronDown:
            weight = 1.8
            stroked.move(to: p(7, 10))
            stroked.addLine(to: p(12, 15))
            stroked.addLine(to: p(17, 10))

        case .more:
            // Three dots, the family's dot size (the radio source, the disc
            // spindle) rather than the system's.
            var dots = Path()
            for x in [5.5, 12, 18.5] as [CGFloat] {
                dots.addEllipse(in: CGRect(x: (x - 1.6) / Icon.grid * s,
                                           y: (12 - 1.6) / Icon.grid * s,
                                           width: 3.2 / Icon.grid * s,
                                           height: 3.2 / Icon.grid * s))
            }
            filled = dots

        case .sleep:
            // A timer dial, not a crescent. Two crescent drafts failed on the
            // gallery sheet — a hook, then a razor-thin ring that read as a
            // plain circle — and the row this serves is literally "Sleep
            // timer", so the dial is the truer glyph anyway. Face plus two
            // hands at ten-past-ten, all strokes.
            var face = Path()
            face.addArc(center: p(12, 12), radius: 7.2 / Icon.grid * s,
                        startAngle: .degrees(0), endAngle: .degrees(360),
                        clockwise: false)
            stroked.addPath(face)
            stroked.move(to: p(12, 12))
            stroked.addLine(to: p(12, 8))
            stroked.move(to: p(12, 12))
            stroked.addLine(to: p(15, 13.6))

        case .infinity:
            // A lemniscate as two teardrops meeting in the middle — arcs and
            // round joins, no straight segments anywhere.
            stroked.move(to: p(12, 12))
            stroked.addCurve(to: p(12, 12),
                             control1: p(20.5, 5.6), control2: p(20.5, 18.4))
            stroked.addCurve(to: p(12, 12),
                             control1: p(3.5, 5.6), control2: p(3.5, 18.4))

        case .restore:
            // An open circle with an arrowhead at its mouth.
            var arc = Path()
            arc.addArc(center: p(12, 12), radius: 7 / Icon.grid * s,
                       startAngle: .degrees(80), endAngle: .degrees(400),
                       clockwise: false)
            stroked.addPath(arc)
            let tip = CGPoint(x: (12 + 7 * cos(.pi * 40 / 180)) / Icon.grid * s,
                              y: (12 + 7 * sin(.pi * 40 / 180)) / Icon.grid * s)
            var head = Path()
            head.move(to: CGPoint(x: tip.x - 3.6 / Icon.grid * s, y: tip.y - 0.4 / Icon.grid * s))
            head.addLine(to: tip)
            head.addLine(to: CGPoint(x: tip.x - 0.4 / Icon.grid * s, y: tip.y - 3.6 / Icon.grid * s))
            stroked.addPath(head)

        case .shield:
            // Symmetric curves to a rounded point; the top edge dips like the
            // mark's arcs rather than running flat.
            stroked.move(to: p(12, 4.4))
            stroked.addCurve(to: p(19, 7.2),
                             control1: p(14.4, 5.6), control2: p(17, 6.6))
            stroked.addCurve(to: p(12, 19.8),
                             control1: p(19, 13.6), control2: p(16.4, 17.6))
            stroked.addCurve(to: p(5, 7.2),
                             control1: p(7.6, 17.6), control2: p(5, 13.6))
            stroked.addCurve(to: p(12, 4.4),
                             control1: p(7, 6.6), control2: p(9.6, 5.6))
            stroked.closeSubpath()

        case .scrobble:
            // The radio glyph turned on its side: a source dot broadcasting
            // to the right — listens leaving the building.
            let source = p(5.4, 12)
            filled = Path(ellipseIn: CGRect(x: source.x - 1.7 / Icon.grid * s,
                                            y: source.y - 1.7 / Icon.grid * s,
                                            width: 3.4 / Icon.grid * s,
                                            height: 3.4 / Icon.grid * s))
            for radius in [5.4, 10.8] as [CGFloat] {
                var arc = Path()
                arc.addArc(center: source, radius: radius / Icon.grid * s,
                           startAngle: .degrees(-48), endAngle: .degrees(48),
                           clockwise: false)
                stroked.addPath(arc)
            }

        case .wave:
            // One clean sine period — a stream, not the mark's bars.
            stroked.move(to: p(3, 12))
            stroked.addCurve(to: p(12, 12),
                             control1: p(6, 4.6), control2: p(9, 4.6))
            stroked.addCurve(to: p(21, 12),
                             control1: p(15, 19.4), control2: p(18, 19.4))

        case .repeatAll, .repeatOne:
            // One rounded loop with a gap at the top-left, the arrowhead
            // sitting in the gap pointing along the direction of travel.
            // `.repeatOne` adds the mark's short bar in the middle.
            weight = 1.8
            stroked.move(to: p(10.2, 5.5))
            stroked.addLine(to: p(16, 5.5))
            stroked.addArc(center: p(16, 8.25), radius: 2.75 / Icon.grid * s,
                           startAngle: .degrees(270), endAngle: .degrees(0),
                           clockwise: false)
            stroked.addLine(to: p(18.75, 15.75))
            stroked.addArc(center: p(16, 15.75), radius: 2.75 / Icon.grid * s,
                           startAngle: .degrees(0), endAngle: .degrees(90),
                           clockwise: false)
            stroked.addLine(to: p(8, 18.5))
            stroked.addArc(center: p(8, 15.75), radius: 2.75 / Icon.grid * s,
                           startAngle: .degrees(90), endAngle: .degrees(180),
                           clockwise: false)
            stroked.addLine(to: p(5.25, 8.25))
            stroked.addArc(center: p(8, 8.25), radius: 2.75 / Icon.grid * s,
                           startAngle: .degrees(180), endAngle: .degrees(270),
                           clockwise: false)
            var head = Path()
            head.move(to: p(8.1, 3.3))
            head.addLine(to: p(10.4, 5.5))
            head.addLine(to: p(8.1, 7.7))
            stroked.addPath(head)
            if glyph == .repeatOne {
                bar(&stroked, x: 12, from: 10.4, to: 13.6)
            }

        case .person:
            // Head and shoulders, both arcs.
            stroked.addEllipse(in: CGRect(x: p(8.4, 3.6).x, y: p(8.4, 3.6).y,
                                          width: 7.2 / Icon.grid * s, height: 7.2 / Icon.grid * s))
            var shoulders = Path()
            shoulders.addArc(center: p(12, 21.4), radius: 7.4 / Icon.grid * s,
                             startAngle: .degrees(205), endAngle: .degrees(335),
                             clockwise: false)
            stroked.addPath(shoulders)

        case .palette:
            // An open ring with three paint dabs — the accent picker's own
            // shape (a circle of colour) three times over.
            var ring = Path()
            ring.addArc(center: p(12, 12), radius: 8 / Icon.grid * s,
                        startAngle: .degrees(0), endAngle: .degrees(360),
                        clockwise: false)
            stroked.addPath(ring)
            var dabs = Path()
            // Asymmetric on purpose: two dabs level with each other under a
            // third read as a face at glyph sizes.
            for (x, y) in [(8.6, 9.2), (10.4, 15.4), (15.4, 12.2)] {
                dabs.addEllipse(in: CGRect(x: (x - 1.5) / Icon.grid * s,
                                           y: (y - 1.5) / Icon.grid * s,
                                           width: 3 / Icon.grid * s,
                                           height: 3 / Icon.grid * s))
            }
            filled = dabs

        case .close:
            weight = 1.8
            stroked.move(to: p(7.5, 7.5))
            stroked.addLine(to: p(16.5, 16.5))
            stroked.move(to: p(16.5, 7.5))
            stroked.addLine(to: p(7.5, 16.5))

        case .plus:
            weight = 1.8
            stroked.move(to: p(12, 5.5))
            stroked.addLine(to: p(12, 18.5))
            stroked.move(to: p(5.5, 12))
            stroked.addLine(to: p(18.5, 12))

        case .lock:
            // Body as a rounded rect, shackle as an arc.
            stroked.addRoundedRect(in: CGRect(x: 5.5 / Icon.grid * s, y: 11 / Icon.grid * s,
                                              width: 13 / Icon.grid * s, height: 9 / Icon.grid * s),
                                   cornerSize: CGSize(width: 2.6 / Icon.grid * s,
                                                      height: 2.6 / Icon.grid * s))
            var shackle = Path()
            shackle.addArc(center: p(12, 11), radius: 4 / Icon.grid * s,
                           startAngle: .degrees(180), endAngle: .degrees(360),
                           clockwise: false)
            stroked.addPath(shackle)
        }

        return Drawing(stroked: stroked, filled: filled, weight: weight)
    }
}

#if DEBUG
#Preview("The set") {
    let all: [SonavaIcon.Glyph] = [.home, .search, .radio, .podcasts, .library,
                                   .play, .pause, .next, .previous, .shuffle,
                                   .aiMix, .equalizer, .download, .note,
                                   .streak, .heart, .server, .stats,
                                   .chevronRight, .chevronDown, .more, .sleep,
                                   .infinity, .restore, .shield, .scrobble,
                                   .wave, .lock, .close, .plus,
                                   .repeatAll, .repeatOne, .person, .palette]
    return ZStack {
        Theme.background.ignoresSafeArea()
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 28) {
            ForEach(Array(all.enumerated()), id: \.offset) { _, glyph in
                SonavaIcon(glyph: glyph, size: 30)
            }
        }
        .padding(Space.xl)
    }
}
#endif

#if DEBUG
/// The whole set on one sheet, reachable with `-openIcons`.
///
/// Icons are judged as a family or not at all: a glyph that looks fine beside
/// its own label can still be two stroke weights away from its neighbours, and
/// that only shows up when they are side by side at one size.
struct IconGallery: View {
    private let all: [(SonavaIcon.Glyph, String)] = [
        (.home, "home"), (.search, "search"), (.radio, "radio"),
        (.podcasts, "podcasts"), (.library, "library"),
        (.play, "play"), (.pause, "pause"), (.next, "next"),
        (.previous, "previous"), (.shuffle, "shuffle"),
        (.aiMix, "aiMix"), (.equalizer, "equalizer"), (.download, "download"),
        (.note, "note"), (.streak, "streak"), (.heart, "heart"),
        (.server, "server"), (.stats, "stats"),
        (.chevronRight, "chevronRight"), (.chevronDown, "chevronDown"),
        (.more, "more"), (.sleep, "sleep"), (.infinity, "infinity"),
        (.restore, "restore"), (.shield, "shield"), (.scrobble, "scrobble"),
        (.wave, "wave"), (.lock, "lock"),
        (.close, "close"), (.plus, "plus"),
        (.repeatAll, "repeatAll"), (.repeatOne, "repeatOne"),
        (.person, "person"), (.palette, "palette")
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4),
                          spacing: Space.xl) {
                    ForEach(Array(all.enumerated()), id: \.offset) { _, entry in
                        VStack(spacing: Space.s) {
                            SonavaIcon(glyph: entry.0, size: 34)
                            Text(entry.1)
                                .font(.system(.caption2))
                                .foregroundColor(Theme.textTertiary)
                        }
                    }
                }
                .padding(Space.screenMargin)
                // The same set small, where stroke weight errors show worst.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 9),
                          spacing: Space.l) {
                    ForEach(Array(all.enumerated()), id: \.offset) { _, entry in
                        SonavaIcon(glyph: entry.0, size: 18)
                    }
                }
                .padding(Space.screenMargin)
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif

// MARK: - Rasterised, for places that demand an image

/// A glyph as a template `UIImage`.
///
/// The system tab bar takes a label and renders it into its own image; a
/// `Canvas` does not survive that trip, and the first attempt at custom tab
/// icons shipped a bar with five labels and no glyphs at all. Handing UIKit an
/// image it can tint is the way in.
///
/// Cached because a tab bar re-reads its items often and re-rendering a vector
/// per pass would be visible.
@MainActor
enum IconRaster {
    private static var cache: [String: UIImage] = [:]

    static func image(_ glyph: SonavaIcon.Glyph, size: CGFloat) -> UIImage? {
        let key = "\(glyph)@\(size)"
        if let hit = cache[key] { return hit }
        let renderer = ImageRenderer(content: SonavaIcon(glyph: glyph, size: size, tint: .white))
        renderer.scale = UIScreen.main.scale
        guard let rendered = renderer.uiImage?.withRenderingMode(.alwaysTemplate) else { return nil }
        cache[key] = rendered
        return rendered
    }
}
