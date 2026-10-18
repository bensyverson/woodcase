//
//  CodeGenerationError.swift
//  Woodcase
//

/// Why ``CodeGeneration`` cannot generate code for a node.
public enum CodeGenerationError: Error, Friendly {
    /// No node in the document has the id.
    case nodeNotFound(id: String)

    /// The node is neither a root of the document nor a component: a layer inside
    /// another. Copy it into a ``PenClip`` first, which makes it a root.
    case notADefinition(id: String)
}
