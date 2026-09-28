//
//  SchemaTypeNotFound.swift
//  Woodcase
//

import Foundation

/// A node type name that the .pen format does not have.
///
/// Carries its own sentence, in the house convention: the subject as the caller typed
/// it, what happened, and a remedy with a backticked literal in it. Every route that
/// resolves a type name — the `schema` verb, `help schema`, a script's `doc.schema` —
/// prints this one, so a caller who guessed `textbox` reads the same sixteen names
/// wherever they guessed it.
public struct SchemaTypeNotFound: Error, Friendly {
    /// Names the type that does not exist.
    ///
    /// - Parameter name: The word the caller typed.
    public init(name: String) {
        self.name = name
    }

    /// The name the caller typed.
    public let name: String

    /// The refusal, in one sentence.
    public var message: String {
        """
        \(name) is not a node type in the .pen format — the types are \
        \(PenNode.NodeType.allCases.map(\.rawValue).joined(separator: ", ")); \
        run `woodcase schema` to list them with what each one is for.
        """
    }
}
