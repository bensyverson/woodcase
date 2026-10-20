//
//  KiwiRecord.swift
//  Woodcase
//

/// A decoded struct or message: its definition's name and the fields it carried.
///
/// A struct carries every field its definition declares; a message only those that were
/// encoded, so an absent key means the field was not sent.
public struct KiwiRecord: Friendly {
    /// The name of the definition this record was decoded as.
    public var typeName: String
    /// The decoded fields, by field name.
    public var fields: [String: KiwiValue]

    /// A record of the given definition name and fields.
    public init(typeName: String, fields: [String: KiwiValue]) {
        self.typeName = typeName
        self.fields = fields
    }

    /// The value of the named field, or `nil` when the record does not carry it.
    public subscript(field: String) -> KiwiValue? {
        fields[field]
    }
}
