//
//  PenCornerRadius.swift
//  Woodcase
//
//  Created by Claude on 2026-03-22.
//

import Foundation

/// Corner radius for a .pen node (frame, rectangle, polygon).
///
/// The .pen format supports two forms:
/// - A single value (uniform radius on all corners)
/// - A 4-element array `[topLeft, topRight, bottomRight, bottomLeft]`
///
/// Each value can be a number or a `$variable` reference.
public enum PenCornerRadius: Friendly {
    /// Same radius on all corners.
    case uniform(PenValue<Double>)
    /// Individual radius per corner.
    case perCorner(
        topLeft: PenValue<Double>,
        topRight: PenValue<Double>,
        bottomRight: PenValue<Double>,
        bottomLeft: PenValue<Double>
    )
}

// MARK: - Resolved Values

public extension PenCornerRadius {
    /// Resolved corner radius values (after variable resolution).
    struct Corners: Friendly {
        public let topLeft: Double
        public let topRight: Double
        public let bottomRight: Double
        public let bottomLeft: Double

        public var isUniform: Bool {
            topLeft == topRight && topRight == bottomRight && bottomRight == bottomLeft
        }

        public static let zero = Corners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
    }

    /// Attempts to resolve to concrete corner values.
    /// Returns nil if any corner is still a variable reference.
    func resolve() -> Corners? {
        switch self {
        case let .uniform(value):
            guard let v = value.literalValue else { return nil }
            return Corners(topLeft: v, topRight: v, bottomRight: v, bottomLeft: v)
        case let .perCorner(topLeft, topRight, bottomRight, bottomLeft):
            guard let tl = topLeft.literalValue,
                  let tr = topRight.literalValue,
                  let br = bottomRight.literalValue,
                  let bl = bottomLeft.literalValue
            else { return nil }
            return Corners(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl)
        }
    }
}

// MARK: - Codable

public extension PenCornerRadius {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try single value first (number or "$var")
        if let single = try? container.decode(PenValue<Double>.self) {
            self = .uniform(single)
            return
        }

        // Try 4-element array
        let array = try container.decode([PenValue<Double>].self)
        guard array.count == 4 else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "a cornerRadius array must hold 4 values "
                    + "[topLeft, topRight, bottomRight, bottomLeft]; this one holds \(array.count)"
            )
        }
        self = .perCorner(topLeft: array[0], topRight: array[1], bottomRight: array[2], bottomLeft: array[3])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .uniform(value):
            try container.encode(value)
        case let .perCorner(topLeft, topRight, bottomRight, bottomLeft):
            try container.encode([topLeft, topRight, bottomRight, bottomLeft])
        }
    }
}
