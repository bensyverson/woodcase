//
//  IconLibraryMapping+Glyph.swift
//  Woodcase
//

extension IconLibraryMapping {
    /// How a library's React component draws its glyph, which a paint that is not a color
    /// has to know: every supported library renders an `<svg>`, but they differ in the
    /// attribute the glyph is painted with and the user space it is drawn in.
    struct Glyph: Friendly {
        /// The `<svg>` attribute the glyph's paint is: `stroke` for an outline library,
        /// `fill` for a filled one. Every library spreads its remaining props onto the
        /// `<svg>` after its own defaults, so passing this attribute sets the paint.
        var paintAttribute: String

        /// The component's `viewBox`, which it scales onto its `size`: the node's box, in the
        /// icon's own user space, where a `userSpaceOnUse` paint server is laid out.
        var viewBox: ReactEmitter.SVGStrokedShape.Box
    }

    /// The glyph of `family`'s React component, or `nil` for a family this build does not
    /// map (``resolve(family:iconName:)`` answers `nil` for it too).
    ///
    /// Read from each package's source: lucide-react and react-feather set
    /// `stroke={color}` over `viewBox="0 0 24 24"`; @phosphor-icons/react sets
    /// `fill={color}` over `0 0 256 256`; @nine-thirty-five/material-symbols-react sets
    /// `fill="currentColor"` over `0 -960 960 960`.
    static func glyph(for family: String) -> Glyph? {
        switch family {
        case "lucide", "feather":
            Glyph(paintAttribute: "stroke", viewBox: .init(x: 0, y: 0, width: 24, height: 24))
        case "phosphor":
            Glyph(paintAttribute: "fill", viewBox: .init(x: 0, y: 0, width: 256, height: 256))
        case "Material Symbols Outlined", "Material Symbols Rounded", "Material Symbols Sharp":
            Glyph(paintAttribute: "fill", viewBox: .init(x: 0, y: -960, width: 960, height: 960))
        default:
            nil
        }
    }
}
