//
//  PenPostIt+Tint.swift
//  Woodcase
//

import Foundation

public extension PenPostIt {
    /// The tint presets a post-it offers: Post-it yellow, then the six of Penumbra's spec
    /// §10 (pink, orange, green, blue, purple and gray).
    ///
    /// A preset is written to `woodcase.tint` as its hex (``color``), like any custom
    /// color, so the file holds no names and a renderer needs no table. All seven are light
    /// enough to take black ink (``Ink``).
    enum Tint: String, Friendly, CaseIterable {
        /// Post-it yellow: a note with no tint.
        case yellow
        /// Pink.
        case pink
        /// Orange.
        case orange
        /// Green.
        case green
        /// Blue.
        case blue
        /// Purple.
        case purple
        /// Gray.
        case gray

        /// The tint a note without `woodcase.tint`, or with a malformed one, draws in.
        public static let `default` = Tint.yellow

        /// The preset's color, as it is written to `woodcase.tint`.
        public var color: PenHexColor {
            switch self {
            case .yellow: PenHexColor(red: 0xFF, green: 0xF5, blue: 0x9D)
            case .pink: PenHexColor(red: 0xF8, green: 0xBB, blue: 0xD0)
            case .orange: PenHexColor(red: 0xFF, green: 0xCC, blue: 0x80)
            case .green: PenHexColor(red: 0xC5, green: 0xE1, blue: 0xA5)
            case .blue: PenHexColor(red: 0xB3, green: 0xE5, blue: 0xFC)
            case .purple: PenHexColor(red: 0xD1, green: 0xC4, blue: 0xE9)
            case .gray: PenHexColor(red: 0xCF, green: 0xD8, blue: 0xDC)
            }
        }
    }
}
