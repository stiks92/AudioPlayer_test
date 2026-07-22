//
//  FilterChip.swift
//  Sonava
//
//  A selectable filter shown as a chip: what the user reads and what the
//  backing service is actually queried with are deliberately separate.
//  Catalogue APIs expect English tags, but the label has to translate.
//

import SwiftUI

struct FilterChip<Value: Hashable>: Identifiable, Hashable {
    /// The translated label shown in the chip.
    let title: LocalizedStringKey
    /// The value handed to the service — never localized.
    let value: Value

    var id: Value { value }

    init(_ title: LocalizedStringKey, _ value: Value) {
        self.title = title
        self.value = value
    }

    // Identity is the query value: two chips that search for the same thing are
    // the same chip, whatever the display language happens to render.
    // (`LocalizedStringKey` is not `Hashable`, so this cannot be synthesised.)
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }
    func hash(into hasher: inout Hasher) { hasher.combine(value) }
}

extension FilterChip where Value == String {
    /// For catalogues whose query term doubles as the English label.
    init(_ term: String) {
        self.init(LocalizedStringKey(term), term)
    }
}
