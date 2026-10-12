//
//  EditableDocument+Inspection.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// Inspects a node of the expanded tree by the id an editor holds for it: its
    /// address, where its values come from, and which properties this instance overrides
    /// there.
    ///
    /// ```swift
    /// let inspection = document.inspect(expandedID: "Card1/Btn02/Lbl02")!
    /// inspection.address          // .instanceDescendant(refID: "Card1", descendantKey: "Btn02/Lbl02")
    /// inspection.overriddenPaths  // ["kind.content"]
    /// ```
    ///
    /// - Parameter expandedID: An id from the expanded document.
    /// - Returns: The inspection, or `nil` when ``resolve(expandedID:)`` maps the id to
    ///   no address.
    func inspect(expandedID: String) -> NodeInspection? {
        resolve(expandedID: expandedID).flatMap(inspect)
    }

    /// Inspects the node an address names.
    ///
    /// The overrides listed are the ones **this** instance stores: an instance root's root
    /// overrides, and a descendant's entry in the outermost instance's `descendants`
    /// map. An override a component's own nested instance stores is part of that
    /// component, and shows in ``NodeInspection/sourceNode``'s component rather than here.
    ///
    /// - Parameter target: The node.
    /// - Returns: The inspection, or `nil` when the document has no such node.
    func inspect(_ target: ResolvedNodeAddress) -> NodeInspection? {
        switch target {
        case let .node(id):
            guard let node = node(id: id) else { return nil }
            guard case let .ref(refData) = node.kind else {
                return inspection(of: target, source: .ownStorage, node: node, overrides: [:])
            }
            let componentID = componentRoot(ofInstanceChain: [id])
            return inspection(
                of: target,
                source: .instance(componentID: componentID),
                node: componentID.flatMap(componentNode),
                overrides: refData.rootOverrides ?? [:]
            )
        case let .instanceDescendant(refID, key):
            guard case let .ref(refData)? = node(id: refID)?.kind,
                  let shown = node(ofInstance: refID, descendantKey: key)
            else { return nil }
            if ownSlotContentKeys(ofInstance: refID).contains(key) {
                return inspection(of: target, source: .slotContent, node: shown, overrides: [:])
            }
            return inspection(
                of: target,
                source: .componentNode(definitionID: shown.id),
                node: shown,
                overrides: refData.descendants?[key]?.properties ?? [:]
            )
        }
    }

    // MARK: - Private

    /// Assembles an inspection, turning stored overrides into sorted rows.
    private func inspection(
        of target: ResolvedNodeAddress,
        source: NodeInspection.Source,
        node: PenNode?,
        overrides: [String: AnyCodable]
    ) -> NodeInspection {
        NodeInspection(
            expandedID: expandedID(of: target),
            address: target,
            source: source,
            sourceNode: node,
            overrides: overrides.keys.sorted().map { key in
                NodeInspection.Override(
                    key: key,
                    path: NodePropertyCodec.path(forRawKey: key),
                    value: overrides[key] ?? .null
                )
            }
        )
    }
}
