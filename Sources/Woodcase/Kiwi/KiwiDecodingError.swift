//
//  KiwiDecodingError.swift
//  Woodcase
//

/// Why a Kiwi schema or message could not be decoded.
///
/// Every failure of ``KiwiByteReader``, ``KiwiSchema`` and ``KiwiSchema/decode(_:as:maxDepth:)``
/// is one of these: untrusted input never traps, and never decodes to a partial value.
/// Offsets are byte offsets into the input that was being read.
public enum KiwiDecodingError: Error, Friendly {
    /// The input ended inside the value that starts at `offset`.
    case truncated(offset: Int)
    /// The varint at `offset` runs past the bytes its width allows.
    case malformedVarint(offset: Int)
    /// The count or length at `offset` is larger than the bytes left to hold it.
    case countExceedsRemainingBytes(count: UInt32, offset: Int)
    /// `count` bytes remain after the value that should have ended the input.
    case trailingBytes(count: Int)

    /// A binary schema gave a definition a kind other than enum, struct or message.
    case invalidDefinitionKind(definition: String, kind: UInt8)
    /// A binary schema gave a field a type number that names neither a native type nor a
    /// definition.
    case invalidFieldType(definition: String, field: String, type: Int32)
    /// A field's type names a definition the schema does not contain.
    case undefinedFieldType(definition: String, field: String, type: String)
    /// A struct or message field has no type.
    case missingFieldType(definition: String, field: String)
    /// Two definitions share a name.
    case duplicateDefinition(String)
    /// Two fields of one definition share a name.
    case duplicateFieldName(definition: String, field: String)
    /// Two fields of one definition share a value (a message's field id, or an enum's case).
    case duplicateFieldValue(definition: String, value: UInt32)
    /// A struct contains itself, directly or through other structs, so it has no finite
    /// encoding.
    case recursiveStruct(String)

    /// The requested root names no definition in the schema.
    case unknownType(String)
    /// The requested root is an enum; only a struct or a message can be decoded on its own.
    case enumerationRoot(String)
    /// A message carries a field id, at `offset`, that its definition does not declare.
    case unknownField(message: String, value: UInt32, offset: Int)
    /// An enum value, at `offset`, that its definition does not declare.
    case unknownEnumValue(enumeration: String, value: UInt32, offset: Int)
    /// Structs and messages nest deeper than the decoder allows.
    case depthLimitExceeded(limit: Int)
}
