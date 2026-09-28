//
//  DeltaTransform+CSS.swift
//  Woodcase
//

extension DeltaTransform {
    /// The CSS transform functions that draw this turn and these flips, or `nil` when there
    /// is neither — a turn of 0° counts as none.
    ///
    /// Pen turns counter-clockwise and CSS's `rotate()` clockwise, so the angle is negated.
    /// Pen flips a node before it turns it, and CSS applies the rightmost function first, so
    /// the flips follow the turn: `rotate(-25deg) scaleX(-1)`. Where the node turns about is
    /// the caller's `transform-origin` (``TransformPivot``).
    var cssFunctions: String? {
        var parts: [String] = []
        if let rotation, rotation != 0 {
            parts.append("rotate(\(ReactEmitter.cssNumber(-rotation))deg)")
        }
        if flipX {
            parts.append("scaleX(-1)")
        }
        if flipY {
            parts.append("scaleY(-1)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// The value React writes into a state's `transform` custom property: the
    /// ``cssFunctions``, or `none` when the variant is neither turned nor flipped.
    var cssValue: String {
        cssFunctions ?? "none"
    }
}
