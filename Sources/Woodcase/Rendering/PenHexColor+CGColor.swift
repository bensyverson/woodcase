//
//  PenHexColor+CGColor.swift
//  Woodcase
//

#if canImport(CoreGraphics)
    import CoreGraphics

    extension PenHexColor {
        /// The color as a `CGColor` in sRGB, unpremultiplied, as Core Text takes a glyph color.
        var sRGBColor: CGColor {
            CGColor(
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                components: unitComponents.map { CGFloat($0) }
            )!
        }
    }
#endif
