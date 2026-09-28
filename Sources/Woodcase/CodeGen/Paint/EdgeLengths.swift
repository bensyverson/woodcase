//
//  EdgeLengths.swift
//  Woodcase
//

/// One ``SymbolicLength`` per side of a box, clockwise from the top.
struct EdgeLengths: Friendly {
    /// The top side.
    var top: SymbolicLength
    /// The right side.
    var right: SymbolicLength
    /// The bottom side.
    var bottom: SymbolicLength
    /// The left side.
    var left: SymbolicLength

    /// Creates sides from four lengths.
    init(top: SymbolicLength, right: SymbolicLength, bottom: SymbolicLength, left: SymbolicLength) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    /// Creates sides that are all `length`.
    init(all length: SymbolicLength) {
        self.init(top: length, right: length, bottom: length, left: length)
    }

    /// The sides clockwise from the top.
    var all: [SymbolicLength] {
        [top, right, bottom, left]
    }

    /// Whether every side is zero.
    var isZero: Bool {
        all.allSatisfy(\.isZero)
    }

    /// Whether all four sides are the same length.
    var isUniform: Bool {
        all.allSatisfy { $0 == top }
    }

    /// Each side transformed by `transform`.
    func map(_ transform: (SymbolicLength) -> SymbolicLength) -> EdgeLengths {
        EdgeLengths(top: transform(top), right: transform(right), bottom: transform(bottom), left: transform(left))
    }

    /// The side-wise difference.
    static func - (lhs: EdgeLengths, rhs: EdgeLengths) -> EdgeLengths {
        EdgeLengths(
            top: lhs.top - rhs.top,
            right: lhs.right - rhs.right,
            bottom: lhs.bottom - rhs.bottom,
            left: lhs.left - rhs.left
        )
    }
}
