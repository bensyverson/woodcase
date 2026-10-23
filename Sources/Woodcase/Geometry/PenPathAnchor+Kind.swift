import Foundation

public extension PenPathAnchor {
    /// How an anchor's two handles relate, which decides what dragging one does to the other.
    enum Kind: Friendly {
        /// Neither handle is extended: the path turns sharply here, or runs straight through.
        case corner
        /// Both handles are extended and point opposite ways, at different lengths: the curve
        /// is smooth through the anchor. Dragging one handle turns the other to stay opposite.
        case smooth
        /// A smooth anchor whose handles are also the same length — what a pen-tool drag pulls.
        /// Dragging one handle moves the other to its reflection.
        case mirrored
        /// The handles move independently: both are extended and not opposite, or only one
        /// is extended, so there is no partner to keep in line.
        case broken
    }

    /// How far from exact a handle pair may be and still read as smooth or mirrored.
    ///
    /// Geometry rarely arrives exact: an arc converted to cubics, a Figma import rounded to a
    /// few decimals, or a smooth anchor whose second handle was computed from the first all
    /// land a few ulps — or a few hundredths — off. ``standard`` absorbs that.
    struct KindTolerance: Friendly {
        /// The largest angle, in radians, between the out handle and the reflection of the in
        /// handle for the pair to count as opposite.
        public var angle: Double
        /// The largest difference between the handles' lengths, as a fraction of the longer,
        /// for the pair to count as equal in length.
        public var lengthRatio: Double
        /// A handle closer to its point than this, in points, has no direction to read, so
        /// classification treats it as retracted. Geometry does not: it is still a curve.
        public var retractedLength: Double

        /// Creates a tolerance.
        public init(angle: Double, lengthRatio: Double, retractedLength: Double) {
            self.angle = angle
            self.lengthRatio = lengthRatio
            self.retractedLength = retractedLength
        }

        /// About half a degree, a 1% length difference, and a millionth of a point.
        public static let standard = KindTolerance(angle: 0.01, lengthRatio: 0.01, retractedLength: 1e-6)
    }

    /// How this anchor's handles relate, within ``KindTolerance/standard``.
    var kind: Kind {
        kind(tolerance: .standard)
    }

    /// How this anchor's handles relate, within `tolerance`.
    func kind(tolerance: KindTolerance) -> Kind {
        let incoming = (x: inHandle.x - point.x, y: inHandle.y - point.y)
        let outgoing = (x: outHandle.x - point.x, y: outHandle.y - point.y)
        let inLength = (incoming.x * incoming.x + incoming.y * incoming.y).squareRoot()
        let outLength = (outgoing.x * outgoing.x + outgoing.y * outgoing.y).squareRoot()
        let hasIn = inLength >= tolerance.retractedLength
        let hasOut = outLength >= tolerance.retractedLength
        guard hasIn || hasOut else { return .corner }
        guard hasIn, hasOut else { return .broken }
        // The angle between the out handle and the in handle's reflection through the point.
        let reflected = (x: -incoming.x, y: -incoming.y)
        let cross = reflected.x * outgoing.y - reflected.y * outgoing.x
        let dot = reflected.x * outgoing.x + reflected.y * outgoing.y
        guard abs(atan2(cross, dot)) <= tolerance.angle else { return .broken }
        let difference = abs(inLength - outLength) / max(inLength, outLength)
        return difference <= tolerance.lengthRatio ? .mirrored : .smooth
    }
}
