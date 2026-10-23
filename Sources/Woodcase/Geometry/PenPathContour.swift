import Foundation

/// One subpath as a run of anchors: what the pen tool draws between a click and Return, or
/// between a click and closing on the first anchor.
///
/// Segments join consecutive anchors; a closed contour also joins its last anchor back to its
/// first. An open contour's first in handle and last out handle face no segment, so they draw
/// nothing and do not survive a conversion to geometry — an editor that wants them while a
/// path is still being drawn keeps them itself.
public struct PenPathContour: Friendly {
    /// The anchors, in drawing order.
    public var anchors: [PenPathAnchor]
    /// Whether a segment joins the last anchor back to the first.
    public var isClosed: Bool

    /// Creates a contour from its anchors.
    public init(anchors: [PenPathAnchor], isClosed: Bool) {
        self.anchors = anchors
        self.isClosed = isClosed
    }
}
