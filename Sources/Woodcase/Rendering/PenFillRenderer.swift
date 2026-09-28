import CoreGraphics
import Foundation

/// Renders fills — solid colours, gradients, mesh gradients and images — through a clip,
/// over a paint domain.
///
/// A fill has two geometric inputs, and they are deliberately separate:
///
/// - The **clip** — a path and its fill rule — is *where* the fill shows: a shape's outline
///   (even-odd for a donut or an `evenodd` path), and equally a text node's glyph outlines
///   or a stroke's outline.
/// - The **domain** is the rectangle the paint is *laid out over*: where a gradient's
///   stops land and where an image is stretched, filled or fitted. Pen lays every paint
///   over the node's layout box whatever the outline inside it — a hexagon, a quarter
///   pie, glyphs or a stroke band all show a slice of the paint the box would show.
///
/// Outside the domain a gradient pads with its end colours; an image draws nothing there.
enum PenFillRenderer {
    /// Renders all enabled fills, bottom to top, each clipped to `clip` and laid out over `domain`.
    ///
    /// Each fill is clipped separately, so a stack of translucent or blended fills composites
    /// through the clip's coverage one fill at a time, as Pen does. Disabled fills and shader
    /// fills draw nothing.
    ///
    /// - Parameters:
    ///   - fills: The node's fills; `nil` draws nothing.
    ///   - clip: The outline the fills show through, in the context's current space.
    ///   - fillRule: How `clip`'s sub-paths combine: `.evenOdd` makes a nested sub-path a hole.
    ///   - domain: The rectangle the paint is laid out over — the node's box for every
    ///     shape, text node and stroke Pen draws.
    ///   - context: The context to draw into.
    ///   - imageProvider: Resolves an image fill's URL to an image.
    static func renderFills(
        _ fills: PenFills?,
        clip: CGPath,
        fillRule: CGPathFillRule,
        domain: CGRect,
        in context: CGContext,
        imageProvider: PenRenderer.ImageProvider = { _ in nil }
    ) {
        guard let fills else { return }
        let target = Target(clip: clip, fillRule: fillRule, domain: domain)
        for fill in fills.all {
            renderFill(fill, onto: target, in: context, imageProvider: imageProvider)
        }
    }

    /// The clip and the paint domain one fill is drawn with.
    struct Target {
        /// The outline the fill shows through.
        let clip: CGPath
        /// How the clip's sub-paths combine.
        let fillRule: CGPathFillRule
        /// The rectangle the paint is laid out over.
        let domain: CGRect

        /// Intersects the context's clip with this target's outline.
        func applyClip(in context: CGContext) {
            context.addPath(clip)
            context.clip(using: fillRule)
        }
    }

    private static func renderFill(
        _ fill: PenFill,
        onto target: Target,
        in context: CGContext,
        imageProvider: PenRenderer.ImageProvider
    ) {
        switch fill {
        case let .shorthand(hex):
            guard let color = PenColorParser.parse(hex) else { return }
            renderSolid(color, blendMode: nil, onto: target, in: context)

        case let .color(colorFill):
            guard colorFill.enabled?.literalValue != false,
                  let hex = colorFill.color.literalValue,
                  let color = PenColorParser.parse(hex)
            else { return }
            renderSolid(color, blendMode: colorFill.blendMode, onto: target, in: context)

        case let .gradient(gradientFill):
            renderGradient(gradientFill, onto: target, in: context)

        case let .image(imageFill):
            renderImageFill(imageFill, onto: target, in: context, imageProvider: imageProvider)

        case let .meshGradient(meshFill):
            renderMeshGradient(meshFill, onto: target, in: context)

        case .shader:
            // Shader fills are not executed; drawn as transparent.
            break

        case .unknown:
            // A fill type this build does not model is preserved, never drawn.
            break
        }
    }

    /// A solid colour covers the whole domain, so it is filled straight through the outline
    /// rather than clipped — the same pixels, with the path's own anti-aliasing.
    private static func renderSolid(
        _ color: CGColor,
        blendMode: PenBlendMode?,
        onto target: Target,
        in context: CGContext
    ) {
        context.saveGState()
        if let blendMode {
            context.setBlendMode(blendMode.cgBlendMode)
        }
        context.addPath(target.clip)
        context.setFillColor(color)
        context.fillPath(using: target.fillRule)
        context.restoreGState()
    }
}
