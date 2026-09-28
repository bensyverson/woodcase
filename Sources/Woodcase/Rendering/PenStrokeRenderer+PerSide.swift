//
//  PenStrokeRenderer+PerSide.swift
//  Woodcase
//

import CoreGraphics

extension PenStrokeRenderer {
    /// A node's box and its corner radii: the shape a per-side stroke is laid out on.
    ///
    /// Only box-shaped nodes — frames, rectangles and browser nodes — have one; see
    /// ``PenStrokeRenderer/roundedBox(for:rect:)``. Pen strokes every other shape with a
    /// per-side width at its top width alone (``PenStrokable/drawn(on:)``).
    struct RoundedBox: Friendly {
        /// The node's box in user space.
        let rect: PenRect
        /// The node's corner radii, before clamping to the box.
        let corners: PenCornerRadius.Corners
    }

    /// The four widths of a per-side stroke, in points; a missing side is zero.
    struct SideWidths: Friendly {
        /// The top side's width.
        let top: CGFloat
        /// The right side's width.
        let right: CGFloat
        /// The bottom side's width.
        let bottom: CGFloat
        /// The left side's width.
        let left: CGFloat

        /// The literal widths of `sides`; a missing side, or one naming a variable, is zero.
        init(_ sides: PenStrokeWidth.Sides) {
            top = sides.top?.literalValue.map { CGFloat($0) } ?? 0
            right = sides.right?.literalValue.map { CGFloat($0) } ?? 0
            bottom = sides.bottom?.literalValue.map { CGFloat($0) } ?? 0
            left = sides.left?.literalValue.map { CGFloat($0) } ?? 0
        }

        /// Whether any side is drawn at all.
        var isEmpty: Bool {
            top <= 0 && right <= 0 && bottom <= 0 && left <= 0
        }
    }

    /// The box a per-side stroke on `node` is laid out on, or `nil` when the node is not box-shaped.
    ///
    /// - Parameters:
    ///   - node: The node carrying the stroke.
    ///   - rect: The node's box in user space.
    static func roundedBox(for node: PenNode, rect: PenRect) -> RoundedBox? {
        let corners: PenCornerRadius?
        switch node.kind {
        case let .frame(data): corners = data.cornerRadius
        case let .rectangle(data): corners = data.cornerRadius
        case let .browser(data): corners = data.cornerRadius
        default: return nil
        }
        return RoundedBox(rect: rect, corners: corners?.resolve() ?? .zero)
    }

    /// The region a per-side stroke covers: an outer rounded rectangle minus an inner one, to fill even-odd.
    ///
    /// Established from Pen's renders
    /// (`project/2026-09-26-gradient-geometry-and-per-side-strokes.md`). With `k` the
    /// alignment's share outside the box — inner 0, centre ½, outer 1 — each side's band
    /// runs from `k·width` outside the box's edge to `(1 − k)·width` inside it. Corners:
    ///
    /// - A square corner stays square on both edges.
    /// - A rounded corner of radius `r` keeps elliptical inner radii
    ///   `max(0, r − (1 − k)·w)` along each axis, `w` being the width of the side that
    ///   axis crosses — as CSS borders do.
    /// - Its outer radius is circular, `r + k·m`, where `m` is the smaller of the two
    ///   adjacent widths — except that a **centred** stroke whose half-width `½·m` exceeds
    ///   `r` gets radius `½·m` instead, which is what Pen draws for a uniform centred
    ///   stroke on a rounded rectangle too.
    ///
    /// - Parameters:
    ///   - widths: The stroke's width per side.
    ///   - alignment: Where the stroke sits relative to the box's edge.
    ///   - box: The node's box and corner radii.
    static func perSideRing(widths: SideWidths, alignment: PenStrokeAlign, box: RoundedBox) -> CGPath {
        let k: CGFloat = switch alignment {
        case .inner: 0
        case .center: 0.5
        case .outer: 1
        }
        let rect = box.rect.cgRect
        let limit = min(rect.width, rect.height) / 2
        let radii = [box.corners.topLeft, box.corners.topRight, box.corners.bottomRight, box.corners.bottomLeft]
            .map { min(CGFloat($0), limit) }
        // The widths each corner's x and y axes cross, clockwise from the top left.
        let crossing: [(x: CGFloat, y: CGFloat)] = [
            (widths.left, widths.top), (widths.right, widths.top),
            (widths.right, widths.bottom), (widths.left, widths.bottom),
        ]

        let outerRect = CGRect(
            x: rect.minX - k * widths.left,
            y: rect.minY - k * widths.top,
            width: rect.width + k * (widths.left + widths.right),
            height: rect.height + k * (widths.top + widths.bottom)
        )
        let outerRadii: [CGSize] = zip(radii, crossing).map { r, w in
            guard r > 0 else { return .zero }
            let m = min(w.x, w.y)
            let radius = alignment == .center && r < k * m ? k * m : r + k * m
            return CGSize(width: radius, height: radius)
        }

        let path = CGMutablePath()
        addRoundedRect(outerRect, radii: outerRadii, to: path)

        let inset = 1 - k
        // Checked before the rect is built: `CGRect.width` is the standardized, absolute
        // width, so a band wider than the box would come back as a hole the size of the
        // overshoot, and even-odd would cut it out of the band.
        let innerWidth = rect.width - inset * (widths.left + widths.right)
        let innerHeight = rect.height - inset * (widths.top + widths.bottom)
        let innerRect = CGRect(
            x: rect.minX + inset * widths.left, y: rect.minY + inset * widths.top,
            width: innerWidth, height: innerHeight
        )
        if innerWidth > 0, innerHeight > 0 {
            let innerRadii: [CGSize] = zip(radii, crossing).map { r, w in
                guard r > 0 else { return .zero }
                return CGSize(width: max(0, r - inset * w.x), height: max(0, r - inset * w.y))
            }
            addRoundedRect(innerRect, radii: innerRadii, to: path)
        }
        return path
    }

    /// Adds a rectangle with elliptical corners (top-left first, clockwise), each clamped to half the rectangle.
    private static func addRoundedRect(_ rect: CGRect, radii: [CGSize], to path: CGMutablePath) {
        let r = radii.map {
            CGSize(width: min($0.width, rect.width / 2), height: min($0.height, rect.height / 2))
        }
        // Control-point distance for a quarter ellipse drawn as one cubic Bézier.
        let kappa: CGFloat = 0.552_284_749_8
        let (tl, tr, br, bl) = (r[0], r[1], r[2], r[3])

        path.move(to: CGPoint(x: rect.minX + tl.width, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr.width, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + tr.height),
            control1: CGPoint(x: rect.maxX - tr.width * (1 - kappa), y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.minY + tr.height * (1 - kappa))
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br.height))
        path.addCurve(
            to: CGPoint(x: rect.maxX - br.width, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - br.height * (1 - kappa)),
            control2: CGPoint(x: rect.maxX - br.width * (1 - kappa), y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + bl.width, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bl.height),
            control1: CGPoint(x: rect.minX + bl.width * (1 - kappa), y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY - bl.height * (1 - kappa))
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl.height))
        path.addCurve(
            to: CGPoint(x: rect.minX + tl.width, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + tl.height * (1 - kappa)),
            control2: CGPoint(x: rect.minX + tl.width * (1 - kappa), y: rect.minY)
        )
        path.closeSubpath()
    }
}
