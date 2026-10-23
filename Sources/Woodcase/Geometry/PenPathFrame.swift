import Foundation

/// What a `path` node writes for a drawn path: its box (`x`, `y`, `width`, `height`), its
/// `viewBox`, and its `geometry` in node-local coordinates — and the anchors read back from
/// those.
///
/// The pen tool works in the parent's space: ``init(contours:precision:)`` takes anchors
/// there and places the node. The box is the drawn extent of the path (control points that
/// the curve never reaches don't count), widened outward to the next hundredth of a point,
/// and the geometry is the path moved so the box's corner is its origin. When the box has
/// both a width and a height, the frame writes the viewBox `[0, 0, width, height]`, so the
/// geometry maps onto the box one to one without anyone recomputing the path's bounds. A
/// straight horizontal or vertical path has no extent across itself, and a viewBox with a
/// zero side is unusable (``PenViewBox/isUsable``), so it writes none: Pen's default then
/// maps the geometry's drawn extent onto the box, and the frame makes that extent and the
/// box the same size, so the mapping is a translation — Woodcase and Pen both draw a
/// horizontal path with no viewBox and height 0 on its box's top edge (pen CLI, 2026-10-23).
///
/// Every coordinate written is kept to a hundredth of a point (``precision``), and reading
/// back keeps the anchors to the same grid, so writing what was read gives the same node
/// properties however many times the tool commits: anchors on the grid read back exactly,
/// and anchors off it are moved onto it by the first write and stay there.
///
/// The box is in the node's parent space before the node's rotation and flip; an editor
/// working on a turned node maps its points through the node's transform first.
///
/// ```swift
/// let frame = PenPathFrame(contours: [PenPathContour(anchors: [a, b], isClosed: false)])!
/// // write frame.x, frame.y, frame.width, frame.height, frame.viewBox and frame.geometry
/// ```
public struct PenPathFrame: Friendly {
    /// The node's left edge in its parent's space.
    public var x: Double
    /// The node's top edge in its parent's space.
    public var y: Double
    /// The node's width; zero for a straight vertical path.
    public var width: Double
    /// The node's height; zero for a straight horizontal path.
    public var height: Double
    /// The node's viewBox, or `nil` when the box has no extent on an axis.
    public var viewBox: PenViewBox?
    /// The node's geometry, in node-local coordinates (the viewBox's space when there is one).
    public var path: PenPath

    /// How finely coordinates are kept: hundredths of a point, as a scale keeps a length
    /// (``PenScaleRounding/lengthPrecision``).
    public static let precision = PenScaleRounding.lengthPrecision

    /// Creates a frame from a node's laid-out box, viewBox and parsed geometry.
    public init(x: Double, y: Double, width: Double, height: Double, viewBox: PenViewBox?, path: PenPath) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.viewBox = viewBox
        self.path = path
    }

    /// Creates a frame from a node's laid-out box, viewBox and geometry string, or `nil` when
    /// the geometry does not parse.
    public init?(x: Double, y: Double, width: Double, height: Double, viewBox: PenViewBox?, geometry: String) {
        guard let path = PenPath(svg: geometry) else { return nil }
        self.init(x: x, y: y, width: width, height: height, viewBox: viewBox, path: path)
    }

    /// Places anchors drawn in the parent's space: the box, viewBox and node-local geometry
    /// a path node writes. `nil` when there are no anchors.
    ///
    /// - Parameters:
    ///   - contours: The anchors, in the parent's space.
    ///   - precision: Coordinates are kept to `1 / precision` of a point.
    public init?(contours: [PenPathContour], precision: Double = PenPathFrame.precision) {
        self.init(path: PenPath(contours: contours), precision: precision)
    }

    /// Places geometry drawn in the parent's space: the box, viewBox and node-local geometry
    /// a path node writes. `nil` when the path has no points.
    ///
    /// - Parameters:
    ///   - path: The geometry, in the parent's space.
    ///   - precision: Coordinates are kept to `1 / precision` of a point.
    public init?(path: PenPath, precision: Double = PenPathFrame.precision) {
        let grid = Grid(precision: precision)
        let drawn = path.mappingPoints(grid.snapped)
        guard let bounds = drawn.tightBounds else { return nil }
        let origin = PenPoint(x: grid.floor(bounds.x), y: grid.floor(bounds.y))
        let width = grid.snapped(grid.ceil(bounds.maxX) - origin.x)
        let height = grid.snapped(grid.ceil(bounds.maxY) - origin.y)
        let local = drawn.mappingPoints { grid.snapped(PenPoint(x: $0.x - origin.x, y: $0.y - origin.y)) }

        if width > 0, height > 0 {
            self.init(
                x: origin.x, y: origin.y, width: width, height: height,
                viewBox: PenViewBox(x: 0, y: 0, width: width, height: height), path: local
            )
            return
        }
        // No viewBox: the geometry's drawn extent is what fills the box, so the box is
        // exactly that extent — snapping it would stretch the path by the rounding.
        guard let extent = local.tightBounds else { return nil }
        self.init(
            x: origin.x + extent.x, y: origin.y + extent.y, width: extent.width, height: extent.height,
            viewBox: nil, path: local
        )
    }

    /// The node's geometry as SVG path data, which parses back to ``path`` exactly.
    public var geometry: String {
        path.svgPathData
    }

    /// The anchors in the parent's space: the geometry mapped onto the box as Pen draws it
    /// (``PenPath/mapped(onto:viewBox:)``), as contours, each coordinate kept to the grid.
    ///
    /// - Parameter precision: Coordinates are kept to `1 / precision` of a point.
    public func contours(precision: Double = PenPathFrame.precision) -> [PenPathContour] {
        let grid = Grid(precision: precision)
        let box = PenRect(x: x, y: y, width: width, height: height)
        return path.mapped(onto: box, viewBox: viewBox).mappingPoints(grid.snapped).contours
    }

    /// Rounding to multiples of `1 / precision`.
    private struct Grid {
        let precision: Double

        /// A value scaled to grid units within this of a whole number is on the grid: the
        /// `Double` nearest a hundredth, times 100, lands a few ulps either side of it.
        private static let onGrid = 1e-6

        func snapped(_ value: Double) -> Double {
            (value * precision).rounded() / precision
        }

        func snapped(_ point: PenPoint) -> PenPoint {
            PenPoint(x: snapped(point.x), y: snapped(point.y))
        }

        /// The grid value at or below `value`, treating a value on the grid as on it.
        func floor(_ value: Double) -> Double {
            let units = value * precision
            let nearest = units.rounded()
            return (abs(units - nearest) < Self.onGrid ? nearest : units.rounded(.down)) / precision
        }

        /// The grid value at or above `value`, treating a value on the grid as on it.
        func ceil(_ value: Double) -> Double {
            let units = value * precision
            let nearest = units.rounded()
            return (abs(units - nearest) < Self.onGrid ? nearest : units.rounded(.up)) / precision
        }
    }
}
