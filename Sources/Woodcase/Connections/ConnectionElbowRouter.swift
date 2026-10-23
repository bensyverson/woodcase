//
//  ConnectionElbowRouter.swift
//  Woodcase
//

import Foundation

/// The orthogonal route between two anchors that ``PenNode/ConnectionData/Routing/elbow``
/// draws: it leaves the source's side along that side's outward normal and enters the
/// target's against its normal, every run horizontal or vertical.
///
/// The route is worked out in one canonical frame — the source at the origin, leaving
/// toward +x — and turned back: every source side is a quarter turn of every other, and a
/// target facing up is a target facing down reflected, so three cases cover all twenty-five
/// anchor pairs. Turns and reflections by quarter turns only swap and negate coordinates,
/// so the points come back exact.
///
/// - **Facing** (the target's side faces back at the source): one step at the middle of
///   the gap, or a straight run when the anchors line up; a target behind the source is
///   reached round the gap between the boxes, or round the nearer side of both.
/// - **Same way** (both sides face the same way): out past the farther box and back in,
///   stepping round the other box when the run would cross it.
/// - **Perpendicular**: one corner when the target's side faces the source's run, or round
///   the target's far side, or through the gap between the boxes.
///
/// It routes round the two endpoint boxes only, never round other nodes. A center anchor,
/// which has no side, leaves toward the other end along the longer axis between them.
enum ConnectionElbowRouter {
    /// The route from one anchor to another.
    ///
    /// - Parameters:
    ///   - start: The source anchor's point, on the canvas.
    ///   - startSide: The source's anchor.
    ///   - startBox: The source node's box, on the canvas.
    ///   - end: The target anchor's point, on the canvas.
    ///   - endSide: The target's anchor.
    ///   - endBox: The target node's box, on the canvas.
    ///   - margin: How far the route runs out from a box before it turns, and clears a box
    ///     it goes round by, in points.
    /// - Returns: The route's points, from `start` to `end`, with no empty runs and no
    ///   point in the middle of a straight run.
    static func route(
        from start: PenPoint, side startSide: PenNode.ConnectionData.Anchor, box startBox: PenRect,
        to end: PenPoint, side endSide: PenNode.ConnectionData.Anchor, box endBox: PenRect,
        margin: Double
    ) -> [PenPoint] {
        let leaving = startSide.outwardNormal ?? axis(toward: end, from: start)
        let facing = endSide.outwardNormal ?? axis(toward: start, from: end)
        var frame = Frame(mapping: leaving)
        var target = frame.local(end, origin: start)
        var targetFacing = frame.local(facing)
        var source = frame.local(startBox, origin: start)
        var box = frame.local(endBox, origin: start)
        if targetFacing.y < 0 {
            frame = frame.reflected
            target.y = -target.y
            targetFacing.y = -targetFacing.y
            source = source.reflected
            box = box.reflected
        }
        let local = solve(to: target, facing: targetFacing, source: source, target: box, margin: margin)
        return simplified(local.map { frame.world($0, origin: start) })
    }

    // MARK: - The canonical cases

    /// The route in the canonical frame: from the origin, leaving toward +x, to `end`, whose
    /// side faces `facing` — never up, which the caller reflects to down.
    private static func solve(
        to end: PenPoint, facing: PenPoint, source: Box, target: Box, margin: Double
    ) -> [PenPoint] {
        let start = PenPoint.zero
        let (dx, dy) = (end.x, end.y)
        let out = source.maxX + margin
        if facing.x < 0 {
            // Facing: the route arrives moving toward +x.
            if dx > 0, dy == 0 { return [start, end] }
            if dx > 0, target.minX > source.maxX {
                let middle = (source.maxX + target.minX) / 2
                return [start, PenPoint(x: middle, y: 0), PenPoint(x: middle, y: dy), end]
            }
            let y = detour(clearing: source, and: target, near: dy / 2, margin: margin)
            let back = target.minX - margin
            return [start, PenPoint(x: out, y: 0), PenPoint(x: out, y: y), PenPoint(x: back, y: y),
                    PenPoint(x: back, y: dy), end]
        }
        if facing.x > 0 {
            // Same way: the route arrives moving toward -x.
            let beyond = max(source.maxX, target.maxX) + margin
            if dx >= 0, target.minY < 0, target.maxY > 0, target.minX > source.maxX {
                let step = (source.maxX + target.minX) / 2
                let y = detour(clearing: target, near: 0, margin: margin)
                return [start, PenPoint(x: step, y: 0), PenPoint(x: step, y: y), PenPoint(x: beyond, y: y),
                        PenPoint(x: beyond, y: dy), end]
            }
            if dx < 0, source.minY < dy, source.maxY > dy, source.minX > target.maxX {
                let step = (target.maxX + source.minX) / 2
                let y = detour(clearing: source, near: dy, margin: margin)
                return [start, PenPoint(x: out, y: 0), PenPoint(x: out, y: y), PenPoint(x: step, y: y),
                        PenPoint(x: step, y: dy), end]
            }
            return [start, PenPoint(x: beyond, y: 0), PenPoint(x: beyond, y: dy), end]
        }
        // Perpendicular, the target's side facing down: the route arrives moving up.
        if dx > 0, dy < 0 { return [start, PenPoint(x: dx, y: 0), end] }
        if dx > 0, target.minX > source.maxX {
            let step = (source.maxX + target.minX) / 2
            let under = max(target.maxY, dy) + margin
            return [start, PenPoint(x: step, y: 0), PenPoint(x: step, y: under), PenPoint(x: dx, y: under), end]
        }
        if target.maxY < source.minY {
            let gap = (target.maxY + source.minY) / 2
            return [start, PenPoint(x: out, y: 0), PenPoint(x: out, y: gap), PenPoint(x: dx, y: gap), end]
        }
        let beyond = max(source.maxX, target.maxX) + margin
        let under = max(source.maxY, target.maxY, dy) + margin
        return [start, PenPoint(x: beyond, y: 0), PenPoint(x: beyond, y: under), PenPoint(x: dx, y: under), end]
    }

    /// A horizontal line clear of both boxes: through the gap between them when they do not
    /// overlap vertically, or a margin past whichever side of both is nearer `near` —
    /// below, on a tie.
    private static func detour(clearing one: Box, and other: Box, near: Double, margin: Double) -> Double {
        if one.maxY < other.minY { return (one.maxY + other.minY) / 2 }
        if other.maxY < one.minY { return (other.maxY + one.minY) / 2 }
        let above = min(one.minY, other.minY) - margin
        let below = max(one.maxY, other.maxY) + margin
        return abs(above - near) < abs(below - near) ? above : below
    }

    /// A horizontal line a margin past whichever side of the box is nearer `near` — below,
    /// on a tie.
    private static func detour(clearing box: Box, near: Double, margin: Double) -> Double {
        let above = box.minY - margin
        let below = box.maxY + margin
        return abs(above - near) < abs(below - near) ? above : below
    }

    // MARK: - Geometry

    /// The axis direction from `origin` toward `point` along the longer of the two axes
    /// between them — horizontal on a tie, +x when they coincide.
    private static func axis(toward point: PenPoint, from origin: PenPoint) -> PenPoint {
        let (dx, dy) = (point.x - origin.x, point.y - origin.y)
        if abs(dx) >= abs(dy) { return PenPoint(x: dx < 0 ? -1 : 1, y: 0) }
        return PenPoint(x: 0, y: dy < 0 ? -1 : 1)
    }

    /// `points` with repeated points removed, and every point in the middle of a straight
    /// run that carries on the same way.
    private static func simplified(_ points: [PenPoint]) -> [PenPoint] {
        var kept: [PenPoint] = []
        for point in points where kept.last != point {
            if kept.count >= 2 {
                let (before, middle) = (kept[kept.count - 2], kept[kept.count - 1])
                let first = PenPoint(x: middle.x - before.x, y: middle.y - before.y)
                let second = PenPoint(x: point.x - middle.x, y: point.y - middle.y)
                let cross = first.x * second.y - first.y * second.x
                let dot = first.x * second.x + first.y * second.y
                if cross == 0, dot > 0 { kept.removeLast() }
            }
            kept.append(point)
        }
        return kept
    }

    /// A box by its edges.
    private struct Box {
        var minX: Double, minY: Double, maxX: Double, maxY: Double

        /// The box reflected across the x axis.
        var reflected: Box {
            Box(minX: minX, minY: -maxY, maxX: maxX, maxY: -minY)
        }
    }

    /// A quarter turn, perhaps with a reflection, from the canonical frame to the canvas:
    /// `world = (a·x + b·y, c·x + d·y)`, every entry 0 or ±1.
    private struct Frame {
        var a: Double, b: Double, c: Double, d: Double

        /// The turn that carries +x onto `direction`, a unit axis vector.
        init(mapping direction: PenPoint) {
            (a, b, c, d) = (direction.x, -direction.y, direction.y, direction.x)
        }

        private init(a: Double, b: Double, c: Double, d: Double) {
            (self.a, self.b, self.c, self.d) = (a, b, c, d)
        }

        /// This frame after reflecting the canonical y axis.
        var reflected: Frame {
            Frame(a: a, b: -b, c: c, d: -d)
        }

        /// A canvas direction in the canonical frame (the transpose: the map is orthogonal).
        func local(_ vector: PenPoint) -> PenPoint {
            PenPoint(x: a * vector.x + c * vector.y, y: b * vector.x + d * vector.y)
        }

        /// A canvas point in the canonical frame whose origin is `origin`.
        func local(_ point: PenPoint, origin: PenPoint) -> PenPoint {
            local(PenPoint(x: point.x - origin.x, y: point.y - origin.y))
        }

        /// A canvas box in the canonical frame whose origin is `origin`.
        func local(_ rect: PenRect, origin: PenPoint) -> Box {
            let one = local(PenPoint(x: rect.x, y: rect.y), origin: origin)
            let other = local(PenPoint(x: rect.x + rect.width, y: rect.y + rect.height), origin: origin)
            return Box(minX: min(one.x, other.x), minY: min(one.y, other.y),
                       maxX: max(one.x, other.x), maxY: max(one.y, other.y))
        }

        /// A canonical point on the canvas.
        func world(_ point: PenPoint, origin: PenPoint) -> PenPoint {
            PenPoint(x: a * point.x + b * point.y + origin.x, y: c * point.x + d * point.y + origin.y)
        }
    }
}
