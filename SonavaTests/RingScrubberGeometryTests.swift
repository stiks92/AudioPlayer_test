//
//  RingScrubberGeometryTests.swift
//  SonavaTests
//
//  The ring scrubber is the inverse of the arc head's placement, and an
//  off-by-a-quadrant error there is invisible in code review — the gesture
//  still "works", it just seeks somewhere else. So the mapping is pinned at
//  the four clock positions, at the 12-o'clock seam where angles wrap, and
//  in the centre dead zone where the angle is noise.
//
//  Pure arithmetic: no views, no audio session — safe under the parallel run.
//

import Testing
import CoreGraphics
@testable import Sonava

struct RingScrubberGeometryTests {

    /// The player's real geometry: a 316pt surface, ring radius 136.
    private let center = CGPoint(x: 158, y: 158)
    private let radius: CGFloat = 136

    private func progress(clockAngleDegrees: Double) -> Double? {
        // 0° = 12 o'clock, growing clockwise — the dial's own convention.
        let theta = clockAngleDegrees * .pi / 180 - .pi / 2
        return RingScrubberGeometry.progress(
            at: CGPoint(x: center.x + radius * CGFloat(cos(theta)),
                        y: center.y + radius * CGFloat(sin(theta))),
            center: center)
    }

    @Test("The four clock positions map to their quarters")
    func clockPositions() throws {
        #expect(abs(try #require(progress(clockAngleDegrees: 0)) - 0) < 1e-9)
        #expect(abs(try #require(progress(clockAngleDegrees: 90)) - 0.25) < 1e-9)
        #expect(abs(try #require(progress(clockAngleDegrees: 180)) - 0.5) < 1e-9)
        #expect(abs(try #require(progress(clockAngleDegrees: 270)) - 0.75) < 1e-9)
    }

    @Test("Angles wrap: just short of 12 o'clock is just short of the end")
    func angleWrapping() throws {
        let nearlyFull = try #require(progress(clockAngleDegrees: 359))
        #expect(nearlyFull > 0.99 && nearlyFull < 1.0)
        let justPast = try #require(progress(clockAngleDegrees: 361))
        #expect(justPast > 0 && justPast < 0.01)
        // Several turns of extra phase change nothing.
        let lapped = try #require(progress(clockAngleDegrees: 90 + 720))
        #expect(abs(lapped - 0.25) < 1e-9)
    }

    @Test("The centre is a dead zone, its edge is not")
    func centerDeadZone() throws {
        #expect(RingScrubberGeometry.progress(at: center, center: center) == nil)
        let inside = CGPoint(x: center.x + RingScrubberGeometry.deadZoneRadius - 1,
                             y: center.y)
        #expect(RingScrubberGeometry.progress(at: inside, center: center) == nil)
        let atEdge = CGPoint(x: center.x + RingScrubberGeometry.deadZoneRadius,
                             y: center.y)
        let progress = try #require(RingScrubberGeometry.progress(at: atEdge, center: center))
        #expect(abs(progress - 0.25) < 1e-9)
    }

    @Test("Crossing the seam pins to the end the finger came from")
    func seamClamp() {
        // Dragging clockwise through 12: 0.97 → raw 0.02 must pin at 1…
        #expect(RingScrubberGeometry.resolved(raw: 0.02, previous: 0.97) == 1)
        // …and stay pinned while the finger lingers past the seam…
        #expect(RingScrubberGeometry.resolved(raw: 0.05, previous: 1) == 1)
        // …until it comes back to the same side, which releases the pin.
        #expect(RingScrubberGeometry.resolved(raw: 0.9, previous: 1) == 0.9)
        // The mirror image, dragging anticlockwise through 12.
        #expect(RingScrubberGeometry.resolved(raw: 0.98, previous: 0.03) == 0)
        #expect(RingScrubberGeometry.resolved(raw: 0.95, previous: 0) == 0)
        // Ordinary movement passes through untouched.
        #expect(RingScrubberGeometry.resolved(raw: 0.5, previous: 0.45) == 0.5)
    }
}
