//
//  PenMeshPoint+Placement.swift
//  Woodcase
//

import Foundation

/// Where a vertex is drawn, including one a file wrote in neither wire form.
///
/// Pen never refuses a file over a malformed vertex. Measured with the headless `pen`
/// CLI 0.3.9 (`render-mesh-malformed-points.pen`,
/// `project/2026-09-26-what-pen-drops-from-a-file.md`), it reads one the way its
/// arithmetic falls out:
///
/// - A value that is neither an array nor an object (`"oops"`, `null`, `42`) sits at its
///   grid position with the default handles, and the mesh paints.
/// - An array is read for its first two entries; anything after them is ignored.
/// - An object's `position` or handle that is absent or `null` takes its default: the
///   grid position, or the default handle.
/// - Inside an array, a number is itself, `null` is 0 and a boolean is 0 or 1. Any other
///   entry, a missing second entry, or a `position` or handle that is not an array
///   (`"oops"`, `{}`) leaves Pen nothing to draw with, and it paints nothing for the
///   **whole fill**.
public extension PenMeshPoint {
    /// Where a vertex is drawn: its position and all four handles, resolved.
    struct Placement: Friendly {
        /// Creates a placement.
        ///
        /// - Parameters:
        ///   - position: Where the vertex sits, in the node's unit space.
        ///   - handles: All four handles, relative to `position`.
        public init(position: Vector, handles: Handles) {
            self.position = position
            self.handles = handles
        }

        /// Where the vertex sits, in the node's unit space.
        public var position: Vector

        /// All four handles, relative to ``position``.
        public var handles: Handles
    }

    /// The position of the vertex at `(column, row)` on an undistorted grid, which Pen
    /// gives a vertex that names none.
    ///
    /// A grid of one column or one row divides by one rather than zero.
    ///
    /// - Parameters:
    ///   - column: The vertex column, `0..<columns`.
    ///   - row: The vertex row, `0..<rows`.
    ///   - columns: The mesh's vertex count across.
    ///   - rows: The mesh's vertex count down.
    /// - Returns: `column / (columns − 1)`, `row / (rows − 1)`.
    static func gridPosition(column: Int, row: Int, columns: Int, rows: Int) -> Vector {
        Vector(Double(column) / Double(max(columns - 1, 1)), Double(row) / Double(max(rows - 1, 1)))
    }

    /// Where the renderer draws this vertex, or `nil` when Pen paints nothing for the
    /// whole fill because of it.
    ///
    /// A well-formed vertex is drawn where it says, its omitted handles defaulted. A
    /// ``malformed(_:)`` one is read as Pen reads it; see the rules above.
    ///
    /// - Parameters:
    ///   - gridPosition: The vertex's ``gridPosition(column:row:columns:rows:)``.
    ///   - defaults: The mesh's default handles, from ``Handles/defaults(columns:rows:)``.
    /// - Returns: The vertex's placement, or `nil`.
    func placement(gridPosition: Vector, defaults: Handles) -> Placement? {
        switch self {
        case let .bare(position):
            Placement(position: position, handles: defaults)
        case let .object(object):
            Placement(position: object.position, handles: Handles(
                left: object.leftHandle ?? defaults.left,
                right: object.rightHandle ?? defaults.right,
                top: object.topHandle ?? defaults.top,
                bottom: object.bottomHandle ?? defaults.bottom
            ))
        case let .malformed(raw):
            Self.penPlacement(of: raw, gridPosition: gridPosition, defaults: defaults)
        }
    }

    // MARK: - Pen's reading

    /// Where Pen draws a vertex written as `raw`, or `nil` if it cannot.
    private static func penPlacement(of raw: AnyCodable, gridPosition: Vector, defaults: Handles) -> Placement? {
        switch raw {
        case let .array(entries):
            guard let position = penVector(entries) else { return nil }
            return Placement(position: position, handles: defaults)
        case let .dictionary(object):
            guard let position = member(object["position"], or: gridPosition),
                  let left = member(object["leftHandle"], or: defaults.left),
                  let right = member(object["rightHandle"], or: defaults.right),
                  let top = member(object["topHandle"], or: defaults.top),
                  let bottom = member(object["bottomHandle"], or: defaults.bottom)
            else { return nil }
            return Placement(position: position, handles: Handles(left: left, right: right, top: top, bottom: bottom))
        case .null, .bool, .int, .double, .string:
            return Placement(position: gridPosition, handles: defaults)
        }
    }

    /// An object member Pen reads with a fallback: absent or `null` takes `fallback`, an
    /// array is read as a vector, and anything else is `nil`.
    private static func member(_ value: AnyCodable?, or fallback: Vector) -> Vector? {
        switch value {
        case nil, .null?: fallback
        case let .array(entries)?: penVector(entries)
        default: nil
        }
    }

    /// The first two entries of an array as numbers, or `nil` if either is not one.
    private static func penVector(_ entries: [AnyCodable]) -> Vector? {
        guard entries.count >= 2, let x = penNumber(entries[0]), let y = penNumber(entries[1]) else { return nil }
        return Vector(x, y)
    }

    /// An array entry as Pen's arithmetic reads it: `null` is 0, a boolean 0 or 1, and a
    /// string, array or object is not a number.
    private static func penNumber(_ entry: AnyCodable) -> Double? {
        switch entry {
        case let .int(value): Double(value)
        case let .double(value): value
        case .null: 0
        case let .bool(value): value ? 1 : 0
        case .string, .array, .dictionary: nil
        }
    }
}
