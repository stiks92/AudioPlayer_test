//
//  Editorial.swift
//  Sonava
//
//  The parts a page is built from when it is not built from cards.
//
//  Three independent design reviews, briefed separately, reached the same
//  verdict about the old Home: nine stacked sections, six of them the identical
//  "section header + horizontal rail of rounded tiles", with two gradient cards
//  on top. Nothing said which part mattered, because every part was built the
//  same way. Recolouring inside that skeleton is what made every round of
//  polish invisible.
//
//  So: rules, rails and scale instead of containers.
//
//  - A **department** is a 1pt rule with a tracked, uppercase label sitting on
//    it, and the section's own count in the margin. It replaces a 20pt bold
//    rounded title and removes every "See all" button in the app.
//  - The **left rail** is absolute. Text starts at the screen margin, or at
//    `Rail.text` when the row is ranked and a numeral hangs outside the
//    measure — the way a contents page sets its folios.
//  - The **marginal column** is right-aligned to the trailing margin and holds
//    one fact, or nothing. The empty right column is the design.
//

import SwiftUI

// MARK: - Department

/// A section label sitting on its own rule, with a fact in the margin.
///
/// The whole label is the tap target when a section has somewhere to go, which
/// is why there is no "See all": a separate button implies the heading is not
/// itself a way in.
struct Department: View {
    let title: LocalizedStringKey
    /// The count, address or state that belongs to this section. Set in the
    /// machine voice, because it is always something measured.
    var fact: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Rectangle()
                .fill(Theme.accent.opacity(0.55))
                .frame(height: Rule.section)
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.sonavaDepartment)
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundColor(Theme.textPrimary.opacity(0.85))
                    // Cyrillic set in tracked caps runs much wider than Latin —
                    // "RECENTLY PLAYED" against "НЕДАВНО ПРОСЛУШАННОЕ" — so the
                    // label shrinks rather than wrapping under its own rule.
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: Space.m)
                if let fact {
                    Text(fact)
                        .font(.sonavaStamp)
                        .tracking(1.2)
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { action?() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(action == nil ? [] : .isButton)
    }
}

// MARK: - Rows

/// A ranked row: the numeral hangs outside the measure, and the sleeve sits
/// beside it.
///
/// The first version of this row had no artwork, on the theory that "borrowed
/// music is text". The owner overruled it in plain words — why are there no
/// covers — and they were right: in a music app the sleeve is not decoration,
/// it is how people recognise music they cannot yet name. The rank makes it a
/// chart; the cover makes it music.
struct RankedRow: View {
    let rank: Int
    let song: Song
    /// One fact for the margin, or nothing.
    var fact: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: Space.m) {
            Text(String(format: "%02d", rank))
                .font(.sonavaOrdinal)
                .foregroundColor(Theme.textTertiary)
                .frame(width: Rail.ordinal, alignment: .trailing)
            ArtworkImage(song: song, glyphSize: 16)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.sonavaName)
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.sonavaByline)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s)
            if let fact {
                Text(fact)
                    .font(.sonavaStamp)
                    .tracking(1.2)
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .frame(minHeight: Space.hitTarget + 12)
        .contentShape(Rectangle())
    }
}

/// A row for music the listener owns: artwork, and in the margin whatever the
/// app truthfully knows about the file.
struct OwnedRow: View {
    let song: Song
    var fact: String? = nil

    var body: some View {
        HStack(spacing: Space.l) {
            ArtworkImage(song: song, glyphSize: 14)
                .frame(width: 40, height: 40)
                // 2pt, not 20. A sleeve has an edge, not a soft corner.
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.sonavaName)
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.sonavaByline)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s)
            if let fact {
                Text(fact)
                    .font(.sonavaStamp)
                    .tracking(1.2)
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .frame(minHeight: Space.hitTarget + 12)
        .contentShape(Rectangle())
    }
}

/// The hairline between rows, inset to the text rail rather than the margin, so
/// a ranked list's numerals hang free of it.
struct RowRule: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(height: Theme.hairlineWidth)
            .padding(.leading, inset)
    }
}
