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
//  ## Why it scrolls instead of squeezing
//
//  It used to divide the width equally and let each label shrink to fit its
//  share. With six Russian segments that produced a row where «Песни» sat at
//  full size and «Плейлисты» at 72% of it — different type sizes in one
//  control, which reads as broken because it is. A segment now takes the
//  width its own word needs, at one size, and the row scrolls when the words
//  do not fit. Nothing is ever truncated, nothing is ever shrunk, and the
//  selected segment scrolls itself into view.
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
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Space.xs) {
                    ForEach(segments) { segment in
                        segmentView(segment).id(segment.value)
                    }
                }
                .padding(Space.xs)
            }
            // Only scrolls when it has to: a three-segment control still sits
            // still under a finger, which is what makes the scrolling one feel
            // like the same component rather than a different one.
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .scrollIndicators(.hidden)
            .background(Capsule().fill(Theme.surfaceElevated))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .clipShape(Capsule())
            // A selection changed from elsewhere — a deep link, a restored
            // state — must not leave its pill off-screen.
            .onChange(of: selection) { _, value in
                withAnimation(Motion.standard) { proxy.scrollTo(value, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
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
                    SonavaIcon(glyph: .lock, size: 11, tint: .white.opacity(0.85))
                }
            }
            .font(.sonavaRowMeta.weight(.semibold))
                // One line, one size, always. The label decides the width;
                // the control decides whether the row scrolls.
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(isSelected ? .white : Theme.textSecondary)
            .padding(.horizontal, Space.l)
            .frame(minHeight: Space.hitTarget - Space.s)
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
