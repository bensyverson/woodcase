import Foundation

/// A point a path passes through, with the handles that shape the curves either side of it.
///
/// Handles are absolute positions in the same space as the point, not offsets from it, so
/// converting to and from geometry copies coordinates and never does arithmetic on them: an
/// anchor list converts to a ``PenPath`` and back unchanged (see ``PenPath/init(contours:)``).
/// A handle that sits exactly on the point is *retracted* — it shapes nothing — and the
/// segment between two anchors is a straight line when both handles that face it are
/// retracted, otherwise a cubic Bézier whose control points are those handles.
///
/// How the two handles relate — ``Kind-swift.enum`` — is read from their positions, since a
/// `.pen` file stores only geometry.
public struct PenPathAnchor: Friendly {
    /// The point the path passes through.
    public var point: PenPoint
    /// The control point of the segment that arrives at this anchor; equal to ``point`` when retracted.
    public var inHandle: PenPoint
    /// The control point of the segment that leaves this anchor; equal to ``point`` when retracted.
    public var outHandle: PenPoint

    /// Creates an anchor. A handle left out is retracted onto the point.
    ///
    /// - Parameters:
    ///   - point: The point the path passes through.
    ///   - inHandle: The incoming segment's control point, or `nil` for none.
    ///   - outHandle: The outgoing segment's control point, or `nil` for none.
    public init(point: PenPoint, inHandle: PenPoint? = nil, outHandle: PenPoint? = nil) {
        self.point = point
        self.inHandle = inHandle ?? point
        self.outHandle = outHandle ?? point
    }

    /// Creates a mirrored anchor — what a pen-tool drag pulls: the in handle is the out
    /// handle reflected through the point.
    ///
    /// - Parameters:
    ///   - point: The point the path passes through.
    ///   - outHandle: Where the drag is; the in handle goes opposite it at the same length.
    public init(point: PenPoint, mirroringOutHandle outHandle: PenPoint) {
        self.init(
            point: point,
            inHandle: PenPoint(x: 2 * point.x - outHandle.x, y: 2 * point.y - outHandle.y),
            outHandle: outHandle
        )
    }

    /// Whether the in handle is extended, i.e. not exactly on the point.
    public var hasInHandle: Bool {
        inHandle != point
    }

    /// Whether the out handle is extended, i.e. not exactly on the point.
    public var hasOutHandle: Bool {
        outHandle != point
    }

    /// The same anchor with its point and both handles passed through `transform`.
    public func mappingPoints(_ transform: (PenPoint) -> PenPoint) -> PenPathAnchor {
        let point = transform(point)
        return PenPathAnchor(
            point: point,
            inHandle: hasInHandle ? transform(inHandle) : point,
            outHandle: hasOutHandle ? transform(outHandle) : point
        )
    }
}
