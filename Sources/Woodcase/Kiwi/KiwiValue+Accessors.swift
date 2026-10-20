//
//  KiwiValue+Accessors.swift
//  Woodcase
//

import Foundation

public extension KiwiValue {
    /// The record of a struct or message, or `nil` for any other value.
    var recordValue: KiwiRecord? {
        switch self {
        case let .structure(record), let .message(record): record
        default: nil
        }
    }

    /// The named field of a struct or message, or `nil` when this is not a record or the
    /// record does not carry the field.
    subscript(field: String) -> KiwiValue? {
        recordValue?[field]
    }

    /// The elements of an array, or `nil` for any other value.
    var arrayValue: [KiwiValue]? {
        if case let .array(values) = self { values } else { nil }
    }

    /// The bytes of a `byte[]`, or `nil` for any other value.
    var bytesValue: Data? {
        if case let .bytes(data) = self { data } else { nil }
    }

    /// The string, or `nil` for any other value.
    var stringValue: String? {
        if case let .string(string) = self { string } else { nil }
    }

    /// The enum case name, or `nil` for any other value.
    var enumName: String? {
        if case let .enumeration(name) = self { name } else { nil }
    }

    /// The bool, or `nil` for any other value.
    var boolValue: Bool? {
        if case let .bool(value) = self { value } else { nil }
    }

    /// The float, or `nil` for any other value.
    var floatValue: Float? {
        if case let .float(value) = self { value } else { nil }
    }

    /// The `uint`, or `nil` for any other value.
    var uintValue: UInt32? {
        if case let .uint(value) = self { value } else { nil }
    }

    /// The `int`, or `nil` for any other value.
    var intValue: Int32? {
        if case let .int(value) = self { value } else { nil }
    }
}
