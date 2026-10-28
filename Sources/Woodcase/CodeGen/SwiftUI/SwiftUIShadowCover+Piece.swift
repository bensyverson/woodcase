//
//  SwiftUIShadowCover+Piece.swift
//  Woodcase
//

import Foundation

extension SwiftUIShadowCover {
    /// A rounded box that bounds part of a silhouette, in the covering frame's coordinates.
    struct Piece: Friendly {
        /// The left edge.
        var x: Double
        /// The top edge.
        var y: Double
        /// The width.
        var width: Double
        /// The height.
        var height: Double
        /// The corner radii, before they are fitted to the box.
        var corners: PenCornerRadius.Corners = .zero

        /// Allowance for floating-point noise in the layout, in points.
        private static let epsilon = 0.01

        /// How far past its layout box a text's or an icon's ink is allowed to be measured
        /// differently, in points: a font measured otherwise than Pen's.
        private static let inkAllowance = 1.0

        /// The pieces bounding the silhouettes of `children` and their descendants, in their
        /// parent's coordinates, as ``PenShadowSilhouette`` draws them: a frame's or a
        /// rectangle's box where its fill paints and its stroke band where its stroke paints,
        /// a clipping frame's box for everything inside it, and any other kind's painted
        /// extent (``PenLayoutEngine/paintedExtent(of:rect:layoutRects:)``, which also counts
        /// its own shadows) — or `nil` when one cannot be bounded: a turned or flipped
        /// descendant, one the layout did not place, or a kind with no silhouette rule here.
        ///
        /// Walks a work list, so a deep tree costs no stack (issue `g5SACU`).
        static func silhouette(of children: [PenNode], rects: [String: PenRect]) -> [Piece]? {
            var pieces: [Piece] = []
            var open: [(node: PenNode, x: Double, y: Double)] = children.reversed().map { ($0, 0, 0) }
            while let (node, originX, originY) = open.popLast() {
                guard node.common.enabled?.literalValue != false else { continue }
                guard !isTurned(node), let rect = rects[node.id], rect.width.isFinite, rect.height.isFinite else { return nil }
                let x = originX + rect.x
                let y = originY + rect.y
                switch node.kind {
                case let .frame(data):
                    guard let own = boxPieces(fills: data.fills, stroke: data, radius: data.cornerRadius, x: x, y: y, rect: rect)
                    else { return nil }
                    pieces += own
                    let children = data.children ?? []
                    if data.clip?.literalValue == true {
                        if !children.isEmpty {
                            let corners = data.cornerRadius?.resolve() ?? .zero
                            pieces.append(Piece(x: x, y: y, width: rect.width, height: rect.height, corners: corners))
                        }
                    } else {
                        open += children.reversed().map { ($0, x, y) }
                    }
                case let .rectangle(data):
                    guard let own = boxPieces(fills: data.fills, stroke: data, radius: data.cornerRadius, x: x, y: y, rect: rect)
                    else { return nil }
                    pieces += own
                case let .group(data):
                    open += (data.children ?? []).reversed().map { ($0, x, y) }
                case .ellipse, .polygon, .path, .line, .text, .icon:
                    let extent = PenLayoutEngine.paintedExtent(of: node, rect: rect, layoutRects: rects)
                    guard extent.width.isFinite, extent.height.isFinite else { return nil }
                    let grow: Double = switch node.kind {
                    case .text, .icon: inkAllowance
                    default: 0
                    }
                    pieces.append(Piece(
                        x: originX + extent.x - grow, y: originY + extent.y - grow,
                        width: extent.width + grow * 2, height: extent.height + grow * 2
                    ))
                default:
                    return nil
                }
            }
            return pieces
        }

        /// A box node's own pieces: its box where its fill paints, and its box grown by its
        /// stroke's reach where the stroke paints — or `nil` when a width cannot be read.
        private static func boxPieces(
            fills: PenFills?, stroke: any PenStrokable, radius: PenCornerRadius?, x: Double, y: Double, rect: PenRect
        ) -> [Piece]? {
            // An unread radius is drawn as some radius; a sharp box bounds every one.
            let corners = radius?.resolve() ?? .zero
            var pieces: [Piece] = []
            if SwiftUINodeEmitter.castsPaint(fills) {
                pieces.append(Piece(x: x, y: y, width: rect.width, height: rect.height, corners: corners))
            }
            if SwiftUINodeEmitter.castsPaint(stroke.stroke) {
                guard let reach = reach(of: stroke) else { return nil }
                let grow = { (radius: Double) in radius > 0 ? radius + reach : 0 }
                pieces.append(Piece(
                    x: x - reach, y: y - reach, width: rect.width + reach * 2, height: rect.height + reach * 2,
                    corners: PenCornerRadius.Corners(
                        topLeft: grow(corners.topLeft), topRight: grow(corners.topRight),
                        bottomRight: grow(corners.bottomRight), bottomLeft: grow(corners.bottomLeft)
                    )
                ))
            }
            return pieces
        }

        /// How far past the outline a stroke reaches: all of its widest side outside, half
        /// of it centered, none inside — or `nil` for a width left as a variable.
        private static func reach(of stroke: any PenStrokable) -> Double? {
            let widths: [PenValue<Double>] = switch stroke.strokeWidth {
            case let .uniform(value): [value]
            case let .perSide(sides): [sides.top, sides.right, sides.bottom, sides.left].compactMap(\.self)
            case nil: []
            }
            var widest = 0.0
            for width in widths {
                guard let value = width.literalValue else { return nil }
                widest = max(widest, value)
            }
            return switch stroke.strokeAlignment ?? .center {
            case .outer: widest
            case .center: widest / 2
            case .inner: 0
            }
        }

        /// Whether `node` is turned or flipped, which the test does not bound.
        private static func isTurned(_ node: PenNode) -> Bool {
            let common = node.common
            let turned = common.rotation.map { $0.literalValue.map { $0.truncatingRemainder(dividingBy: 360) != 0 } ?? true } ?? false
            return turned || common.flipX.map { $0.literalValue != false } == true || common.flipY.map { $0.literalValue != false } == true
        }

        /// Whether this piece, read as a covering shape, holds all of `piece`: `piece` lies in
        /// its box, and wherever it reaches into one of its rounded corners, every point of
        /// `piece` there lies in the corner's circle.
        ///
        /// In a corner, only `piece`'s own corner can reach farthest: a straight edge is
        /// farthest from the circle's center at its ends, one on the corner's arc and one on
        /// a line through the center, which the box already bounds. So the test samples
        /// `piece`'s corner arc (its corner point, when it is sharp), and a sample must clear
        /// the circle by the most the arc can bulge between two samples. This shape's radii
        /// are fitted to its box at their largest (`min(r, w/2, h/2)`), and `piece`'s at their
        /// smallest, so the test errs toward not covered.
        func contains(_ piece: Piece) -> Bool {
            let eps = Self.epsilon
            guard piece.x >= x - eps, piece.y >= y - eps,
                  piece.x + piece.width <= x + width + eps, piece.y + piece.height <= y + height + eps
            else { return false }
            let outer = largestRadii
            let inner = piece.smallestRadii
            // Each corner: its radius here and there, and which way is outward on each axis.
            let corners: [(outer: Double, inner: Double, dx: Double, dy: Double)] = [
                (outer[0], inner[0], -1, -1), (outer[1], inner[1], 1, -1),
                (outer[2], inner[2], 1, 1), (outer[3], inner[3], -1, 1),
            ]
            return corners.allSatisfy { corner in
                guard corner.outer > 0 else { return true }
                let centerX = corner.dx < 0 ? x + corner.outer : x + width - corner.outer
                let centerY = corner.dy < 0 ? y + corner.outer : y + height - corner.outer
                // The piece's extremes toward this corner: it reaches the corner's square only
                // past the circle's center on both axes.
                let edgeX = corner.dx < 0 ? piece.x : piece.x + piece.width
                let edgeY = corner.dy < 0 ? piece.y : piece.y + piece.height
                guard (edgeX - centerX) * corner.dx > eps, (edgeY - centerY) * corner.dy > eps else { return true }
                let arcX = edgeX - corner.dx * corner.inner
                let arcY = edgeY - corner.dy * corner.inner
                let steps = corner.inner > 0 ? Self.arcSamples : 0
                let bulge = corner.inner * (1 - cos(Double.pi / 4 / Double(max(steps, 1))))
                return (0 ... steps).allSatisfy { step in
                    let angle = Double.pi / 2 * Double(step) / Double(max(steps, 1))
                    let pointX = arcX + corner.dx * corner.inner * cos(angle)
                    let pointY = arcY + corner.dy * corner.inner * sin(angle)
                    // A sample outside the corner's square is bounded by the box.
                    guard (pointX - centerX) * corner.dx > 0, (pointY - centerY) * corner.dy > 0 else { return true }
                    let distance = ((pointX - centerX) * (pointX - centerX) + (pointY - centerY) * (pointY - centerY)).squareRoot()
                    return distance + bulge <= corner.outer + eps
                }
            }
        }

        /// How many steps a corner arc is sampled in.
        private static let arcSamples = 32

        /// The radii as large as a renderer could draw them in this box: each limited to half
        /// the shorter side. Top left, top right, bottom right, bottom left.
        private var largestRadii: [Double] {
            let limit = min(width, height) / 2
            return radii.map { min(max($0, 0), limit) }
        }

        /// The radii as small as a renderer could draw them in this box: each limited to half
        /// the shorter side, and all scaled down together where two on one side overlap.
        private var smallestRadii: [Double] {
            let r = radii.map { max($0, 0) }
            let sums = [(r[0] + r[1], width), (r[3] + r[2], width), (r[0] + r[3], height), (r[1] + r[2], height)]
            let scale = sums.reduce(1.0) { scale, pair in pair.0 > pair.1 && pair.0 > 0 ? min(scale, pair.1 / pair.0) : scale }
            let limit = min(width, height) / 2
            return r.map { min($0 * scale, limit) }
        }

        /// The radii in order: top left, top right, bottom right, bottom left.
        private var radii: [Double] {
            [corners.topLeft, corners.topRight, corners.bottomRight, corners.bottomLeft]
        }
    }
}
