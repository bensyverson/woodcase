//
//  DeltaValue.swift
//  Woodcase
//

/// The value a ``PropertyChange`` sets: typed where a target needs the parts, and otherwise
/// the diff's pen-level encoding.
public enum DeltaValue: Friendly {
    /// The pen-level value as ``NodeDiffer`` encodes it: a number, a `$variable`, a colour
    /// literal, a sizing keyword, or a summary such as `"multi-fill"` for a value it does
    /// not carry whole.
    case encoded(AnyCodable)

    /// A turn and flips, for ``DeltaProperty/transform``.
    case transform(DeltaTransform)
}
