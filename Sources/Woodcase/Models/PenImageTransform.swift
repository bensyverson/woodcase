//
//  PenImageTransform.swift
//  Woodcase
//

import Foundation

/// An image paint's crop: the .pen `transform` key of an image fill, written
/// `[a, b, c, d, tx, ty]` (format 2.20).
///
/// It maps the image's unit square — (0, 0) at its top-left, (1, 1) at its bottom-right — to
/// the unit square of the crop box: `x' = a·x + c·y + tx`, `y' = b·x + d·y + ty`, the
/// `CGAffineTransform` convention. `[2, 0, 0, 1, -1, 0]` shows the image's right half across
/// the whole crop box. A missing transform is ``identity``: no crop.
public struct PenImageTransform: Friendly {
    /// The x-axis column's x.
    public var a: Double
    /// The x-axis column's y.
    public var b: Double
    /// The y-axis column's x.
    public var c: Double
    /// The y-axis column's y.
    public var d: Double
    /// The translation's x.
    public var tx: Double
    /// The translation's y.
    public var ty: Double

    /// Creates a crop from its six coefficients; the defaults are the identity's.
    ///
    /// - Parameters:
    ///   - a: The x-axis column's x.
    ///   - b: The x-axis column's y.
    ///   - c: The y-axis column's x.
    ///   - d: The y-axis column's y.
    ///   - tx: The translation's x.
    ///   - ty: The translation's y.
    public init(a: Double = 1, b: Double = 0, c: Double = 0, d: Double = 1, tx: Double = 0, ty: Double = 0) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    /// No crop.
    public static let identity = PenImageTransform()

    /// The names of the array's six slots, in the order the file writes them.
    public static let slotNames = ["a", "b", "c", "d", "tx", "ty"]

    /// The same map as a layout-engine transform, which shares its coefficients and convention.
    public var planeTransform: PenLayoutEngine.PlaneTransform {
        PenLayoutEngine.PlaneTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }
}

// MARK: - Codable

public extension PenImageTransform {
    /// Decodes the six-number array `[a, b, c, d, tx, ty]`.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` when the value is not an array of exactly six numbers.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let values = try container.decode([Double].self)
        guard values.count == Self.slotNames.count else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "an image transform is six numbers [a, b, c, d, tx, ty], not \(values.count)"
            )
        }
        self.init(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
    }

    /// Encodes the transform as the six-number array `[a, b, c, d, tx, ty]`.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode([a, b, c, d, tx, ty])
    }
}
