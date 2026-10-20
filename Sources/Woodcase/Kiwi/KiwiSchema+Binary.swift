//
//  KiwiSchema+Binary.swift
//  Woodcase
//

import Foundation

public extension KiwiSchema {
    /// Reads and compiles a binary Kiwi schema.
    ///
    /// The grammar: a varint definition count, then for each definition a null-terminated
    /// name, a kind byte (0 enum, 1 struct, 2 message) and a varint field count; for each
    /// field a null-terminated name, a zigzag type number (negative for a native type,
    /// otherwise a definition's index), a flags byte (bit 0: array) and a varint value.
    /// The schema must end with its last definition.
    ///
    /// - Throws: ``KiwiDecodingError`` if the bytes are truncated or malformed, or the
    ///   definitions would not compile (see ``init(definitions:)``).
    init(binary data: Data) throws(KiwiDecodingError) {
        var reader = KiwiByteReader(data)
        let definitionCount = try reader.readCount()
        var raw: [(name: String, kind: KiwiDefinition.Kind, fields: [(field: KiwiField, type: Int32)])] = []
        raw.reserveCapacity(definitionCount)
        for _ in 0 ..< definitionCount {
            let name = try reader.readString()
            let kindByte = try reader.readByte()
            guard let kind = KiwiDefinition.Kind(rawValue: kindByte) else {
                throw .invalidDefinitionKind(definition: name, kind: kindByte)
            }
            let fieldCount = try reader.readCount()
            var fields: [(field: KiwiField, type: Int32)] = []
            fields.reserveCapacity(fieldCount)
            for _ in 0 ..< fieldCount {
                let fieldName = try reader.readString()
                let type = try reader.readVarInt()
                let isArray = try reader.readByte() & 1 == 1
                let value = try reader.readVarUInt()
                fields.append((KiwiField(name: fieldName, type: nil, isArray: isArray, value: value), type))
            }
            raw.append((name, kind, fields))
        }
        guard reader.isAtEnd else { throw .trailingBytes(count: reader.remainingCount) }

        let names = raw.map(\.name)
        var definitions: [KiwiDefinition] = []
        definitions.reserveCapacity(raw.count)
        for entry in raw {
            var fields: [KiwiField] = []
            fields.reserveCapacity(entry.fields.count)
            for (field, type) in entry.fields {
                var resolved = field
                if entry.kind != .enumeration {
                    resolved.type = try Self.resolve(type, in: names, definition: entry.name, field: field.name)
                }
                fields.append(resolved)
            }
            definitions.append(KiwiDefinition(name: entry.name, kind: entry.kind, fields: fields))
        }
        try self.init(definitions: definitions)
    }

    /// The field type a binary type number names.
    private static func resolve(
        _ type: Int32,
        in names: [String],
        definition: String,
        field: String
    ) throws(KiwiDecodingError) -> KiwiFieldType {
        if type < 0 {
            let native = Int(~type)
            guard native < KiwiFieldType.nativeTypes.count else {
                throw .invalidFieldType(definition: definition, field: field, type: type)
            }
            return KiwiFieldType.nativeTypes[native]
        }
        guard Int(type) < names.count else {
            throw .invalidFieldType(definition: definition, field: field, type: type)
        }
        return .definition(names[Int(type)])
    }
}
