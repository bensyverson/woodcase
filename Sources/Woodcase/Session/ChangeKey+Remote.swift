//
//  ChangeKey+Remote.swift
//  Woodcase
//

import Foundation

extension ChangeKey {
    /// The keys a collaborator's CRDT operation writes, computed against the document
    /// *before* it is applied.
    ///
    /// Remote keys come from the CRDT payload rather than from an ``EditOperation``, but
    /// they must meet the keys a local edit stamps, or an undo would not see the
    /// collaborator's work. So a property write is keyed as finely as the local
    /// vocabulary: the override maps, which replicate whole, are keyed per override
    /// key that differs; the extras register per `extras.<key>` that differs; and a
    /// change of node type like ``kindKeys(nodeID:old:new:)``. A tree or list move keys
    /// the moved node's place; a create its existence and place; a delete its existence
    /// and place.
    ///
    /// - Parameters:
    ///   - operation: The remote operation about to be applied.
    ///   - document: The collaborative document it will be applied to, as it stands.
    /// - Returns: The keys, without duplicates, in a stable order. Empty for a payload
    ///   that addresses nothing this document holds.
    static func keys(ofRemote operation: CRDTOperation, in document: EditableDocument) -> [ChangeKey] {
        let keys: [ChangeKey] = switch operation.payload {
        case let .setProperty(p):
            propertyKeys(p, in: document)
        case let .listInsert(p):
            [.placement(node: p.elementID)]
        case let .listDelete(p):
            listElement(p.listID, p.positionID, in: document).map { [.placement(node: $0)] } ?? []
        case let .listMove(p):
            listElement(p.sourceListID, p.positionID, in: document).map { [.placement(node: $0)] } ?? []
        case let .treeMove(p):
            [.placement(node: p.nodeID)]
        case let .createNode(p):
            [.existence(node: p.node.id), .placement(node: p.node.id)]
        case let .deleteNode(p):
            [.existence(node: p.nodeID), .placement(node: p.nodeID)]
        case let .setVariable(p):
            [.variable(name: p.name)]
        case let .removeVariable(p):
            [.variable(name: p.name)]
        case let .setImport(p):
            [.importAlias(p.alias)]
        case let .removeImport(p):
            [.importAlias(p.alias)]
        case let .setThemeAxis(p):
            [.themeAxis(p.name)]
        case let .removeThemeAxis(p):
            [.themeAxis(p.name)]
        }
        var seen = Set<ChangeKey>()
        return keys.filter { seen.insert($0).inserted }
    }

    /// The keys one replicated property write changes on its node.
    private static func propertyKeys(_ p: CRDTOperation.SetProperty, in document: EditableDocument) -> [ChangeKey] {
        guard let crdt = document.crdtDocument, let before = document.nodes[p.nodeID] else { return [] }
        let after = crdt.applyPropertyToNode(nodeID: p.nodeID, property: p.property, value: p.value, document: document)
        let whole = ChangeKey.property(node: p.nodeID, path: p.property)
        switch p.property {
        case CRDTDocument.extrasProperty:
            return changedKeys(before.extras.values, after.extras.values).map {
                .property(node: p.nodeID, path: "\(NodePropertyCodec.extrasPrefix)\($0)")
            }
        case kindTypePath:
            return kindKeys(nodeID: p.nodeID, old: before.kind, new: after.kind)
        case descendantsPath:
            let old = refData(before)?.descendants ?? [:]
            let new = refData(after)?.descendants ?? [:]
            let overrides = Set(old.keys).union(new.keys).sorted().flatMap { descendant in
                changedKeys(old[descendant]?.properties ?? [:], new[descendant]?.properties ?? [:]).map {
                    ChangeKey.override(ref: p.nodeID, descendant: descendant, key: $0)
                }
            }
            return [whole] + overrides
        case rootOverridesPath:
            let old = refData(before)?.rootOverrides ?? [:]
            let new = refData(after)?.rootOverrides ?? [:]
            return [whole] + changedKeys(old, new).map { .rootOverride(ref: p.nodeID, key: $0) }
        default:
            return [whole]
        }
    }

    /// The keys whose values differ between two maps, sorted.
    private static func changedKeys(_ old: [String: AnyCodable], _ new: [String: AnyCodable]) -> [String] {
        Set(old.keys).union(new.keys).filter { old[$0] != new[$0] }.sorted()
    }

    /// A node's ref payload, if it is an instance.
    private static func refData(_ node: PenNode) -> PenNode.RefData? {
        if case let .ref(data) = node.kind { data } else { nil }
    }

    /// The element at a position of a replicated children list.
    private static func listElement(_ listID: String, _ position: PositionID, in document: EditableDocument) -> String? {
        document.crdtDocument?.childrenLists[listID]?.value(at: position)
    }

    /// The path an instance's whole descendant-override map replicates under.
    private static let descendantsPath = "kind.descendants"

    /// The path an instance's whole root-override map replicates under.
    private static let rootOverridesPath = "kind.rootOverrides"
}
