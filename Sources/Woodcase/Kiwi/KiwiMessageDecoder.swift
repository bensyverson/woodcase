//
//  KiwiMessageDecoder.swift
//  Woodcase
//

/// Decodes one encoded value against a compiled schema, tracking nesting depth.
///
/// Recursion only enters a struct or message, and every entry counts against
/// `maxDepth`, so a hostile schema or payload fails with a typed error long before the
/// stack would.
struct KiwiMessageDecoder {
    /// The schema the bytes are decoded against.
    let schema: KiwiSchema
    /// The deepest nesting allowed, counting the root as one.
    let maxDepth: Int
    /// The bytes being decoded.
    var reader: KiwiByteReader
    /// How many structs and messages enclose the current read.
    private var depth = 0

    /// A decoder over `reader` for `schema`.
    init(schema: KiwiSchema, reader: KiwiByteReader, maxDepth: Int) {
        self.schema = schema
        self.reader = reader
        self.maxDepth = maxDepth
    }

    /// Decodes the struct or message at definition `index`.
    mutating func record(at index: Int) throws(KiwiDecodingError) -> KiwiRecord {
        depth += 1
        defer { depth -= 1 }
        guard depth <= maxDepth else { throw .depthLimitExceeded(limit: maxDepth) }
        let definition = schema.definitions[index]
        var fields: [String: KiwiValue] = [:]
        switch definition.kind {
        case .structure:
            for field in definition.fields {
                fields[field.name] = try value(of: field, in: definition.name)
            }
        case .message:
            while true {
                let start = reader.offset
                let id = try reader.readVarUInt()
                if id == 0 { break }
                guard let fieldIndex = schema.fieldIndexByValue[index][id] else {
                    throw .unknownField(message: definition.name, value: id, offset: start)
                }
                let field = definition.fields[fieldIndex]
                fields[field.name] = try value(of: field, in: definition.name)
            }
        case .enumeration:
            throw .enumerationRoot(definition.name)
        }
        return KiwiRecord(typeName: definition.name, fields: fields)
    }

    /// Decodes one field's value, or its array of values.
    private mutating func value(of field: KiwiField, in definition: String) throws(KiwiDecodingError) -> KiwiValue {
        guard let type = field.type else {
            // Unreachable: compilation refuses a struct or message field without a type.
            throw .missingFieldType(definition: definition, field: field.name)
        }
        guard field.isArray else { return try value(of: type) }
        if type == .byte { return try .bytes(reader.readByteArray()) }
        let count = try reader.readCount()
        var values: [KiwiValue] = []
        values.reserveCapacity(count)
        for _ in 0 ..< count {
            try values.append(value(of: type))
        }
        return .array(values)
    }

    /// Decodes one value of `type`.
    private mutating func value(of type: KiwiFieldType) throws(KiwiDecodingError) -> KiwiValue {
        switch type {
        case .bool: return try .bool(reader.readBool())
        case .byte: return try .byte(reader.readByte())
        case .int: return try .int(reader.readVarInt())
        case .uint: return try .uint(reader.readVarUInt())
        case .float: return try .float(reader.readVarFloat())
        case .string: return try .string(reader.readString())
        case .int64: return try .int64(reader.readVarInt64())
        case .uint64: return try .uint64(reader.readVarUInt64())
        case let .definition(name):
            guard let index = schema.indexByName[name] else { throw .unknownType(name) }
            switch schema.definitions[index].kind {
            case .enumeration: return try enumeration(at: index)
            case .structure: return try .structure(record(at: index))
            case .message: return try .message(record(at: index))
            }
        }
    }

    /// Decodes an enum value of definition `index` to its case name.
    private mutating func enumeration(at index: Int) throws(KiwiDecodingError) -> KiwiValue {
        let start = reader.offset
        let raw = try reader.readVarUInt()
        let definition = schema.definitions[index]
        guard let caseIndex = schema.fieldIndexByValue[index][raw] else {
            throw .unknownEnumValue(enumeration: definition.name, value: raw, offset: start)
        }
        return .enumeration(definition.fields[caseIndex].name)
    }
}
