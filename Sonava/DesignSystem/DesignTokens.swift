//
//  DesignTokens.swift
//  Sonava
//
//  The scales every screen measures itself against: space, radius, motion and
//  type. Before these existed the app had thirteen distinct corner radii and
//  spacing that drifted off the 4pt grid in a dozen places, because each call
//  site invented its own values.
//
//  The rule is the same as for colour in `Theme`: name the role, never the
//  number.
//

import SwiftUI

// MARK: - Space

/// Everything is a multiple of 4. If a layout wants 14 or 18, it wants 16.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    /// The margin every screen's content starts at. One value, app-wide —
    /// edge discipline is the cheapest signal of craft and the most expensive
    /// to retrofit.
    static let screenMargin: CGFloat = 20

    /// Width of the leading icon column in a row. Fixed in both dimensions so
    /// row height stops depending on which SF Symbol happens to be there.
    static let iconColumn: CGFloat = 24

    /// Gap between the icon column and a row's text.
    static let iconGap: CGFloat = 14

    /// Where row text begins, measured from the row's own leading edge.
    /// Separators inset to this so they start at the text, not under the icon.
    static var textRail: CGFloat { iconColumn + iconGap }

    /// Apple's minimum touch target. Controls smaller than this get a
    /// transparent frame of this size around them.
    static let hitTarget: CGFloat = 44
}

// MARK: - Radius

enum Radius {
    static let control: CGFloat = 12
    static let card: CGFloat = 20
    static let hero: CGFloat = 28

    /// Concentric nesting: something inset by `inset` inside a `outer`-radius
    /// container needs this radius, or the corners visibly disagree.
    static func inner(_ outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(4, outer - inset)
    }
}

// MARK: - Motion

/// One vocabulary of movement. The app previously had nine distinct spring
/// definitions and five different curves inside a single four-slide tour.
enum Motion {
    /// Button presses and other momentary feedback.
    static let press = Animation.spring(response: 0.28, dampingFraction: 0.70)
    /// The default for state changes: selections, reveals, layout shifts.
    static let standard = Animation.spring(response: 0.35, dampingFraction: 0.82)
    /// Deliberately showy — reserved for moments that should feel like events.
    static let expressive = Animation.spring(response: 0.45, dampingFraction: 0.80)
    /// Crossfades and opacity-only changes, where a spring would look wrong.
    static let fade = Animation.easeInOut(duration: 0.25)
}

// MARK: - Type

/// A seven-role ramp built on text styles, so every size responds to the
/// reader's Dynamic Type setting. `Font.system(size:)` does not scale at all,
/// which is why it no longer appears in the app.
extension Font {
    /// Screen titles.
    static let sonavaDisplay = Font.system(.largeTitle, design: .rounded).weight(.heavy)
    /// The big number on a stat: durations, counts, streaks.
    static let sonavaMetric = Font.system(.title, design: .rounded).weight(.heavy)
    /// The title of a card or a sheet section.
    static let sonavaCardTitle = Font.system(.headline, design: .rounded).weight(.bold)
    /// Supporting copy under a card title.
    static let sonavaCardSubtitle = Font.system(.subheadline)
    /// A list row's primary line.
    static let sonavaRowTitle = Font.system(.subheadline).weight(.medium)
    /// A row's secondary line, values and metadata.
    static let sonavaRowMeta = Font.system(.footnote)
    /// The small uppercase label above a group.
    static let sonavaSectionLabel = Font.system(.caption).weight(.bold)
}

extension View {
    /// The uppercase, tracked group label used above every section.
    func sectionLabelStyle() -> some View {
        self.font(.sonavaSectionLabel)
            .textCase(.uppercase)
            .tracking(1)
            .foregroundColor(Theme.textTertiary)
    }

    /// Guarantees a control is at least 44×44pt without changing how it looks.
    func hitTarget(_ size: CGFloat = Space.hitTarget) -> some View {
        frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }
}
