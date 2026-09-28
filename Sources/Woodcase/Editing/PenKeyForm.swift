//
//  PenKeyForm.swift
//  Woodcase
//

import Foundation

/// Where a property's value lands in the .pen file.
///
/// Almost every property is written under a key of its own, and the schema's `.pen key`
/// column prints that key. A `ref`'s root overrides are the exception: the format spreads
/// them across the ref node's own top-level keys, so `rootOverrides` is a name the codec
/// has and the file does not. Printing it in a column headed `.pen key` invites a caller
/// to write it, and a literal `rootOverrides` key is swept straight back into the
/// overrides as an override *named* `rootOverrides` — one that patches a property no node
/// has. Naming the two forms apart is what keeps the schema honest about that.
public enum PenKeyForm: Friendly {
    /// The value is written under this key.
    case key(String)

    /// The value has no key of its own: it is spread across the node's top-level keys.
    case inlined

    /// The key the file writes, or `nil` when the value is inlined.
    public var written: String? {
        guard case let .key(key) = self else { return nil }
        return key
    }

    /// What the schema's `.pen key` column prints.
    public var column: String {
        switch self {
        case let .key(key): key
        case .inlined: "(top-level keys)"
        }
    }
}
