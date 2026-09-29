import CoreGraphics
import Foundation

/// How a text or icon node's fills paint its glyphs.
///
/// Core Text can color glyphs with one solid color and nothing else. Every other paint —
/// a gradient, an image, a stack of fills, a blended solid — is drawn through the glyph
/// outlines (``PenGlyphOutlines``) over the node's box, exactly as it would fill a
/// rectangle of that size. The lone solid keeps Core Text so that ordinary text draws
/// byte for byte as it always has.
///
/// This is the rule Woodcase's CG renderer draws text and icons by, public so that another
/// renderer follows it rather than a copy of it (RapidPro's text rasterizer does).
///
/// ```swift
/// switch PenGlyphPaint(fills: textData.fills) {
/// case .nothing: break                      // draw nothing
/// case let .solid(color): draw(in: color)  // Core Text, one color
/// case .glyphOutlines: paintThroughOutlines()
/// }
/// ```
public enum PenGlyphPaint: Friendly {
    /// No enabled paint: nothing is drawn, as Pen draws nothing for a text or icon with
    /// no fill, an empty fill list, or only disabled fills (`render-text-unfilled.pen`).
    case nothing
    /// A single solid of normal blend: Core Text draws the glyphs in this color. A solid
    /// whose color does not parse — an invalid hex, an unresolved `$variable` — is still
    /// an enabled paint, and paints opaque black, as Pen paints it.
    case solid(PenHexColor)
    /// Anything else: the fills are drawn through the glyphs' outlines over the node's box.
    case glyphOutlines

    /// Chooses the paint for a node's fills.
    ///
    /// - Parameter fills: The node's fills, after any override.
    public init(fills: PenFills?) {
        let enabled = (fills?.all ?? []).filter(Self.isEnabled)
        switch enabled.count {
        case 0:
            self = .nothing
        case 1:
            self = Self.isPlainSolid(enabled[0]) ? .solid(Self.color(of: enabled[0])) : .glyphOutlines
        default:
            self = .glyphOutlines
        }
    }

    /// The color Core Text is handed for the glyphs: the solid's, or opaque black for any
    /// other paint, where Core Text draws only color-font glyphs, which keep their own.
    var coreTextColor: CGColor {
        let color = if case let .solid(color) = self { color } else { Self.black }
        return CGColor(
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: color.unitComponents.map { CGFloat($0) }
        )!
    }

    private static let black = PenHexColor(red: 0, green: 0, blue: 0)

    private static func isEnabled(_ fill: PenFill) -> Bool {
        switch fill {
        case .shorthand: true
        case let .color(fill): fill.enabled?.literalValue != false
        case let .gradient(fill): fill.enabled?.literalValue != false
        case let .image(fill): fill.enabled?.literalValue != false
        case let .meshGradient(fill): fill.enabled?.literalValue != false
        case let .shader(fill): fill.enabled?.literalValue != false
        case .unknown: false
        }
    }

    private static func isPlainSolid(_ fill: PenFill) -> Bool {
        switch fill {
        case .shorthand: true
        case let .color(fill): fill.blendMode == nil || fill.blendMode == .normal
        case .gradient, .image, .meshGradient, .shader, .unknown: false
        }
    }

    /// A solid's color, black when it does not parse; black for any other fill.
    private static func color(of fill: PenFill) -> PenHexColor {
        let hex: String? = switch fill {
        case let .shorthand(hex): hex
        case let .color(fill): fill.color.literalValue
        case .gradient, .image, .meshGradient, .shader, .unknown: nil
        }
        return hex.flatMap(PenHexColor.init) ?? black
    }
}
