//
//  PenTextMeasurer+FaceAvailability.swift
//  Woodcase
//

import CoreText
import Foundation

/// Whether Core Text has a real face for a (family, weight, style), not merely the family.
///
/// ``fontFamilyAvailable(_:)`` answers for a family, and a family with only its regular
/// file registered answers yes — then draws bold and italic in that one file. The font
/// resolver needs the finer question: is there a registered font of the family in this
/// style whose weight is this one?
extension PenTextMeasurer {
    /// The faces among `faces` Core Text has a font for: one of the family's fonts in the
    /// face's style whose weight is the face's — a variable font whose `wght` axis spans
    /// it, or a static font whose OS/2 weight class equals it.
    ///
    /// A face the family lacks by design (a 900 in a family that stops at 700) is not
    /// available, even though Core Text would draw the nearest one; the caller decides
    /// whether anything better exists.
    ///
    /// Gated by ``FontRegistryGate``: every call here is a round trip to `fontd`.
    ///
    /// - Parameter faces: The faces to look for, of any families.
    /// - Returns: The subset Core Text has a font for.
    static func availableFaces(_ faces: Set<PenFontFace>) -> Set<PenFontFace> {
        var available: Set<PenFontFace> = []
        for (family, familyFaces) in Dictionary(grouping: faces, by: \.family) {
            let fonts = registeredFaces(of: family)
            for face in familyFaces where fonts.contains(where: { $0.covers(face) }) {
                available.insert(face)
            }
        }
        return available
    }

    /// One registered font of a family: its style and the weights it draws.
    private struct RegisteredFace {
        let italic: Bool
        let weights: ClosedRange<Int>

        func covers(_ face: PenFontFace) -> Bool {
            italic == (face.style == .italic) && weights.contains(face.weight)
        }
    }

    /// Every font Core Text holds for exactly `family`.
    private static func registeredFaces(of family: String) -> [RegisteredFace] {
        FontRegistryGate.withAccess {
            let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family] as CFDictionary)
            let matches = (CTFontDescriptorCreateMatchingFontDescriptors(descriptor, nil) as? [CTFontDescriptor]) ?? []
            return matches.compactMap { match in
                let font = CTFontCreateWithFontDescriptor(match, 12, nil)
                guard (CTFontCopyFamilyName(font) as String).lowercased() == family.lowercased() else { return nil }
                let italic = CTFontGetSymbolicTraits(font).contains(.traitItalic)
                return RegisteredFace(italic: italic, weights: weights(of: font))
            }
        }
    }

    /// The weights a font draws: its `wght` axis's range, or its OS/2 weight class.
    private static func weights(of font: CTFont) -> ClosedRange<Int> {
        let axes = (CTFontCopyVariationAxes(font) as? [[CFString: Any]]) ?? []
        if let axis = axes.first(where: { ($0[kCTFontVariationAxisIdentifierKey] as? Int) == wghtAxisTag }),
           let minimum = (axis[kCTFontVariationAxisMinimumValueKey] as? NSNumber)?.doubleValue,
           let maximum = (axis[kCTFontVariationAxisMaximumValueKey] as? NSNumber)?.doubleValue,
           minimum <= maximum
        {
            return Int(minimum.rounded(.down)) ... Int(maximum.rounded(.up))
        }
        let weight = weightClass(of: font) ?? 400
        return weight ... weight
    }

    /// The font's OS/2 `usWeightClass` — the CSS weight its maker gave it — or `nil`
    /// when the table is missing or says 0.
    private static func weightClass(of font: CTFont) -> Int? {
        let tag = CTFontTableTag(kCTFontTableOS2)
        guard let table = CTFontCopyTable(font, tag, []) as Data?, table.count >= 6 else { return nil }
        let value = Int(table[table.startIndex + 4]) << 8 | Int(table[table.startIndex + 5])
        return value == 0 ? nil : value
    }
}
