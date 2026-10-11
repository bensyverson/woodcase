//
//  PenMetadata+TextSpans.swift
//  Woodcase
//

import Foundation

public extension PenMetadata {
    /// A text node's spans, read from and written to `metadata.woodcase.spans` through
    /// ``subscript(woodcase:)`` — their one source of truth.
    ///
    /// Reading answers `nil` when the key is absent or holds something
    /// ``PenTextSpans/init(metadataValue:)`` refuses, so unreadable spans draw plain.
    /// Writing stores the wire form (``PenTextSpans/metadataValue``) and types metadata that
    /// had no type; writing `nil` removes the key.
    var textSpans: PenTextSpans? {
        get {
            guard let value = self[woodcase: .spans] else { return nil }
            return try? PenTextSpans(metadataValue: value)
        }
        set {
            self[woodcase: .spans] = newValue?.metadataValue
        }
    }
}
