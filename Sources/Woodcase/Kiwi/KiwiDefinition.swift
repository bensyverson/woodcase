//
//  KiwiDefinition.swift
//  Woodcase
//

/// One named definition in a Kiwi schema: an enum, a struct or a message.
public struct KiwiDefinition: Friendly {
    /// What a definition is, numbered as a binary schema numbers it.
    public enum Kind: UInt8, Friendly {
        /// Named values, encoded as a varint.
        case enumeration = 0
        /// Fields that are all present, encoded in order without ids.
        case structure = 1
        /// Optional fields, each encoded after its id, ended by a zero id.
        case message = 2
    }

    /// The definition's name, unique in its schema.
    public var name: String
    /// Whether it is an enum, a struct or a message.
    public var kind: Kind
    /// Its fields, or its cases for an enum, in schema order.
    public var fields: [KiwiField]

    /// A definition with the given name, kind and fields.
    public init(name: String, kind: Kind, fields: [KiwiField]) {
        self.name = name
        self.kind = kind
        self.fields = fields
    }

    /// The field, or enum case, with the given name.
    public func field(named name: String) -> KiwiField? {
        fields.first { $0.name == name }
    }
}
