//
//  RingScrubberGeometry.swift
//  Sonava
//
//  The pure math that turns a finger on the progress ring into a playback
//  position. Kept free of views and state so it can be unit-tested as
//  arithmetic: the inverse of the arc head's placement
//  (`theta = 2π·progress − π/2` in NowPlayingView), with two guards a finger
//  needs that a formula doesn't — a dead zone around the centre where the
//  angle is numerically meaningless, and a clamp at the 12-o'clock seam so
//  dragging through the top pins to an end instead of teleporting the head
//  across the whole track.
//

import SwiftUI

enum RingScrubberGeometry {

    /// Inside this radius of the ring's centre the angle flips wildly with a
    /// one-point movement, so a touch there reports nothing rather than noise.
    /// The hit donut starts far outside this; the dead zone only matters when
    /// a captured finger wanders inward mid-drag.
    static let deadZoneRadius: CGFloat = 30

    /// Finger position → progress, 0…1 around the dial: 12 o'clock is 0,
    /// 3 o'clock is 0.25, 6 is 0.5, 9 is 0.75. Returns nil inside the dead
    /// zone. This is the exact inverse of how the arc's head is drawn, so the
    /// head lands under the finger, not near it.
    static func progress(at point: CGPoint, center: CGPoint) -> Double? {
        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        guard (dx * dx + dy * dy).squareRoot() >= Double(deadZoneRadius) else { return nil }
        let full = 2 * Double.pi
        // atan2 measures from 3 o'clock; the dial measures from 12.
        let angle = atan2(dy, dx) + .pi / 2
        let wrapped = (angle.truncatingRemainder(dividingBy: full) + full)
            .truncatingRemainder(dividingBy: full)
        return wrapped / full
    }

    /// The seam clamp. A raw angle wraps at 12 o'clock — 0.99 becomes 0.01 as
    /// the finger crosses the top — which would fling the head across the
    /// track. A jump of more than half the dial in one sample can only be the
    /// seam, so it pins to the end the finger came from; the pin releases the
    /// moment the finger returns to the same side of the seam.
    static func resolved(raw: Double, previous: Double) -> Double {
        let delta = raw - previous
        if delta > 0.5 { return 0 }
        if delta < -0.5 { return 1 }
        return min(max(raw, 0), 1)
    }
}

/// The hit area of the ring scrubber: a donut centred on the progress arc,
/// wide enough to be a real touch target, with a hole so the record inside
/// keeps its own gestures. Used with `contentShape(_:eoFill: true)` — the
/// even-odd rule is what makes the hole a hole.
struct RingHitShape: Shape {
    /// Radius of the arc the donut is centred on.
    var ringRadius: CGFloat
    /// Width of the touch band, split evenly to both sides of the arc.
    var hitWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = ringRadius + hitWidth / 2
        let inner = max(0, ringRadius - hitWidth / 2)
        var path = Path()
        path.addEllipse(in: CGRect(x: center.x - outer, y: center.y - outer,
                                   width: outer * 2, height: outer * 2))
        path.addEllipse(in: CGRect(x: center.x - inner, y: center.y - inner,
                                   width: inner * 2, height: inner * 2))
        return path
    }
}
