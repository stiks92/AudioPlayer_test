//
//  FilterChipRow.swift
//  Sonava
//
//  One filter row for the whole app.
//
//  Radio and Podcasts had the same control built twice — chips 2pt apart in
//  gutter, one firing a haptic and the other silent, neither animating the
//  selection. A review put it well: differing only by 2pt and whether it
//  buzzes is worse than a deliberate difference, because it reads as neglect
//  rather than intent.
//
//  Selection is the accent, not white. Tint is semantic and reserved for the
//  choice the user has made, and it also means the paid accent palette
//  actually reaches the browsing screens, where it was previously invisible.
//

import SwiftUI

struct FilterChipRow<Value: Hashable>: View {
    let chips: [FilterChip<Value>]
    @Binding var selection: Value
    var onSelect: ((Value) -> Void)? = nil

    @Namespace private var indicator

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(chips) { chip in
                    chipView(chip)
                }
            }
        }
        .carouselBleed()
    }

    private func chipView(_ chip: FilterChip<Value>) -> some View {
        let isSelected = selection == chip.value
        return Button {
            guard !isSelected else { return }
            withAnimation(Motion.standard) { selection = chip.value }
            Haptics.selection()
            onSelect?(chip.value)
        } label: {
            Text(chip.title)
                .font(.sonavaRowMeta.weight(.semibold))
                .foregroundColor(isSelected ? .white : Theme.textSecondary)
                .padding(.horizontal, Space.l)
                // Height rather than vertical padding, so the target is 44pt
                // whatever the reader's text size does to the label.
                .frame(minHeight: Space.hitTarget)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Theme.accent.mix(with: Theme.background, by: 0.12))
                            .matchedGeometryEffect(id: "filterChip", in: indicator)
                    } else {
                        Capsule().fill(Color.white.opacity(0.08))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
