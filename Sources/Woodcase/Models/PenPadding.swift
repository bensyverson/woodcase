//
//  PenPadding.swift
//  Woodcase
//
//  Created by Claude on 2026-03-22.
//

import Foundation

/// Padding for a .pen container node.
///
/// The .pen format supports three padding forms:
/// - A single number (uniform on all sides)
/// - A 2-element array `[vertical, horizontal]`, as CSS orders them
/// - A 4-element array `[top, right, bottom, left]`
///
/// Each value can be a number or a `$variable` reference.
public enum PenPadding: Friendly {
    /// Same padding on all sides.
    case uniform(PenValue<Double>)
    /// Horizontal and vertical padding.
    case symmetric(h: PenValue<Double>, v: PenValue<Double>)
    /// Individual padding per side.
    case individual(
        top: PenValue<Double>,
        right: PenValue<Double>,
        bottom: PenValue<Double>,
        left: PenValue<Double>
    )
}

// MARK: - Resolved Values

public extension PenPadding {
    /// Resolved padding edges (after variable resolution).
    struct Edges: Friendly {
        public let top: Double
        public let right: Double
        public let bottom: Double
        public let left: Double

        public var horizontal: Double {
            left + right
        }

        public var vertical: Double {
            top + bottom
        }

        public static let zero = Edges(top: 0, right: 0, bottom: 0, left: 0)
    }

    /// Attempts to resolve to concrete edge values.
    /// Returns nil if any edge is still a variable reference.
    func resolve() -> Edges? {
        switch self {
        case let .uniform(value):
            guard let v = value.literalValue else { return nil }
            return Edges(top: v, right: v, bottom: v, left: v)
        case let .symmetric(h, v):
            guard let hv = h.literalValue, let vv = v.literalValue else { return nil }
            return Edges(top: vv, right: hv, bottom: vv, left: hv)
        case let .individual(top, right, bottom, left):
            guard let t = top.literalValue,
                  let r = right.literalValue,
                  let b = bottom.literalValue,
                  let l = left.literalValue
            else { return nil }
            return Edges(top: t, right: r, bottom: b, left: l)
        }
    }
}

// MARK: - Codable

public extension PenPadding {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try single value first (number or "$var")
        if let single = try? container.decode(PenValue<Double>.self) {
            self = .uniform(single)
            return
        }

        // Try array
        let array = try container.decode([PenValue<Double>].self)
        switch array.count {
        case 2:
            // .pen format follows CSS convention: [vertical, horizontal]
            self = .symmetric(h: array[1], v: array[0])
        case 4:
            self = .individual(top: array[0], right: array[1], bottom: array[2], left: array[3])
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "a padding array must hold 2 values [vertical, horizontal] "
                    + "or 4 values [top, right, bottom, left]; this one holds \(array.count)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .uniform(value):
            try container.encode(value)
        case let .symmetric(h, v):
            // .pen format follows CSS convention: [vertical, horizontal]
            try container.encode([v, h])
        case let .individual(top, right, bottom, left):
            try container.encode([top, right, bottom, left])
        }
    }
}
