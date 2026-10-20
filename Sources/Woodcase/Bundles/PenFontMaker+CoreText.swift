//
//  PenFontMaker+CoreText.swift
//  Woodcase
//

#if canImport(CoreText)
    import CoreText
    import Foundation

    public extension PenFontMaker {
        /// The maker of a font Core Text resolved, from the OS/2 and name tables it copies.
        ///
        /// - Parameter font: The font.
        /// - Returns: `nil` when the font has neither table.
        init?(font: CTFont) {
            self.init(
                os2Table: CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), []) as Data?,
                nameTable: CTFontCopyTable(font, CTFontTableTag(kCTFontTableName), []) as Data?
            )
        }
    }
#endif
