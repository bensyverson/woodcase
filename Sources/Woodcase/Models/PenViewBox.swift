//
//  PenViewBox.swift
//  Woodcase
//

import Foundation

/// The SVG coordinate space a `path` node's geometry is expressed in.
///
/// On the wire a viewBox is the four-element array `[x, y, width, height]`, exactly
/// as in SVG. The region it names is mapped onto the node's box: translated by
/// `(-x, -y)` and scaled by `nodeWidth / width` and `nodeHeight / height`
/// independently, so the stretch is non-uniform and geometry outside the region
/// overflows the node box rather than being clipped.
///
/// A path node with no viewBox keeps the format's default: the tight bounding box of the
/// geometry is stretched to fill the node box.
public struct PenViewBox: Friendly {
    /// Creates a viewBox from its origin and size in SVG user units.
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The left edge of the visible region, in the geometry's own coordinates.
    public var x: Double
    /// The top edge of the visible region, in the geometry's own coordinates.
    public var y: Double
    /// The width of the visible region, in the geometry's own coordinates.
    public var width: Double
    /// The height of the visible region, in the geometry's own coordinates.
    public var height: Double

    /// Whether the region has a positive extent on both axes and can be mapped onto a node box.
    public var isUsable: Bool {
        width > 0 && height > 0
    }

    /// The four components in wire order: `x`, `y`, `width`, `height`.
    public var components: [Double] {
        [x, y, width, height]
    }

    /// The value of an SVG `viewBox` attribute, with whole numbers written without a decimal point.
    public var svgValue: String {
        components.map { value in
            // `Int(_:)` traps on a value it cannot represent, and nothing validates
            // the magnitudes a .pen file declares.
            guard value.isFinite, value == value.rounded(), value.magnitude < 1e15 else {
                return String(value)
            }
            return String(Int(value))
        }.joined(separator: " ")
    }

    /// The number of components in the wire representation.
    private static let componentCount = 4

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [Double] = []
        while !container.isAtEnd {
            try values.append(container.decode(Double.self))
        }
        guard values.count == Self.componentCount else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "A viewBox must be [x, y, width, height]; found \(values.count) values"
            ))
        }
        self.init(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for value in components {
            try container.encode(value)
        }
    }
}
