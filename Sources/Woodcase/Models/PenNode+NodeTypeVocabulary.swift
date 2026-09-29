//
//  PenNode+NodeTypeVocabulary.swift
//  Woodcase
//

import Foundation

/// What each node type is, in one phrase.
///
/// A list of sixteen bare words teaches nothing — `context` and `note` and `prompt` all
/// look alike until someone says which of them renders. The phrase is the one piece of
/// the schema no decoder can produce, so it lives here, beside the type it names, rather
/// than as prose in whatever happens to print it.
public extension PenNode.NodeType {
    /// One phrase saying what a node of this type is.
    var summary: String {
        switch self {
        case .frame:
            "a container that lays its children out, with padding, gap and a radius"
        case .group:
            "children moved and transformed together; it has no box of its own"
        case .rectangle:
            "a rectangle, with a radius per corner"
        case .ellipse:
            "an ellipse, or an arc or ring via innerRadius and the two angles"
        case .path:
            "SVG path data, stretched from its viewBox onto the node's box"
        case .polygon:
            "a regular polygon of polygonCount sides"
        case .text:
            "a run of text, with its font, growth behavior and alignment"
        case .note:
            "an authoring note; it is never drawn"
        case .prompt:
            "a prompt and the model it is meant for; it is never drawn"
        case .context:
            "reference text carried with the design; it is never drawn"
        case .icon:
            "one glyph from an icon library, painted like a shape"
        case .script:
            "a sized placeholder for a script; Woodcase never runs it"
        case .browser:
            "an embedded web page; Woodcase never loads it, and draws a placeholder"
        case .ref:
            "an instance of a reusable node, with per-descendant overrides"
        case .line:
            "a straight line; it is drawn by its stroke, and takes no fill"
        case .connection:
            "a connector between anchors on two nodes, drawn by its stroke"
        }
    }
}

public extension PenNode.Kind {
    /// The known node type this kind is, or `nil` for a type the format has and
    /// Woodcase does not.
    var nodeType: PenNode.NodeType? {
        PenNode.NodeType(rawValue: typeName)
    }
}
