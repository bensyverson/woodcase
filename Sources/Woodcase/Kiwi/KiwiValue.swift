//
//  KiwiValue.swift
//  Woodcase
//

import Foundation

/// A decoded Kiwi value: the schema-independent form a message decodes to.
///
/// Each case matches a ``KiwiFieldType``. An array of bytes decodes to ``bytes(_:)``
/// rather than an ``array(_:)`` of ``byte(_:)``.
public enum KiwiValue: Friendly {
    /// A `bool`.
    case bool(Bool)
    /// A single `byte`.
    case byte(UInt8)
    /// An `int`.
    case int(Int32)
    /// A `uint`.
    case uint(UInt32)
    /// A `float`.
    case float(Float)
    /// A `string`.
    case string(String)
    /// An `int64`.
    case int64(Int64)
    /// A `uint64`.
    case uint64(UInt64)
    /// An enum value, by its case name.
    case enumeration(String)
    /// A `byte[]`.
    case bytes(Data)
    /// An array of any other type.
    case array([KiwiValue])
    /// A struct.
    case structure(KiwiRecord)
    /// A message.
    case message(KiwiRecord)
}
