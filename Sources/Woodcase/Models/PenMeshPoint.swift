//
//  PenMeshPoint.swift
//  Woodcase
//

import Foundation

/// One vertex of a ``PenFill/PenMeshGradientFill``: where it sits, and the Bézier handles
/// that shape the patches around it.
///
/// Every number is in the node's unit space: `[0, 0]` is the top-left corner of its box
/// and `[1, 1]` the bottom-right. A handle is an offset *relative to the position*, in
/// the same units.
///
/// The .pen format writes a vertex in one of two forms, and a point keeps the form it
/// was read in so it is written back unchanged:
///
/// ```json
/// [0.5, 0]                                              // bare: default handles
/// {"position": [0.5, 0], "bottomHandle": [0.25, 0.4]}   // object: omitted handles default
/// ```
///
/// A handle the file omits takes its default, a quarter of a cell along its axis; see
/// ``Handles/defaults(columns:rows:)`` and ``handles(defaults:)``.
/// ``canonicalized(defaults:)`` rewrites a point the way Pen's own serializer would.
///
/// A file can also hold a vertex in neither form — `"oops"`, `[1]`, an object whose
/// `position` is not two numbers. Pen opens such a file, so a file decode keeps the
/// value as ``malformed(_:)`` and writes it back verbatim; authoring input
/// (``PenDecodingMode/authoring``) refuses it. Where the renderer puts any vertex is
/// ``placement(gridPosition:defaults:)``, which follows Pen for a malformed one.
public enum PenMeshPoint: Friendly {
    /// A vertex written as a bare `[x, y]` position; all four handles are the defaults.
    case bare(Vector)

    /// A vertex written as an object, with whichever handles the file named.
    case object(Object)

    /// A vertex a file wrote in neither form, kept exactly as written.
    ///
    /// Only a file decode produces it. Pen places some malformed vertices and refuses to
    /// paint the fill for others; see ``placement(gridPosition:defaults:)``.
    case malformed(AnyCodable)

    /// The vertex's position in the node's unit space, whichever form it was written in,
    /// or `nil` for a ``malformed(_:)`` vertex, which has none of its own.
    public var position: Vector? {
        switch self {
        case let .bare(position): position
        case let .object(object): object.position
        case .malformed: nil
        }
    }

    /// All four handles, with every one the file omitted replaced by its default, or
    /// `nil` for a ``malformed(_:)`` vertex.
    ///
    /// - Parameter defaults: The mesh's default handles, from
    ///   ``Handles/defaults(columns:rows:)``.
    /// - Returns: The handles the renderer should use for this vertex.
    public func handles(defaults: Handles) -> Handles? {
        switch self {
        case .bare:
            defaults
        case let .object(object):
            Handles(
                left: object.leftHandle ?? defaults.left,
                right: object.rightHandle ?? defaults.right,
                top: object.topHandle ?? defaults.top,
                bottom: object.bottomHandle ?? defaults.bottom
            )
        case .malformed:
            nil
        }
    }

    // MARK: - Vector

    /// A pair of numbers, written in the file as a two-element array `[x, y]`.
    ///
    /// Used for both a position and a handle; for a handle the pair is an offset.
    public struct Vector: Friendly {
        /// Creates a vector.
        ///
        /// - Parameters:
        ///   - x: The horizontal component, as a fraction of the node's width.
        ///   - y: The vertical component, as a fraction of the node's height.
        public init(_ x: Double, _ y: Double) {
            self.x = x
            self.y = y
        }

        /// The horizontal component, as a fraction of the node's width.
        public var x: Double

        /// The vertical component, as a fraction of the node's height.
        public var y: Double

        /// Decodes a two-element numeric array.
        ///
        /// - Parameter decoder: The decoder to read from.
        /// - Throws: `DecodingError.dataCorrupted` when the array does not hold exactly
        ///   two numbers.
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let values = try container.decode([Double].self)
            guard values.count == 2 else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "A mesh point position or handle is [x, y]; got \(values.count) numbers"
                )
            }
            self.init(values[0], values[1])
        }

        /// Encodes the vector as `[x, y]`.
        ///
        /// - Parameter encoder: The encoder to write to.
        /// - Throws: Whatever the encoder throws.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode([x, y])
        }
    }

    // MARK: - Object

    /// A vertex written as an object: a position and up to four handles.
    ///
    /// A `nil` handle was absent from the file, and the vertex uses the default there.
    public struct Object: Friendly {
        /// Creates an object-form vertex.
        ///
        /// - Parameters:
        ///   - position: Where the vertex sits.
        ///   - leftHandle: The handle toward the previous column, or `nil` for the default.
        ///   - rightHandle: The handle toward the next column, or `nil` for the default.
        ///   - topHandle: The handle toward the previous row, or `nil` for the default.
        ///   - bottomHandle: The handle toward the next row, or `nil` for the default.
        ///   - extras: Keys a file wrote on the vertex that the model does not claim.
        public init(
            position: Vector,
            leftHandle: Vector? = nil,
            rightHandle: Vector? = nil,
            topHandle: Vector? = nil,
            bottomHandle: Vector? = nil,
            extras: PenExtras = PenExtras()
        ) {
            self.position = position
            self.leftHandle = leftHandle
            self.rightHandle = rightHandle
            self.topHandle = topHandle
            self.bottomHandle = bottomHandle
            self.extras = extras
        }

        /// Where the vertex sits, in the node's unit space.
        public var position: Vector

        /// The handle toward the previous column, relative to ``position``.
        public var leftHandle: Vector?

        /// The handle toward the next column, relative to ``position``.
        public var rightHandle: Vector?

        /// The handle toward the previous row, relative to ``position``.
        public var topHandle: Vector?

        /// The handle toward the next row, relative to ``position``.
        public var bottomHandle: Vector?

        /// Keys the file wrote on this vertex that the model does not claim. See ``PenExtras``.
        public var extras = PenExtras()

        /// The keys a vertex object claims; any other key of its object is an extra.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case position, leftHandle, rightHandle, topHandle, bottomHandle
        }
    }

    // MARK: - Handles

    /// All four handles of a vertex, each one resolved.
    public struct Handles: Friendly {
        /// Creates a full set of handles.
        ///
        /// - Parameters:
        ///   - left: The handle toward the previous column.
        ///   - right: The handle toward the next column.
        ///   - top: The handle toward the previous row.
        ///   - bottom: The handle toward the next row.
        public init(left: Vector, right: Vector, top: Vector, bottom: Vector) {
            self.left = left
            self.right = right
            self.top = top
            self.bottom = bottom
        }

        /// The handle toward the previous column.
        public var left: Vector

        /// The handle toward the next column.
        public var right: Vector

        /// The handle toward the previous row.
        public var top: Vector

        /// The handle toward the next row.
        public var bottom: Vector

        /// The fraction of a cell a default handle reaches along its axis.
        ///
        /// A quarter, not the third a uniform Bézier parametrization would use, so even
        /// an undistorted grid is not parametrized uniformly.
        public static let defaultReach = 0.25

        /// The handles Pen gives a vertex that names none, for a grid of this size.
        ///
        /// A grid of one column or one row divides by one rather than zero.
        ///
        /// - Parameters:
        ///   - columns: The mesh's vertex count across.
        ///   - rows: The mesh's vertex count down.
        /// - Returns: `left`/`right` a quarter of a column's width, `top`/`bottom` a
        ///   quarter of a row's height, pointing away from the vertex.
        public static func defaults(columns: Int, rows: Int) -> Handles {
            let dx = defaultReach / Double(max(columns - 1, 1))
            let dy = defaultReach / Double(max(rows - 1, 1))
            return Handles(
                left: Vector(-dx, 0),
                right: Vector(dx, 0),
                top: Vector(0, -dy),
                bottom: Vector(0, dy)
            )
        }
    }
}

// MARK: - Codable

public extension PenMeshPoint {
    /// Decodes either wire form: a bare `[x, y]` array or an object with a `position`.
    ///
    /// A value in neither form is ``malformed(_:)`` in ``PenDecodingMode/file``, kept as
    /// written, and a decoding error in ``PenDecodingMode/authoring``.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: In authoring mode, the `DecodingError` of the object form when the value
    ///   is neither.
    init(from decoder: Decoder) throws {
        do {
            try self.init(wellFormedFrom: decoder)
        } catch let error as DecodingError {
            guard PenDecodingMode.of(decoder) == .file else { throw error }
            self = try .malformed(AnyCodable(from: decoder))
        }
    }

    /// Decodes a vertex in one of the two wire forms, or throws.
    private init(wellFormedFrom decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let values = try? container.decode([Double].self)
        {
            guard values.count == 2 else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "A bare mesh point is [x, y]; got \(values.count) numbers"
                )
            }
            self = .bare(Vector(values[0], values[1]))
        } else {
            self = try .object(Object(from: decoder))
        }
    }

    /// Encodes the point in the form it holds.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: Encoder) throws {
        switch self {
        case let .bare(position):
            try position.encode(to: encoder)
        case let .object(object):
            try object.encode(to: encoder)
        case let .malformed(raw):
            try raw.encode(to: encoder)
        }
    }
}
