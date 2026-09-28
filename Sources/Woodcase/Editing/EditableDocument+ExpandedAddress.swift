//
//  EditableDocument+ExpandedAddress.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// The id a resolved address answers to *after* ``PenRefExpander/expand(_:for:)``.
    ///
    /// ``ResolvedNodeAddress/address`` names a node as the *authored* document stores
    /// it. The layout engine, the renderer and every rect map run on the **expanded**
    /// document, where a `ref` does not survive under its own id: the expander clones
    /// the component it points at and prefixes every id in the clone with the ref's, so
    /// the instance placed by `YGJ0d` is rooted at `YGJ0d/nSNTs`.
    ///
    /// This closes that last gap. ``ResolvedNodeAddress/address`` already yields the
    /// post-expansion id for a node *inside* an instance — `Nav01/Lbl01` is both the
    /// `descendants` key and the prefixed id — because the expander prefixes with the
    /// ref's id at every level. Only the instance **root** needs the component's own id
    /// appended, and only this type knows which component that is:
    ///
    /// | Authored target | Expanded id |
    /// |---|---|
    /// | a plain node, or a reusable definition | its own id |
    /// | a `ref` (an instance root) | `<ref id>/<component root id>` |
    /// | a node inside an instance | `<ref id>/<node id>` |
    ///
    /// A `ref` whose component is missing — or points at a node that is not marked
    /// `reusable` — is left standing by the expander under its own id, and gets its own
    /// id back here, so the two agree in the broken case too.
    ///
    /// Following the ref *chain* matters: a reusable component may itself be a `ref` to
    /// another component, and the expander clones the far end of that chain, so the id
    /// it prefixes is the last component's, not the first's. So does the instance the
    /// target sits inside: an instance may repoint a nested `ref` through its own
    /// `descendants` map, and the id the expander prefixes is then the component it was
    /// repointed at — see ``componentRootID(placedBy:insideInstances:)``. A `ref` the
    /// instance *injected* into a slot is an instance root like any other, and its
    /// payload is read from the override that wrote it.
    ///
    /// - Parameter resolved: What ``resolve(_:tags:)-(String,_)`` returned.
    /// - Returns: The id to look up in a layout rect map, or to hand a renderer as its
    ///   root node.
    func expandedID(of resolved: ResolvedNodeAddress) -> String {
        let address = resolved.address
        let steps = resolved.descendantKey?
            .split(separator: NodeAddress.separator)
            .map(String.init) ?? []
        let storedID = steps.last ?? resolved.targetID
        let chain = steps.isEmpty ? [] : [resolved.targetID] + steps.dropLast()
        guard let rootID = componentRoot(ofInstanceChain: chain + [storedID]) else {
            return address
        }
        return "\(address)\(NodeAddress.separator)\(rootID)"
    }
}
