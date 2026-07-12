//
//  Theme.swift
//  AudioPlayer_test
//
//  Design tokens + shared visual building blocks.
//

import SwiftUI

// MARK: - Color helpers

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum Theme {
    static let background = Color(hex: 0x08080C)
    static let surface = Color(hex: 0x15151F)
    static let surfaceElevated = Color(hex: 0x1E1E2A)
    static let accent = Color(hex: 0x7C5CFF)
    static let accentSoft = Color(hex: 0xB9A8FF)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)
}

// MARK: - Aurora animated background

/// A softly-drifting, blurred multi-blob gradient that colours whole
/// scenes based on the current track's palette.
struct AuroraBackground: View {
    let colors: [Color]
    var animated: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    Theme.background
                    blob(colors.first ?? Theme.accent,
                         x: 0.30 + 0.16 * sin(t * 0.20),
                         y: 0.26 + 0.12 * cos(t * 0.23),
                         size: 1.15, w: w, h: h)
                    blob(colors.last ?? Theme.accentSoft,
                         x: 0.72 + 0.14 * cos(t * 0.17),
                         y: 0.40 + 0.14 * sin(t * 0.19),
                         size: 1.0, w: w, h: h)
                    blob((colors.last ?? Theme.accent).opacity(0.9),
                         x: 0.48 + 0.18 * sin(t * 0.13 + 1.5),
                         y: 0.82 + 0.10 * cos(t * 0.15),
                         size: 1.25, w: w, h: h)
                }
                .blur(radius: 70)
                .overlay(Theme.background.opacity(0.28))
            }
            .ignoresSafeArea()
        }
    }

    private func blob(_ color: Color, x: Double, y: Double, size: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        let dimension = max(w, h) * size
        return Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.85), color.opacity(0.0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: dimension / 2
                )
            )
            .frame(width: dimension, height: dimension)
            .position(x: w * x, y: h * y)
    }
}

// MARK: - Glass surface

struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 20
    var strokeOpacity: Double = 0.12

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(strokeOpacity), lineWidth: 1)
            )
    }
}

extension View {
    func glass(cornerRadius: CGFloat = 20, strokeOpacity: Double = 0.12) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, strokeOpacity: strokeOpacity))
    }
}

// MARK: - Time formatting

extension Double {
    /// Formats a duration in seconds as `m:ss`.
    var asClock: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
