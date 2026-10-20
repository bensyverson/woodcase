//
//  FigmaVectorNetwork+Paths.swift
//  Woodcase
//

public extension FigmaVectorNetwork {
    /// The outline region `index` fills, under its ``Region/windingRule``: each loop a
    /// subpath, closed when it ends at the vertex it began from.
    ///
    /// A loop lists its segments in order, but each may be stored in either direction, so
    /// the walk takes each from whichever end touches the point reached so far. The first
    /// segment runs forward unless only its start touches the second. A segment with both tangents zero draws a line;
    /// any other a cubic whose controls are its vertices plus their tangents.
    ///
    /// - Parameter index: A valid index into ``regions``.
    /// - Throws: ``FigmaBlobError/disconnectedLoop(region:loop:segment:)`` when a segment
    ///   shares no vertex with the point its loop has reached.
    func path(ofRegion index: Int) throws(FigmaBlobError) -> FigmaPath {
        var commands: [FigmaPathCommand] = []
        for (loopIndex, loop) in regions[index].loops.enumerated() {
            guard let first = loop.first else { continue }
            let firstSegment = segments[first]
            var current = firstSegment.start
            if loop.count > 1 {
                let next = segments[loop[1]]
                if firstSegment.end != next.start, firstSegment.end != next.end {
                    current = firstSegment.end
                }
            }
            let start = current
            commands.append(.move(to: vertices[start].position))
            for (position, segmentIndex) in loop.enumerated() {
                let segment = segments[segmentIndex]
                if segment.start == current {
                    commands.append(command(segment, reversed: false))
                    current = segment.end
                } else if segment.end == current {
                    commands.append(command(segment, reversed: true))
                    current = segment.start
                } else {
                    throw .disconnectedLoop(region: index, loop: loopIndex, segment: position)
                }
            }
            if current == start {
                commands.append(.close)
            }
        }
        return FigmaPath(commands: commands)
    }

    /// Every segment once, in index order and in its stored direction, for a stroke: a
    /// segment that starts where the previous one ended continues its subpath, any other
    /// starts a new one.
    func segmentPath() -> FigmaPath {
        var commands: [FigmaPathCommand] = []
        var current: Int?
        for segment in segments {
            if segment.start != current {
                commands.append(.move(to: vertices[segment.start].position))
            }
            commands.append(command(segment, reversed: false))
            current = segment.end
        }
        return FigmaPath(commands: commands)
    }

    /// The command that draws `segment` from its start, or from its end when `reversed`.
    private func command(_ segment: Segment, reversed: Bool) -> FigmaPathCommand {
        var from = (vertex: vertices[segment.start].position, tangent: segment.tangentStart)
        var to = (vertex: vertices[segment.end].position, tangent: segment.tangentEnd)
        if reversed { swap(&from, &to) }
        if segment.isStraight { return .line(to: to.vertex) }
        return .cubic(control1: from.vertex + from.tangent, control2: to.vertex + to.tangent, to: to.vertex)
    }
}
