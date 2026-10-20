//
//  KiwiFieldType.swift
//  Woodcase
//

/// The type of a struct or message field: one of Kiwi's eight native types, or another
/// definition in the same schema.
public enum KiwiFieldType: Friendly {
    /// One byte, true when not zero.
    case bool
    /// One raw byte. An array of bytes decodes as ``KiwiValue/bytes(_:)``.
    case byte
    /// A zigzag varint holding a 32-bit signed integer.
    case int
    /// A varint holding a 32-bit unsigned integer.
    case uint
    /// A 32-bit float in Kiwi's exponent-first encoding.
    case float
    /// A null-terminated UTF-8 string.
    case string
    /// A zigzag varint holding a 64-bit signed integer.
    case int64
    /// A varint holding a 64-bit unsigned integer.
    case uint64
    /// The enum, struct or message of this name.
    case definition(String)

    /// The native types in the order a binary schema numbers them: type `-1` is the first,
    /// `-8` the last.
    static let nativeTypes: [KiwiFieldType] = [.bool, .byte, .int, .uint, .float, .string, .int64, .uint64]
}
