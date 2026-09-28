//
//  ImportedComponentStore.swift
//  Woodcase
//

import Foundation

/// The components a document's imports define, flattened the way the document's own
/// nodes are, so a walk into a component can step into an imported one.
///
/// ``EditableDocument`` keeps its own nodes in ``EditableDocument/nodes`` and the
/// tree in ``EditableDocument/children``; an imported component lives in neither,
/// because it is not part of the file and must never be written, revised, searched or
/// deleted as if it were. This is the same shape, read-only, for the imported side:
/// the walks that follow a `ref` into its component — override keys, name paths,
/// addresses into an instance, the tree's instance rows — look here when the
/// document's own store has no such node. See `EditableDocument+ComponentLookup.swift`.
struct ImportedComponentStore: Friendly {
    /// The `imports` table the store was built for.
    let imports: [String: String]?

    /// The prefixed definitions, as ``PenImportResolver/definitions(for:libraries:)``
    /// returned them.
    let definitions: PenImportedDefinitions

    /// Every imported node, children stripped, keyed by prefixed id.
    private(set) var nodes: [String: PenNode] = [:]

    /// Ordered child ids of each imported container.
    private(set) var children: [String: [String]] = [:]

    /// The parent of each imported node below a component root.
    private(set) var parents: [String: String] = [:]

    /// Every imported reusable node — outermost or nested — children stripped, keyed by
    /// prefixed id: the imported half of ``EditableDocument/componentRegistry``.
    private(set) var reusables: [String: PenNode] = [:]

    /// The same reusables with their whole subtrees: the registry a ref expansion adds
    /// to the document's own. See ``PenImportedDefinitions/registry``.
    let expansionRegistry: [String: PenNode]

    /// Flattens a set of definitions.
    ///
    /// - Parameters:
    ///   - imports: The `imports` table the definitions came from.
    ///   - definitions: The prefixed definitions.
    init(imports: [String: String]?, definitions: PenImportedDefinitions) {
        self.imports = imports
        self.definitions = definitions
        expansionRegistry = definitions.registry
        for key in definitions.components.keys.sorted() {
            if let component = definitions.components[key] {
                flatten(component, parentID: nil)
            }
        }
    }

    /// Records one node and its subtree.
    private mutating func flatten(_ node: PenNode, parentID: String?) {
        nodes[node.id] = PenNode(
            id: node.id, common: node.common, kind: node.kind.withEmptyChildren(), extras: node.extras
        )
        if node.common.reusable == true { reusables[node.id] = nodes[node.id] }
        if let parentID { parents[node.id] = parentID }
        if let declared = node.kind.declaredChildIDs { children[node.id] = declared }
        for child in node.kind.inlineChildren {
            flatten(child, parentID: node.id)
        }
    }
}
