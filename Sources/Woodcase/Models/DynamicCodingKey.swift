//
//  DynamicCodingKey.swift
//  Woodcase
//

import Foundation

/// A string-only `CodingKey` for encoding and decoding dynamic dictionary keys.
///
/// Used by types that need to iterate over or produce arbitrary JSON keys
/// at runtime — for example, ``PenMetadata``, ``PenNode/RefData``, and
/// the unknown node type round-tripping in ``PenNode``.
struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? {
        nil
    }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}
