//
//  KiwiTestBytes.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// A minimal Kiwi byte writer for building hostile and synthetic payloads by hand.
///
/// It writes the encoding the reader's tests expect, independently of the reader, so a
/// test that round-trips through it checks the reader against a second implementation.
struct KiwiTestBytes {
    /// The bytes written so far.
    var bytes: [UInt8] = []

    /// The bytes as `Data`.
    var data: Data {
        Data(bytes)
    }

    /// Appends raw bytes.
    mutating func raw(_ values: UInt8...) {
        bytes += values
    }

    /// Appends an unsigned LEB128 varint; as Kiwi's 64-bit encoding does, the ninth byte,
    /// if reached, carries the last eight bits whole.
    mutating func varUInt(_ value: UInt64) {
        var rest = value
        var written = 0
        repeat {
            if written == 8 {
                bytes.append(UInt8(rest))
                return
            }
            written += 1
            var byte = UInt8(rest & 0x7F)
            rest >>= 7
            if rest != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while rest != 0
    }

    /// Appends a zigzag-encoded signed varint.
    mutating func varInt(_ value: Int64) {
        varUInt(UInt64(bitPattern: (value << 1) ^ (value >> 63)))
    }

    /// Appends a null-terminated UTF-8 string.
    mutating func string(_ value: String) {
        bytes += Array(value.utf8)
        bytes.append(0)
    }

    /// The kinds a binary schema's definition byte names.
    enum Kind: UInt8 {
        case enumeration = 0, structure = 1, message = 2
    }

    /// One field of a hand-built binary schema; `type` is the raw binary type number.
    struct Field {
        var name: String
        var type: Int64
        var isArray = false
        var value: UInt64
    }

    /// Native type numbers as a binary schema stores them.
    enum Native {
        static let bool: Int64 = -1
        static let byte: Int64 = -2
        static let int: Int64 = -3
        static let uint: Int64 = -4
        static let float: Int64 = -5
        static let string: Int64 = -6
        static let int64: Int64 = -7
        static let uint64: Int64 = -8
    }

    /// A binary schema of the given definitions.
    static func schema(_ definitions: [(name: String, kind: UInt8, fields: [Field])]) -> Data {
        var out = KiwiTestBytes()
        out.varUInt(UInt64(definitions.count))
        for definition in definitions {
            out.string(definition.name)
            out.raw(definition.kind)
            out.varUInt(UInt64(definition.fields.count))
            for field in definition.fields {
                out.string(field.name)
                out.varInt(field.type)
                out.raw(field.isArray ? 1 : 0)
                out.varUInt(field.value)
            }
        }
        return out.data
    }
}
