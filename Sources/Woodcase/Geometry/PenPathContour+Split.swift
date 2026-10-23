import Foundation

public extension PenPathContour {
    /// The contour with a new anchor on one of its segments, drawing the same shape.
    ///
    /// On a cubic the segment is split by de Casteljau's construction: the anchors either
    /// side keep their points and far handles, their handles facing the split shorten to
    /// the two halves' control points, and the new anchor sits on the curve with the
    /// collinear handles of a smooth anchor. On a straight segment the new anchor is a
    /// corner, its handles retracted, at the straight-line point. `t` is clamped to 0…1;
    /// at either end the new anchor sits on that end's anchor.
    ///
    /// - Parameters:
    ///   - segment: The segment, numbered as ``NearestPoint/segment`` numbers it; it must
    ///     be a segment the contour draws.
    ///   - t: How far along it, as ``NearestPoint/t`` gives it.
    /// - Returns: The new contour, and the index of the new anchor in it: `segment + 1`,
    ///   which for a closed contour's closing segment is the end.
    func insertingAnchor(inSegment segment: Int, at t: Double) -> (contour: PenPathContour, index: Int) {
        precondition((0 ..< segmentCount).contains(segment), "insertingAnchor(inSegment:at:) needs a segment the contour draws")
        let t = min(max(t, 0), 1)
        let piece = self.segment(segment)
        let endIndex = (segment + 1) % anchors.count
        var contour = self
        let anchor: PenPathAnchor
        if piece.isLine {
            anchor = PenPathAnchor(point: Segment.lerp(piece.start, piece.end, t))
        } else {
            let q0 = Segment.lerp(piece.start, piece.control1, t)
            let q1 = Segment.lerp(piece.control1, piece.control2, t)
            let q2 = Segment.lerp(piece.control2, piece.end, t)
            let r0 = Segment.lerp(q0, q1, t)
            let r1 = Segment.lerp(q1, q2, t)
            anchor = PenPathAnchor(point: Segment.lerp(r0, r1, t), inHandle: r0, outHandle: r1)
            contour.anchors[segment].outHandle = q0
            contour.anchors[endIndex].inHandle = q2
        }
        contour.anchors.insert(anchor, at: segment + 1)
        return (contour, segment + 1)
    }
}
