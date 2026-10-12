//
//  PenTextRun+StyleKey.swift
//  Woodcase
//

import Foundation

public extension PenTextRun {
    /// A key a run sets: every stored property of ``PenTextRun`` but its offsets.
    ///
    /// This is the one list of a run's keys. Overlaying runs, clearing a key, comparing
    /// keys and flattening (``overlaid(by:)``, ``clear(_:)``, ``PenFlatTextRuns``) all walk
    /// it, so a key added here reaches every one of them; and a property added to the
    /// struct without a case here fails `PenTextRunKeysTests`. Each case is spelled as
    /// its property.
    enum StyleKey: String, Friendly, CaseIterable {
        /// ``PenTextRun/fontFamily``.
        case fontFamily
        /// ``PenTextRun/fontSize``.
        case fontSize
        /// ``PenTextRun/fontWeight``.
        case fontWeight
        /// ``PenTextRun/isItalic``.
        case isItalic
        /// ``PenTextRun/fill``.
        case fill
        /// ``PenTextRun/underline``.
        case underline
        /// ``PenTextRun/strikethrough``.
        case strikethrough
        /// ``PenTextRun/mention``.
        case mention
        /// ``PenTextRun/inlinePadding``.
        case inlinePadding

        /// The key `metadata.woodcase.spans` stores this one under, or `nil` for a key a
        /// text node's spans cannot set.
        public var wireKey: WireKey? {
            switch self {
            case .fontFamily: .fontFamily
            case .fontSize: .fontSize
            case .fontWeight: .fontWeight
            case .isItalic: .fontStyle
            case .fill: .fill
            case .underline: .underline
            case .strikethrough: .strikethrough
            case .mention: .mention
            case .inlinePadding: nil
            }
        }

        /// The property this key names, reached without knowing its type.
        fileprivate var field: Field {
            switch self {
            case .fontFamily: Field(\.fontFamily)
            case .fontSize: Field(\.fontSize)
            case .fontWeight: Field(\.fontWeight)
            case .isItalic: Field(\.isItalic)
            case .fill: Field(\.fill)
            case .underline: Field(\.underline)
            case .strikethrough: Field(\.strikethrough)
            case .mention: Field(\.mention)
            case .inlinePadding: Field(\.inlinePadding)
            }
        }
    }

    /// Whether the run sets `key`, rather than inheriting the node's.
    ///
    /// - Parameter key: The key.
    /// - Returns: `true` when the key's property is not `nil`.
    func sets(_ key: StyleKey) -> Bool {
        key.field.isSet(self)
    }

    /// Unsets `key`, so the run inherits the node's value for it.
    ///
    /// - Parameter key: The key.
    mutating func clear(_ key: StyleKey) {
        key.field.clear(&self)
    }

    /// The run with `key` unset.
    ///
    /// - Parameter key: The key.
    /// - Returns: A copy that inherits the node's value for `key`.
    func clearing(_ key: StyleKey) -> PenTextRun {
        var run = self
        run.clear(key)
        return run
    }

    /// The run with `key` as `other` has it, set or not.
    ///
    /// - Parameters:
    ///   - key: The key.
    ///   - other: The run to take it from.
    /// - Returns: A copy holding `other`'s value for `key`.
    func taking(_ key: StyleKey, from other: PenTextRun) -> PenTextRun {
        var run = self
        key.field.copy(&run, other)
        return run
    }
}

/// One of a run's optional properties, read and written whatever its type.
private struct Field {
    /// Whether the property is set on a run.
    let isSet: (PenTextRun) -> Bool
    /// Unsets the property on a run.
    let clear: (inout PenTextRun) -> Void
    /// Sets the property on the first run to the second run's value.
    let copy: (inout PenTextRun, PenTextRun) -> Void

    /// The field a key path names.
    init(_ path: WritableKeyPath<PenTextRun, (some Any)?>) {
        isSet = { $0[keyPath: path] != nil }
        clear = { $0[keyPath: path] = nil }
        copy = { $0[keyPath: path] = $1[keyPath: path] }
    }
}
