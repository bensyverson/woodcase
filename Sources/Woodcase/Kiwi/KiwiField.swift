//
//  KiwiField.swift
//  Woodcase
//

/// One field of a Kiwi definition: a member of a struct or message, or a case of an enum.
public struct KiwiField: Friendly {
    /// The field's name, or the enum case's name.
    public var name: String
    /// The field's type; `nil` for an enum case, which has none.
    public var type: KiwiFieldType?
    /// Whether the field holds an array of `type`.
    public var isArray: Bool
    /// A message field's id, an enum case's value; a struct field's ordinal, unused when
    /// decoding because struct fields are read in order.
    public var value: UInt32

    /// A field with the given name, type, arrayness and value.
    public init(name: String, type: KiwiFieldType?, isArray: Bool, value: UInt32) {
        self.name = name
        self.type = type
        self.isArray = isArray
        self.value = value
    }
}
