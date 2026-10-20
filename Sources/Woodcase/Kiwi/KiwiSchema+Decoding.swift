//
//  KiwiSchema+Decoding.swift
//  Woodcase
//

import Foundation

public extension KiwiSchema {
    /// Decodes `data` as one value of the struct or message named `rootType`.
    ///
    /// Kiwi does not record which definition a buffer holds; the caller names it, as
    /// with the reference implementation's per-definition decoders. The value must end
    /// exactly where `data` does.
    ///
    /// - Parameters:
    ///   - data: The encoded value.
    ///   - rootType: The name of the struct or message it encodes.
    ///   - maxDepth: The deepest nesting of structs and messages to follow, counting the
    ///     root as one.
    /// - Throws: ``KiwiDecodingError`` if `rootType` is not a struct or message in this
    ///   schema, or the bytes are truncated, malformed, nest too deeply, or run on past
    ///   the value.
    func decode(
        _ data: Data,
        as rootType: String,
        maxDepth: Int = KiwiSchema.defaultMaxDepth
    ) throws(KiwiDecodingError) -> KiwiRecord {
        guard let index = indexByName[rootType] else { throw .unknownType(rootType) }
        guard definitions[index].kind != .enumeration else { throw .enumerationRoot(rootType) }
        var decoder = KiwiMessageDecoder(schema: self, reader: KiwiByteReader(data), maxDepth: maxDepth)
        let record = try decoder.record(at: index)
        guard decoder.reader.isAtEnd else { throw .trailingBytes(count: decoder.reader.remainingCount) }
        return record
    }
}
