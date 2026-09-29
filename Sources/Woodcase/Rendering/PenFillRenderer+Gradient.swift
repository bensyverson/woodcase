import CoreGraphics
import Foundation

extension PenFillRenderer {
    /// Draws one gradient fill through `target`'s clip, laid out over its domain.
    ///
    /// The gradient's frame (``PenFill/PenGradientFill/frameTransform(in:)``) is built from
    /// the domain, never from the clip, so a gradient seen through a hexagon, a glyph or a
    /// stroke band is the slice of the gradient the whole box would show.
    static func renderGradient(
        _ gradient: PenFill.PenGradientFill,
        onto target: Target,
        in context: CGContext
    ) {
        guard gradient.enabled?.literalValue != false else { return }
        guard let cgGradient = buildCGGradient(from: gradient) else { return }

        let frame = gradient.frameTransform(in: target.domain)
        // A zero `size` or an empty domain collapses the gradient; there is nothing to lay out.
        guard abs(frame.a * frame.d - frame.b * frame.c) > 1e-12 else { return }

        context.saveGState()
        defer { context.restoreGState() }

        if let blendMode = gradient.blendMode {
            context.setBlendMode(blendMode.cgBlendMode)
        }
        let opacity = gradient.opacity?.literalValue ?? 1.0
        if opacity < 1.0 {
            context.setAlpha(CGFloat(opacity))
        }
        target.applyClip(in: context)

        switch gradient.gradientType ?? .linear {
        case .linear:
            context.concatenate(frame)
            context.drawLinearGradient(
                cgGradient,
                start: CGPoint(x: 0, y: 0.5),
                end: CGPoint(x: 0, y: -0.5),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        case .radial:
            context.concatenate(frame)
            context.drawRadialGradient(
                cgGradient,
                startCenter: .zero,
                startRadius: 0,
                endCenter: .zero,
                endRadius: 0.5,
                options: [.drawsAfterEndLocation]
            )
        case .angular:
            // An angular gradient is defined everywhere, so the bitmap must reach wherever the
            // clip does — past the domain for an outer or centered stroke.
            let bounds = target.domain.union(target.clip.boundingBoxOfPath)
            drawAngularGradient(gradient, frame: frame, bounds: bounds, in: context)
        }
    }

    /// A `CGGradient` in sRGB from the fill's parsable stops, or `nil` when none parse.
    static func buildCGGradient(from gradient: PenFill.PenGradientFill) -> CGGradient? {
        guard let stops = gradient.colors, !stops.isEmpty else { return nil }

        var colors: [CGColor] = []
        var positions: [CGFloat] = []

        for stop in stops {
            guard let hex = stop.color.literalValue,
                  let color = PenColorParser.parse(hex)
            else { continue }
            colors.append(color)
            positions.append(CGFloat(stop.position.literalValue ?? 0))
        }

        guard !colors.isEmpty else { return nil }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        return CGGradient(
            colorsSpace: colorSpace,
            colors: colors as CFArray,
            locations: positions
        )
    }
}
