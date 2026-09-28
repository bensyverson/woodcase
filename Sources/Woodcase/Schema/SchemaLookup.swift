//
//  SchemaLookup.swift
//  Woodcase
//

import Foundation

/// Turns a node type *name* a caller typed into that type, or into the refusal that
/// lists the real ones.
///
/// The sentence lives here rather than in either caller because both `woodcase schema
/// textbox` and a script's `doc.schema('textbox')` have to say the same thing: someone
/// who guessed needs the sixteen real names more than a restatement of the guess.
public enum SchemaLookup {
    /// The node type a caller named.
    ///
    /// - Parameter name: The word after `schema`.
    /// - Returns: The type it names.
    /// - Throws: ``SchemaTypeNotFound`` when the format has no such type.
    public static func type(named name: String) throws -> PenNode.NodeType {
        guard let type = PenSchema.type(named: name) else {
            throw SchemaTypeNotFound(name: name)
        }
        return type
    }
}
