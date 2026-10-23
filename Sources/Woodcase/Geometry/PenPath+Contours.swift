import Foundation

public extension PenPath {
    /// The path the anchors draw: one subpath per contour.
    ///
    /// Each contour starts with a move to its first anchor. Between two anchors it draws a
    /// line when both facing handles are retracted, otherwise a cubic whose control points
    /// are the first anchor's out handle and the second's in handle. A closed contour then
    /// closes: when its closing segment is curved it is drawn as a cubic back to the first
    /// anchor before the `Z`, and when the last anchor sits exactly on the first it is drawn
    /// as a line, so that reading the path back keeps both anchors. A contour with no
    /// anchors draws nothing.
    ///
    /// Conversion copies coordinates and does no arithmetic, so for any contours whose open
    /// ends have retracted outer handles, `PenPath(contours: c).contours == c` — and it
    /// stays so through the path's ``svgPathData`` text, any number of times.
    init(contours: [PenPathContour]) {
        var commands: [PenPathCommand] = []
        for contour in contours {
            guard let first = contour.anchors.first, let last = contour.anchors.last else { continue }
            commands.append(.move(to: first.point))
            for (from, to) in zip(contour.anchors, contour.anchors.dropFirst()) {
                commands.append(Self.segment(from: from, to: to))
            }
            guard contour.isClosed else { continue }
            if last.hasOutHandle || first.hasInHandle || (contour.anchors.count > 1 && last.point == first.point) {
                commands.append(Self.segment(from: last, to: first))
            }
            commands.append(.close)
        }
        self.init(commands: commands)
    }

    /// The path as anchors: one contour per subpath.
    ///
    /// A line ends at a corner-side anchor; a cubic gives its start its out handle and its
    /// end its in handle. A quadratic becomes the cubic that draws the same curve, its handles
    /// two thirds of the way from each end to its control point, so a path holding
    /// quadratics comes back from ``init(contours:)`` drawn the same but written as cubics.
    /// Arcs were already cubics when the path was parsed (``init(svg:)``), so editing an arc
    /// edits those cubics. On a close, a final segment that ends exactly on the first anchor
    /// is that anchor arriving again: its in handle goes to the first anchor and it is not
    /// repeated. Drawing on after a close without a move starts a new contour at the closed
    /// one's start; data that does not start with a move starts at the origin.
    var contours: [PenPathContour] {
        var reader = ContourReader()
        for command in commands {
            reader.read(command)
        }
        return reader.finish()
    }

    /// The command for the segment between two anchors.
    private static func segment(from: PenPathAnchor, to: PenPathAnchor) -> PenPathCommand {
        guard from.hasOutHandle || to.hasInHandle else { return .line(to: to.point) }
        return .cubicCurve(to: to.point, control1: from.outHandle, control2: to.inHandle)
    }

    /// Collects contours from commands, holding the contour being drawn and the points a
    /// command without its own start depends on.
    private struct ContourReader {
        var contours: [PenPathContour] = []
        var contour: PenPathContour?
        var current = PenPoint.zero
        var subpathStart = PenPoint.zero

        mutating func read(_ command: PenPathCommand) {
            switch command {
            case let .move(to):
                flush()
                contour = PenPathContour(anchors: [PenPathAnchor(point: to)], isClosed: false)
                subpathStart = to
                current = to
            case let .line(to):
                append(PenPathAnchor(point: to))
            case let .quadCurve(to, control):
                let control1 = PenPoint(x: (current.x + 2 * control.x) / 3, y: (current.y + 2 * control.y) / 3)
                let control2 = PenPoint(x: (to.x + 2 * control.x) / 3, y: (to.y + 2 * control.y) / 3)
                append(PenPathAnchor(point: to, inHandle: control2), outHandle: control1)
            case let .cubicCurve(to, control1, control2):
                append(PenPathAnchor(point: to, inHandle: control2), outHandle: control1)
            case .close:
                if contour == nil {
                    contour = PenPathContour(anchors: [PenPathAnchor(point: current)], isClosed: false)
                }
                close()
                current = subpathStart
            }
        }

        /// Appends an anchor, setting the previous anchor's out handle; a contour is started
        /// at the current point when none is being drawn.
        private mutating func append(_ anchor: PenPathAnchor, outHandle: PenPoint? = nil) {
            // Taken out while it grows, so appending does not copy the anchors.
            var drawing = contour ?? PenPathContour(anchors: [PenPathAnchor(point: current)], isClosed: false)
            contour = nil
            if let outHandle {
                drawing.anchors[drawing.anchors.count - 1].outHandle = outHandle
            }
            drawing.anchors.append(anchor)
            contour = drawing
            current = anchor.point
        }

        private mutating func close() {
            guard var closing = contour else { return }
            if closing.anchors.count > 1, let last = closing.anchors.last, last.point == closing.anchors[0].point {
                closing.anchors[0].inHandle = last.inHandle
                closing.anchors.removeLast()
            }
            closing.isClosed = true
            contour = closing
            flush()
        }

        private mutating func flush() {
            if let contour { contours.append(contour) }
            contour = nil
        }

        mutating func finish() -> [PenPathContour] {
            flush()
            return contours
        }
    }
}
