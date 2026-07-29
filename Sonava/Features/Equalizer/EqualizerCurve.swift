//
//  EqualizerCurve.swift
//  Sonava
//
//  The equalizer's response curve — the thing that makes the screen an
//  instrument rather than ten disconnected sliders.
//
//  A design review put the gap plainly: every hardware and software equalizer
//  draws the filter shape it produces; this one drew dots. It also had no 0 dB
//  reference, so "flat" was communicated only by ten knobs happening to line
//  up, and no motion, so choosing a preset teleported them.
//
//  The curve is a Catmull-Rom spline through the ten band gains. That is not a
//  decorative choice: the underlying `AVAudioUnitEQ` bands are parametric at
//  half-octave bandwidth on ISO octave centres, so their summed response really
//  is close to a smooth interpolation between the control points. The picture
//  tells the truth about the sound.
//

import SwiftUI

// MARK: - Animatable gains

/// Lets a `Shape` interpolate between two whole sets of band gains, so
/// applying a preset draws the curve moving instead of cutting to it.
///
/// SwiftUI can animate a shape only through `animatableData`, and `[Float]`
/// is not `VectorArithmetic` — hence this.
struct AnimatableGains: VectorArithmetic {
    var values: [Double]

    init(_ values: [Double]) { self.values = values }

    static var zero: AnimatableGains { AnimatableGains([]) }

    /// Pads the shorter operand so two curves of different arity still blend
    /// rather than trapping.
    private static func aligned(_ a: [Double], _ b: [Double]) -> ([Double], [Double]) {
        let count = max(a.count, b.count)
        return (a + Array(repeating: 0, count: count - a.count),
                b + Array(repeating: 0, count: count - b.count))
    }

    static func + (lhs: AnimatableGains, rhs: AnimatableGains) -> AnimatableGains {
        let (a, b) = aligned(lhs.values, rhs.values)
        return AnimatableGains(zip(a, b).map(+))
    }

    static func - (lhs: AnimatableGains, rhs: AnimatableGains) -> AnimatableGains {
        let (a, b) = aligned(lhs.values, rhs.values)
        return AnimatableGains(zip(a, b).map(-))
    }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }
}

// MARK: - The curve

/// The filter response as a path. `closed` fills the area back to the 0 dB
/// line; the open form is the stroke on top of it.
struct ResponseCurve: Shape {
    var gains: AnimatableGains
    /// ±limit in dB maps to the full height.
    let limit: Double
    var closed = false

    var animatableData: AnimatableGains {
        get { gains }
        set { gains = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let values = gains.values
        guard values.count > 1 else { return Path() }

        let midY = rect.midY
        // The same mapping the handles use: ten equal columns, each knob at its
        // column's centre. Dividing by `count - 1` instead drew the curve 11%
        // wider than the controls it claims to describe, so it missed every
        // knob — by up to 7.7pt at 8 kHz — while this file's own header claimed
        // the picture tells the truth about the sound.
        let step = rect.width / CGFloat(values.count)
        let points = values.enumerated().map { index, gain in
            CGPoint(x: rect.minX + step * (CGFloat(index) + 0.5),
                    y: midY - CGFloat(gain / limit) * (rect.height / 2))
        }

        var path = Path()
        // Run flat out to both edges so the graph still spans its full width
        // without inventing control points that no band corresponds to.
        path.move(to: CGPoint(x: rect.minX, y: points[0].y))
        path.addLine(to: points[0])
        // Catmull-Rom, expressed as the cubic Bézier segments SwiftUI draws.
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            let control1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6,
                                   y: p1.y + (p2.y - p0.y) / 6)
            let control2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6,
                                   y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: control1, control2: control2)
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: points.last!.y))

        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: midY))
            path.addLine(to: CGPoint(x: rect.minX, y: midY))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - The graph behind the bands

/// Gridlines, the 0 dB reference and the filled response, drawn behind the
/// band controls.
struct ResponseGraph: View {
    let gains: [Float]
    let limit: Float

    private var animatable: AnimatableGains {
        AnimatableGains(gains.map(Double.init))
    }

    var body: some View {
        ZStack {
            // ±6 dB rules first, then 0 dB brighter — "flat" should be legible
            // as a shape against a reference, not inferred from knob positions.
            GeometryReader { geo in
                let half = geo.size.height / 2
                let sixth = CGFloat(6 / limit) * half
                ForEach([-sixth, sixth], id: \.self) { offset in
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(height: 1)
                        .position(x: geo.size.width / 2, y: half + offset)
                }
                // The plot withheld its own ordinate: three rules and no
                // numbers, so "how much boost is that" had no answer except
                // dragging the band again.
                // `y = half + offset`, and positive y is *down*, so the top
                // rule is +6 and the bottom is −6. Labelling them the other way
                // round told the reader the plot was upside down.
                ForEach([(-sixth, "+6"), (sixth, "−6")], id: \.1) { offset, label in
                    Text(label)
                        .font(.system(.caption2).weight(.medium).monospacedDigit())
                        .foregroundColor(Theme.textTertiary)
                        .position(x: geo.size.width - 14, y: half + offset - 11)
                }
                // Dashed, so a flat curve resting exactly on it still reads
                // as a curve on a datum rather than as one unexplained line.
                Rectangle()
                    .fill(Theme.textTertiary)
                    .frame(height: 1)
                    .overlay(
                        Rectangle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .foregroundColor(Theme.background)
                            .frame(height: 1)
                    )
                    .position(x: geo.size.width / 2, y: half)
            }

            ResponseCurve(gains: animatable, limit: Double(limit), closed: true)
                .fill(
                    LinearGradient(colors: [Theme.accent.opacity(0.42),
                                            Theme.accent.opacity(0.10)],
                                   startPoint: .top, endPoint: .bottom)
                )

            ResponseCurve(gains: animatable, limit: Double(limit))
                .stroke(Theme.accentSoft, style: StrokeStyle(lineWidth: 3,
                                                             lineCap: .round,
                                                             lineJoin: .round))
        }
        .animation(Motion.expressive, value: gains)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
