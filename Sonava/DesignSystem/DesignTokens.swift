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

// MARK: - Artwork tiles

/// Two tile sizes for the horizontal rails, and only two.
///
/// Home had three — 130, 150 and 160 — with identical gutters and identical
/// margins, so the difference read as a mistake rather than as a hierarchy.
/// Worse, the smallest belonged to "Made for you": the rail that carries the
/// app's personalisation promise was drawn smaller than "Popular now".
enum Tile {
    /// The rails that lead a screen and carry a promise: what the app picked
    /// for this listener, and the curated playlists.
    static let feature: CGFloat = 160
    /// Every other rail.
    static let standard: CGFloat = 140
}

/// The accent and app-icon pickers, sized so six fit a settings card's inner
/// width with a real gutter. They were 52 and 56, which did not, and the row
/// spent three rounds being sliced by the card's own border instead.
enum Swatch {
    static let size: CGFloat = 46
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

/// Three families, one rule each, so the ramp can be checked in a sentence:
/// **if a human named it, it is serif; if a machine measured it, it is
/// monospaced; everything else is the system face.**
///
/// The previous ramp put `design: .rounded` on the display, metric, card-title
/// and section-header roles. Two independent design reviews named it, without
/// prompting, as the single loudest signal that a screen was generated rather
/// than designed — SF Rounded is the friendliness default of every template.
/// It appears in exactly zero roles now.
///
/// Serif is New York, which the system ships and which optically sizes itself.
/// It carries names — track titles, artists, the app's own word — because a
/// name is written by a person. Monospaced carries facts, and the reason is
/// mechanical as well as editorial: a tabular numeral does not twitch when the
/// value under it changes thirty times a second.
///
/// Every role is anchored to a text style, never `Font.system(size:)`, so it
/// still answers Dynamic Type.
extension Font {
    /// The app's own word, and nothing else. Once per screen at most.
    static let sonavaMasthead = Font.system(.largeTitle, design: .serif).weight(.black)
    /// The one hero figure on a screen: a duration, a count, a streak.
    static let sonavaFigure = Font.system(.largeTitle, design: .serif).weight(.black)
    /// A title someone chose: a track, an album, a playlist.
    static let sonavaTitle = Font.system(.title, design: .serif).weight(.bold)
    /// A row's primary line — the name of the thing.
    static let sonavaName = Font.system(.callout, design: .serif).weight(.semibold)
    /// An attribution: the artist, set the way a credit is set.
    static let sonavaAttribution = Font.system(.body, design: .serif).italic()
    /// A row's secondary line.
    static let sonavaByline = Font.system(.footnote)
    /// The department label above a rule. Set in caps and tracked.
    static let sonavaDepartment = Font.system(.caption2).weight(.heavy)
    /// A measured fact: elapsed time, latency, a count, a format, an address.
    static let sonavaFact = Font.system(.footnote, design: .monospaced)
        .weight(.medium).monospacedDigit()
    /// The smallest machine voice: stamps, datelines, badges, units.
    static let sonavaStamp = Font.system(.caption2, design: .monospaced).weight(.medium)
    /// A rank. Hangs outside the text rail, the way a folio does.
    static let sonavaOrdinal = Font.system(.subheadline, design: .monospaced)
        .weight(.semibold).monospacedDigit()

    // Retained so the app keeps building while screens migrate one at a time.
    // Each now points at its replacement rather than at a rounded face.
    static let sonavaDisplay = sonavaMasthead
    static let sonavaMetric = sonavaFigure
    static let sonavaCardTitle = Font.system(.headline).weight(.semibold)
    static let sonavaCardSubtitle = Font.system(.subheadline)
    static let sonavaRowTitle = Font.system(.subheadline).weight(.medium)
    static let sonavaRowMeta = Font.system(.footnote)
    static let sonavaSectionLabel = sonavaDepartment
}

// MARK: - Rails and rules

/// The two vertical lines nothing crosses, and the four weights of rule.
///
/// A page is held together by where things start and stop, not by the boxes
/// they sit in. Home previously had six horizontal rails whose contents each
/// began at a different optical position, because each tile was a different
/// width — so the left edge of the screen was a suggestion.
enum Rail {
    /// Rank numerals hang here, outside the measure.
    static let ordinal: CGFloat = 32
    static let gap: CGFloat = 20
    /// Where text starts in a ranked row.
    static var text: CGFloat { ordinal + gap }
}

enum Rule {
    /// Ends the nameplate. Full bleed, once per screen.
    static let masthead: CGFloat = 2
    /// Above a department label. Drawn in the accent, so choosing a palette
    /// repaints every rule in the app rather than tinting a chevron.
    static let section: CGFloat = 1
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

    /// Lets a horizontal scroller run to the physical screen edges while its
    /// content still starts on the screen margin.
    ///
    /// Applied to a scroller inside a padded column, otherwise the viewport
    /// stops at the margin and guillotines the last card — and its title —
    /// down the middle, which reads as a layout bug rather than as "there is
    /// more this way". Every shipping Apple carousel bleeds.
    /// The trailing edge dissolves rather than being cut.
    ///
    /// The bleed is deliberate — a half-visible card is how a reader knows to
    /// swipe — but a hard vertical cut through a cover, a badge or a word reads
    /// as clipping damage rather than as an invitation. A review found it on
    /// four scrollers at once, worst on the accent swatches, where a circle was
    /// sliced down the middle against the card's own border and its label was
    /// truncated to a single letter.
    ///
    /// Only the trailing side. A leading fade would dim the first card while
    /// the row sits unscrolled at its margin, which is the state it is in most
    /// of the time.
    ///
    /// Pass `fade: nil` for a scroller inside a container that clips — a card,
    /// say — where the mask must not be applied at all.
    ///
    /// Measured, and the measurement corrected a wrong guess. With a mask on,
    /// the sixth accent swatch vanished while the five before it stayed at
    /// pixel-identical positions, so the layout had not moved. The first guess
    /// was that the gradient was too wide; narrowing it from 28pt to 14
    /// changed nothing, and a plain opaque `Rectangle()` mask erased the swatch
    /// too. So it is applying a mask at all that re-clips the scroller to its
    /// unbled bounds inside a card, which is precisely where the peeking item
    /// lives. Trading a sliced circle for no "there is more" cue is a worse
    /// deal, and that cue is what an earlier round added this bleed to restore.
    @ViewBuilder
    func carouselBleed(_ margin: CGFloat = Space.screenMargin,
                       fade: CGFloat? = 14) -> some View {
        let bled = padding(.horizontal, -margin)
            .contentMargins(.horizontal, margin, for: .scrollContent)
        if let fade {
            bled.mask(alignment: .leading) {
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: fade)
                }
            }
        } else {
            bled
        }
    }

    /// Centres a zero state in the space the screen actually has.
    ///
    /// The four empty states used three different top paddings and sat in the
    /// upper third with the bottom half of the screen empty — a 5:1 imbalance.
    /// `containerRelativeFrame` measures the scroll view rather than guessing.
    func centredEmptyState() -> some View {
        frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center) { height, _ in
                // Leaves room for the title and any control above it, so the
                // block lands optically centred rather than mathematically.
                height * 0.72
            }
    }

    /// Gives content passing under the floating tab bar a solid backdrop.
    ///
    /// The soft default lets saturated artwork read straight through the
    /// glass: with album art scrolled under it the selected tab measured
    /// 1.39:1, and the selected tab is the app's single most important state.
    @ViewBuilder
    func opaqueBottomScrollEdge() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectStyle(.hard, for: .bottom)
        } else {
            self
        }
    }
}
