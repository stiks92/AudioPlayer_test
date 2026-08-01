//
//  Theme.swift
//  Sonava
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

/// Deterministic *fallback* pairs for tracks whose sleeve has not been read
/// yet — the real colour of the app comes from the artwork's own pixels (see
/// `ArtworkPalette`), and these only cover the moment before it loads or the
/// track that has no art. Stored as hex so tracks stay `Codable` (see `Song`).
///
/// Muted, sleeve-like duos on purpose. The previous seventeen were stock neon
/// gradients — half of them violet — and because they were assigned by title
/// hash, they were the dominant colour story of the whole app: template light
/// over real covers. A fallback should look like a record that hasn't been
/// pulled from its shelf yet, not like a brand.
enum Palette {
    static let gradientsHex: [[UInt]] = [
        [0xC9A227, 0x5A3E1B], [0xB4552D, 0x3C1F14], [0x2E6E5E, 0x122A24],
        [0x3E6E9E, 0x14263C], [0xA63A3A, 0x2E1010], [0xC77B4A, 0x4A2C18],
        [0x5E8272, 0x1E2C26], [0x4A7E8C, 0x142E36], [0xB89B5E, 0x40351C],
        [0x8C4A2E, 0x2E140A], [0x6E7E8C, 0x222A32], [0x3E8C6E, 0x102E22]
    ]

    static func hex(for index: Int) -> [UInt] {
        gradientsHex[abs(index) % gradientsHex.count]
    }

    /// Stable seed for a string so a track keeps its colour across launches.
    static func hex(forSeed string: String) -> [UInt] {
        let seed = string.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return hex(for: seed)
    }
}

extension Array where Element == UInt {
    /// Convert stored hex stops into SwiftUI colours.
    var colors: [Color] { map { Color(hex: $0) } }
}

/// Semantic design tokens. Views name the *role* of a colour, never its hex —
/// so a palette change happens here and nowhere else. Decorative per-track
/// gradients live in `Palette` instead, because they carry no meaning.
enum Theme {

    // MARK: Surfaces
    static let background = Color(hex: 0x08080C)
    static let surface = Color(hex: 0x15151F)
    static let surfaceElevated = Color(hex: 0x1E1E2A)

    // MARK: Brand — driven by the selected palette (see ThemePalette)
    @MainActor static var accent: Color { Color(hex: ThemeManager.shared.palette.accent) }
    @MainActor static var accentSoft: Color { Color(hex: ThemeManager.shared.palette.accentSoft) }
    @MainActor static var accentDeep: Color { Color(hex: ThemeManager.shared.palette.accentDeep) }
    @MainActor static var accentWarm: Color { Color(hex: ThemeManager.shared.palette.accentWarm) }

    /// The two-stop brand gradient for surfaces that sit *behind* content.
    ///
    /// Never use this on text: `accentDeep` measures 2.25:1 against the app
    /// background, so any leading→trailing run of it dissolves the end of the
    /// word. Foreground text wants `brandGradientOnDark`.
    @MainActor static var brandGradient: LinearGradient {
        LinearGradient(colors: [accent, accentDeep], startPoint: .leading, endPoint: .trailing)
    }

    /// The brand gradient for *foreground* use on a dark ground. Both stops
    /// clear 4.5:1, so a headline stays legible end to end.
    @MainActor static var brandGradientOnDark: LinearGradient {
        LinearGradient(colors: [accentSoft, accent], startPoint: .leading, endPoint: .trailing)
    }

    /// The richer three-stop gradient reserved for the paywall and Pro upsells.
    @MainActor static var proGradient: LinearGradient {
        LinearGradient(colors: [accent, accentWarm, accentDeep],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Semantic state
    /// Success / connected.
    static let positive = Color(hex: 0x38EF7D)
    /// Favourites and destructive actions.
    static let destructive = Color(hex: 0xFF3B6B)
    /// Inline error copy — softer than `destructive` so it reads as text.
    static let error = Color(hex: 0xFF6B8A)
    /// Live radio indicator. Deliberately *not* `destructive`: they shared a
    /// hex, so one colour meant "live", "favourite" and "delete" at once, and
    /// therefore meant none of them.
    static let live = Color(hex: 0xFF9F0A)
    /// Something the user owns is degraded but not broken — a saved server that
    /// isn't answering. Separate from `live` for exactly the reason recorded
    /// above: `live` had started doing this job as well, and a token that means
    /// "broadcasting now" and "not responding" at the same time means neither.
    /// Separate from `error` too, because an unreachable box is a fact about
    /// the house, not a fault in the app.
    static let warning = Color(hex: 0xFFB340)

    // MARK: Text
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    /// The dimmest colour any *text* may use. 0.38 was the previous value and
    /// measured ~3.5:1 everywhere it appeared — below the 4.5:1 body-text floor
    /// in a dozen places, including section headers and chart axis labels.
    static let textTertiary = Color.white.opacity(0.55)

    // MARK: Lines
    /// Separators and borders. Not for text — a line has no contrast floor to
    /// meet, and the old 0.38 text colour was doing double duty as both.
    static let hairline = Color.white.opacity(0.10)
    /// The thickness a 1-pixel rule should actually be. `frame(height: 1)` on a
    /// @3x display draws three device pixels.
    @MainActor static var hairlineWidth: CGFloat { 1 / UIScreen.main.scale }
}

// MARK: - Aurora animated background

/// A softly-drifting, blurred multi-blob gradient that colours whole
/// scenes based on the current track's palette.
struct AuroraBackground: View {
    let colors: [Color]
    var animated: Bool = true

    /// A permanently drifting full-screen gradient is exactly what this setting
    /// exists to stop, so it freezes on a single frame instead.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isMoving: Bool { animated && !reduceMotion }

    /// The middle stop of a three-colour gradient. The previous version read
    /// only `first` and `last`, so `Theme.proGradient`'s third colour never
    /// reached a pixel and the paywall rendered identically to the slide before
    /// it — a documented "richer" gradient that was a no-op.
    private var midColor: Color {
        colors.count > 2 ? colors[1] : (colors.last ?? Theme.accentSoft)
    }

    var body: some View {
        // 30fps rather than 20: on a 120Hz panel the old interval was visible
        // as judder on something whose whole job is to drift smoothly.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isMoving)) { timeline in
            let t = isMoving ? timeline.date.timeIntervalSinceReferenceDate : 0
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    Theme.background
                    blob(colors.first ?? Theme.accent,
                         x: 0.30 + 0.16 * sin(t * 0.20),
                         y: 0.26 + 0.12 * cos(t * 0.23),
                         size: 1.15, w: w, h: h)
                    blob(midColor,
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

/// An opaque content surface.
///
/// Content is deliberately *not* glass. Apple reserves Liquid Glass for the
/// floating navigation layer — bars, toolbars, floating controls — and states
/// plainly that it must never be applied to lists, media or scrollable content.
/// Every card in this app used to be `.ultraThinMaterial`, which over an opaque
/// page had nothing to refract and simply composited to flat grey anyway.
struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = Radius.card

    func body(content: Content) -> some View {
        content
            .background(Theme.surfaceElevated,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    /// A content surface: cards, grouped rows, panels.
    func card(cornerRadius: CGFloat = Radius.card) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }

    /// Real Liquid Glass, for the floating navigation layer only.
    ///
    /// iOS 26 supplies the material; below that we keep the old frosted
    /// approximation, which is the closest the platform can get. The deployment
    /// target is 18.0, so the fallback is required rather than optional.
    @ViewBuilder
    func floatingGlass(cornerRadius: CGFloat = Radius.control) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
        } else {
            background(.ultraThinMaterial,
                       in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
        }
    }

    /// Liquid Glass for a control that responds to touch — it scales, shimmers
    /// and lights up under the finger on iOS 26.
    @ViewBuilder
    func interactiveGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
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
