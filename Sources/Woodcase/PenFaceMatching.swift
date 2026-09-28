//
//  PenFaceMatching.swift
//  Woodcase
//

import CoreText
import Foundation

/// Picks a static family's cut for a CSS weight and slant as CSS font matching does —
/// the rule the browser Pen runs in applies (CSS Fonts 4 §5.2).
///
/// Each cut's weight is its OS/2 weight class, the number a `@font-face` declares, not
/// Core Text's weight trait: the traits differ from family to family (a Medium is 0.2 in
/// IBM Plex Sans and 0.23 in Avenir Next), so a fixed table of them drew Medium as Regular
/// and SemiBold as Medium (`project/2026-09-28-pen-font-faces.md`, finding 1). The emitted
/// SwiftUI carries the same rule in `PenSupport+FaceMatching.swift`.
enum PenFaceMatching {
    /// The weight CSS picks among `available` for `weight`, or `nil` when there is none.
    ///
    /// An exact weight wins. Otherwise, for a weight from 400 to 500, the heavier ones up
    /// to 500 in ascending order, then the lighter ones descending, then those above 500
    /// ascending; below 400, the lighter ones descending, then the heavier ascending;
    /// above 500, the heavier ones ascending, then the lighter descending.
    static func cssMatch(weight: Double, among available: [Double]) -> Double? {
        if available.contains(weight) {
            return weight
        }
        let lighter = available.filter { $0 < weight }.max()
        let heavier = available.filter { $0 > weight }.min()
        if weight >= 400, weight <= 500 {
            if let upTo500 = available.filter({ $0 > weight && $0 <= 500 }).min() {
                return upTo500
            }
            return lighter ?? heavier
        }
        return weight < 400 ? lighter ?? heavier : heavier ?? lighter
    }

    /// The cut of `family` CSS would draw at `weight`, upright or italic, or `nil` when
    /// Core Text knows no face of the family.
    ///
    /// Faces of normal width come first, as CSS matches `font-stretch` before weight, and
    /// faces of the asked-for slant before the others; the caller slants an upright cut
    /// when the family has no italic.
    static func descriptor(family: String, weight: Double, italic: Bool) -> CTFontDescriptor? {
        let request = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family] as CFDictionary)
        let faces = (CTFontDescriptorCreateMatchingFontDescriptors(request, nil) as? [CTFontDescriptor] ?? [])
            .map { Face(descriptor: $0) }
        guard let narrowest = faces.map({ abs($0.width) }).min() else {
            return nil
        }
        let normalWidth = faces.filter { abs($0.width) == narrowest }
        let slanted = normalWidth.filter { $0.italic == italic }
        let candidates = slanted.isEmpty ? normalWidth : slanted
        guard let picked = cssMatch(weight: weight, among: candidates.map(\.weight)) else {
            return nil
        }
        return candidates.first { $0.weight == picked }?.descriptor
    }

    /// One face of a family, as matching reads it.
    private struct Face {
        /// The face.
        let descriptor: CTFontDescriptor
        /// Its CSS weight: the OS/2 weight class, or its weight trait on Core Text's scale
        /// when it has no OS/2 table.
        let weight: Double
        /// Its width trait, 0 for normal.
        let width: Double
        /// Whether it is italic.
        let italic: Bool

        init(descriptor: CTFontDescriptor) {
            self.descriptor = descriptor
            let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [CFString: Any] ?? [:]
            width = traits[kCTFontWidthTrait] as? Double ?? 0
            let symbolic = (traits[kCTFontSymbolicTrait] as? UInt32) ?? 0
            italic = symbolic & CTFontSymbolicTraits.traitItalic.rawValue != 0
            let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
            weight = Self.weightClass(of: font)
                ?? Self.cssWeight(ofTrait: traits[kCTFontWeightTrait] as? Double ?? 0)
        }

        /// The OS/2 table's `usWeightClass`, bytes 4–5, when the font has one.
        private static func weightClass(of font: CTFont) -> Double? {
            guard let table = CTFontCopyTable(font, UInt32(kCTFontTableOS2), []) as Data?,
                  table.count >= 6
            else {
                return nil
            }
            let value = Int(table[table.startIndex + 4]) << 8 | Int(table[table.startIndex + 5])
            return value > 0 ? Double(value) : nil
        }

        /// A weight trait as the CSS weight of the nearest of AppKit's named weights.
        private static func cssWeight(ofTrait trait: Double) -> Double {
            let named: [(trait: Double, css: Double)] = [
                (-0.8, 100), (-0.6, 200), (-0.4, 300), (0, 400), (0.23, 500),
                (0.3, 600), (0.4, 700), (0.56, 800), (0.62, 900),
            ]
            return named.min { abs($0.trait - trait) < abs($1.trait - trait) }?.css ?? 400
        }
    }
}
