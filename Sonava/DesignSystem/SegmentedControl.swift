//
//  SegmentedControl.swift
//  Sonava
//
//  One segmented control for the app.
//
//  Library and Stats each built their own: a solid white pill with a black
//  label in one, an accent capsule with a white label in the other. Same
//  component, adjacent screens, nothing shared — and Library's white pill made
//  a *filter* the brightest object on a screen whose primary action was also a
//  white capsule, so the eye could not tell which one mattered.
//
//  Selection is the accent here for the same reason it is on the filter chips:
//  tint belongs to the choice the user made, and it is the only way the paid
//  accent palette reaches these screens at all.
//

import SwiftUI

struct SegmentedControl<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        let title: LocalizedStringKey
        /// Shown as a lock when the segment needs Pro.
        var isLocked = false
        /// Automation identifier. Segments are found by id rather than by
        /// label so the tests hold in any language.
        var identifier: String? = nil

        var id: Value { value }
    }

    let segments: [Segment]
    @Binding var selection: Value
    /// Called instead of selecting when a locked segment is tapped.
    var onLocked: (() -> Void)? = nil

    @Namespace private var indicator

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(segments) { segment in
                segmentView(segment)
            }
        }
        .padding(Space.xs)
        .background(Capsule().fill(Theme.surfaceElevated))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func segmentView(_ segment: Segment) -> some View {
        let isSelected = selection == segment.value
        return Button {
            if segment.isLocked {
                onLocked?()
            } else if !isSelected {
                withAnimation(Motion.standard) { selection = segment.value }
                Haptics.selection()
            }
        } label: {
            HStack(spacing: Space.xs) {
                Text(segment.title)
                if segment.isLocked {
                    Image(systemName: "lock.fill").font(.system(.caption2).weight(.bold))
                }
            }
            .font(.sonavaRowMeta.weight(.semibold))
                // Russian labels — "Плейлисты", "Избранное" — hyphenated into
                // two lines inside the pill. A segment shrinks, never wraps.
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            .foregroundColor(isSelected ? .white : Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: Space.hitTarget - Space.s)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Theme.accent.mix(with: Theme.background, by: 0.12))
                        .matchedGeometryEffect(id: "segment", in: indicator)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(segment.identifier ?? "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
