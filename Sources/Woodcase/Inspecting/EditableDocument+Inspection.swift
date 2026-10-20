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
                overrides: (refData.rootOverrides ?? [:]).merging(
                    Self.naturalOverrides(in: node.common.metadata.map { .dictionary($0.object) }, kindOnly: true)
                ) { stored, _ in stored }
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
                overrides: Self.expandingNaturalOverrides(refData.descendants?[key]?.properties ?? [:])
            )
        }
    }

    // MARK: - Private

    /// An override entry with each Woodcase-owned key its metadata stores listed as an
    /// override of its own, under the raw key `override` and an inspector name it by
    /// (`strokeDash`, at `kind.strokeDash`); the entry's `metadata` is listed too.
    private static func expandingNaturalOverrides(_ entry: [String: AnyCodable]) -> [String: AnyCodable] {
        entry.merging(naturalOverrides(in: entry[NodePropertyCodec.rawKey(for: NodePropertyCodec.metadataPath)])) { stored, _ in
            stored
        }
    }

    /// The Woodcase-owned keys a metadata value stores, by the raw field of their natural
    /// path; only the `kind.*` ones when `kindOnly`, for a ref, whose `common.locked` is its own.
    private static func naturalOverrides(in metadata: AnyCodable?, kindOnly: Bool = false) -> [String: AnyCodable] {
        guard case let .dictionary(object)? = metadata,
              case let .dictionary(keys)? = object[PenMetadata.woodcaseNamespace]
        else { return [:] }
        var found: [String: AnyCodable] = [:]
        for (raw, value) in keys {
            guard let key = PenMetadata.WoodcaseKey(rawValue: raw), let path = key.naturalPath,
                  let field = key.naturalField, !kindOnly || path.hasPrefix(NodePropertyCodec.kindPrefix)
            else { continue }
            found[field] = value
        }
        return found
    }

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
