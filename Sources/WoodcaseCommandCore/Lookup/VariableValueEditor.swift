//
//  VariableValueEditor.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// Works out what a variable's value becomes after one `vars set`.
///
/// The .pen format holds a variable's value two ways — one value, or a list of
/// `{value, theme?}` variants of which the resolver takes the last that matches the
/// active theme, falling back to the one with no `theme` at all. Merging a new value
/// into that has to preserve two things: the variants nobody asked about, and their
/// order, because order is what "last match wins" is about.
///
/// | `--theme` | existing value | result |
/// |---|---|---|
/// | absent | none, or one value | that one value, replaced |
/// | absent | variants | the default variant (no `theme`) replaced, or appended |
/// | given | none | one variant, pinned |
/// | given | one value | the old value as the **default**, then the pinned one |
/// | given | variants | the variant with that exact pin replaced, or appended |
///
/// The fourth row is the one that matters: promoting the old value to the default is
/// what keeps every reference that already resolved to it resolving to it, under every
/// theme the new pin does not name.
enum VariableValueEditor {
    /// The value a variable holds after a `set`.
    ///
    /// - Parameters:
    ///   - existing: The value the variable holds now, or `nil` for a new variable.
    ///   - value: The value being set.
    ///   - pin: The `--theme` axes and options this value is for. Empty for the
    ///     default.
    /// - Returns: The merged value.
    static func merged(
        existing: PenVariableValue?,
        setting value: AnyCodable,
        pinnedTo pin: [String: String]
    ) -> PenVariableValue {
        guard !pin.isEmpty else { return merged(existing: existing, settingDefault: value) }
        switch existing {
        case .none:
            return .themed([PenThemedValue(value: value, theme: pin)])
        case let .simple(old):
            return .themed([
                PenThemedValue(value: old, theme: nil),
                PenThemedValue(value: value, theme: pin),
            ])
        case var .themed(variants):
            if let index = variants.firstIndex(where: { $0.theme == pin }) {
                variants[index] = PenThemedValue(value: value, theme: pin)
            } else {
                variants.append(PenThemedValue(value: value, theme: pin))
            }
            return .themed(variants)
        }
    }

    /// The value a variable holds after a `set` with no `--theme`.
    ///
    /// - Parameters:
    ///   - existing: The value the variable holds now.
    ///   - value: The value being set.
    /// - Returns: The merged value.
    private static func merged(
        existing: PenVariableValue?,
        settingDefault value: AnyCodable
    ) -> PenVariableValue {
        guard case var .themed(variants) = existing else { return .simple(value) }
        if let index = variants.firstIndex(where: { $0.theme == nil }) {
            variants[index] = PenThemedValue(value: value, theme: nil)
        } else {
            variants.append(PenThemedValue(value: value, theme: nil))
        }
        return .themed(variants)
    }
}
