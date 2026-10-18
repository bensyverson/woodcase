//
//  EditableDocument+DefaultTextStyle.swift
//  Woodcase
//

import Foundation

/// What an editor reads the document's default text style from (Penumbra spec §6.3, Ben's
/// ruling of 2026-10-18): the marked text, whose live style is the default, and failing
/// that the font-family variable the document's texts already use.
///
/// An editor reads both on every new text and plain-text paste, so each is one walk of
/// the store.
public extension EditableDocument {
    /// The id of the text whose style is the document's default: the first text marked
    /// with ``PenMetadata/WoodcaseKey/defaultTextStyle`` in document order
    /// (``nodeIDsInDocumentOrder()``: roots in order, each subtree depth first).
    ///
    /// Two marks — after a merge or a paste — resolve to the first, so every peer agrees.
    /// A mark on a node that is not a text, or a mark of `false`, does not count.
    ///
    /// ```swift
    /// document.defaultTextStyleNodeID()  // "Body", or nil when no text is marked
    /// ```
    ///
    /// - Returns: The stored id, or `nil` when no text is marked.
    /// - Complexity: O(*n*) in the number of nodes.
    func defaultTextStyleNodeID() -> String? {
        nodeIDsInDocumentOrder().first { id in
            guard let node = node(id: id), case .text = node.kind else { return false }
            return node.common.metadata?[woodcase: .defaultTextStyle] == .bool(true)
        }
    }

    /// The name of the document's first font-family variable: the first string variable,
    /// by name, that some text binds as its `fontFamily` (`"$name"`).
    ///
    /// By name because ``variables`` is keyed by name and keeps no order of its own, so the
    /// file's order is gone once it is read; name order is the one every peer agrees on,
    /// and the order an inspector's picker lists variables in
    /// (``bindableVariables(ofType:at:)``).
    ///
    /// Only a binding counts: a variable is never chosen for its name or its value. The
    /// document's own variables are read, not a library's, and a note's family does not
    /// count. An editor binds a new text's family to it as `"$" + name`.
    ///
    /// ```swift
    /// document.firstFontFamilyVariableName()  // "body", or nil
    /// ```
    ///
    /// - Returns: The variable's name, without `$`, or `nil` when no text binds a string
    ///   variable as its family.
    /// - Complexity: O(*n*) in the number of nodes.
    func firstFontFamilyVariableName() -> String? {
        guard let variables, !variables.isEmpty else { return nil }
        var bound: Set<String> = []
        for node in nodes.values {
            guard case let .text(data) = node.kind, let name = data.fontFamily?.variableName else { continue }
            bound.insert(name)
        }
        return bound.filter { variables[$0]?.type == .string }.min()
    }
}
