//
//  PenTextMeasurer+SystemFont.swift
//  Woodcase
//

import CoreText
import Foundation

/// Where a requested family is drawn from: itself, the default family, or the system font
/// standing in for the default family.
///
/// ``PenTextStyle/defaultFontFamily`` is "SF Pro", which is a family only where Apple's
/// developer SF Pro is installed. Elsewhere — a stock Mac, every iPhone — the system font
/// is the hidden `.SF NS` family, Core Text answers "SF Pro" with Helvetica, and the
/// family can't be named: it is reached only as the UI font. So "SF Pro" draws as the
/// system font wherever the family is missing, the same design on every Mac.
extension PenTextMeasurer {
    /// Where Core Text draws a family from.
    enum FamilySource: Friendly {
        /// A family Core Text has, by name.
        case family(String)

        /// The system UI font, standing in for ``PenTextStyle/defaultFontFamily`` where
        /// that family is not installed.
        case systemFont
    }

    /// Where `family` is drawn from: itself when it is installed, else the default
    /// family when that is, else the system font.
    ///
    /// - Parameters:
    ///   - family: The requested family.
    ///   - isAvailable: Whether Core Text has a family; ``fontFamilyAvailable(_:)`` in
    ///     production, and a test's own answer so it doesn't depend on the machine.
    /// - Returns: The source to draw from.
    static func familySource(
        for family: String,
        isAvailable: (String) -> Bool = fontFamilyAvailable
    ) -> FamilySource {
        if isAvailable(family) { return .family(family) }
        if family != defaultFontFamily, isAvailable(defaultFontFamily) { return .family(defaultFontFamily) }
        return .systemFont
    }

    /// The font a source names at `size`, before any weight or slant is applied.
    ///
    /// - Parameters:
    ///   - source: Where to draw from.
    ///   - size: The point size.
    ///   - attributes: Further descriptor attributes, such as optical sizing.
    /// - Returns: The family's font, or the system UI font.
    static func baseFont(of source: FamilySource, size: Double, attributes: [CFString: Any]) -> CTFont {
        switch source {
        case let .family(family):
            let descriptor = CTFontDescriptorCreateWithAttributes(
                attributes.merging([kCTFontFamilyNameAttribute: family]) { $1 } as CFDictionary
            )
            return CTFontCreateWithFontDescriptor(descriptor, size, nil)
        case .systemFont:
            let system = CTFontCreateUIFontForLanguage(.system, size, nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
            guard !attributes.isEmpty else { return system }
            return CTFontCreateCopyWithAttributes(
                system, size, nil, CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
            )
        }
    }
}
