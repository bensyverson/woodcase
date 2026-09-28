//
//  PenFill+MeshGradientFill.swift
//  Woodcase
//

import Foundation

public extension PenFill {
    /// A mesh gradient: a `columns × rows` grid of coloured vertices joined by
    /// Bézier patches.
    ///
    /// The grid is row-major: ``points`` and ``colors`` each hold one entry per vertex,
    /// left to right and then top to bottom. There is no per-patch data; each patch is
    /// shaped by the handles of its four corner vertices (see ``PenMeshPoint``).
    ///
    /// Every key is optional because Pen writes and tolerates a mesh without them. Pen
    /// is expected to drop the whole fill unless `columns`, `rows`, `points` and
    /// `colors` are all present and `points.count == colors.count == columns × rows`
    /// (inferred, not yet measured; `project/2026-09-26-mesh-gradients.md` §1).
    ///
    /// Woodcase models the fill in full and round-trips it losslessly. The CoreGraphics
    /// renderer draws it as a raster from the mesh core (<doc:PenMeshGradients>); the
    /// React emitter bakes it to a small PNG, and the SwiftUI emitter writes SwiftUI's
    /// native `MeshGradient` (<doc:PenCodeGen>).
    struct PenMeshGradientFill: Friendly {
        /// Creates a mesh gradient fill.
        ///
        /// - Parameters:
        ///   - enabled: Whether the fill is painted.
        ///   - blendMode: How the fill composites onto what is under it.
        ///   - opacity: The fill's own opacity, on top of the node's.
        ///   - columns: The vertex count across.
        ///   - rows: The vertex count down.
        ///   - colors: One colour per vertex, row-major.
        ///   - points: One vertex per grid position, row-major.
        ///   - extras: Keys a file wrote on the fill that the model does not claim.
        public init(
            enabled: PenValue<Bool>? = nil,
            blendMode: PenBlendMode? = nil,
            opacity: PenValue<Double>? = nil,
            columns: Int? = nil,
            rows: Int? = nil,
            colors: [PenValue<String>]? = nil,
            points: [PenMeshPoint]? = nil,
            extras: PenExtras = PenExtras()
        ) {
            self.enabled = enabled
            self.blendMode = blendMode
            self.opacity = opacity
            self.columns = columns
            self.rows = rows
            self.colors = colors
            self.points = points
            self.extras = extras
        }

        /// Whether the fill is painted.
        public var enabled: PenValue<Bool>?

        /// How the fill composites onto what is under it.
        public var blendMode: PenBlendMode?

        /// The fill's own opacity, on top of the node's.
        public var opacity: PenValue<Double>?

        /// The vertex count across.
        public var columns: Int?

        /// The vertex count down.
        public var rows: Int?

        /// One colour per vertex, row-major: a colour string or a `$variable`.
        public var colors: [PenValue<String>]?

        /// One vertex per grid position, row-major, each in the form it was written — a
        /// point in neither wire form is kept as ``PenMeshPoint/malformed(_:)``.
        public var points: [PenMeshPoint]?

        /// Keys the file wrote on this fill that the model does not claim. See ``PenExtras``.
        public var extras = PenExtras()

        /// The keys this payload claims; any other key of its object is an extra.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case enabled, blendMode, opacity, columns, rows, colors, points
        }

        /// The handles a vertex of this grid takes where it names none, or `nil` while
        /// ``columns`` or ``rows`` is missing.
        public var defaultHandles: PenMeshPoint.Handles? {
            guard let columns, let rows else { return nil }
            return PenMeshPoint.Handles.defaults(columns: columns, rows: rows)
        }

        /// The fill with every point in the form Pen's serialiser writes.
        ///
        /// See ``PenMeshPoint/canonicalized(defaults:)``. A fill missing ``columns`` or
        /// ``rows`` has no defaults to compare against and is returned unchanged.
        ///
        /// - Returns: A copy whose ``points`` are canonical.
        public func canonicalized() -> PenMeshGradientFill {
            guard let defaults = defaultHandles else { return self }
            var result = self
            result.points = points?.map { $0.canonicalized(defaults: defaults) }
            return result
        }
    }
}
