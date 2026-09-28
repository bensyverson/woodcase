//
//  CRDTDocument+Extras.swift
//  Woodcase
//

import Foundation

/// A node's ``PenExtras`` as replica state.
///
/// Extras are one last-writer-wins register per node, carried on the wire as an ordinary
/// ``CRDTOperation/SetProperty`` under the reserved path ``extrasProperty`` with the whole
/// ``PenExtras`` as its value. A node's extras arrive with it in
/// ``CRDTOperation/CreateNode``; after that the only local write is a replace, which
/// gives the node its replacement's extras. Nothing edits a single extra, so the register
/// never contends with a property write.
extension CRDTDocument {
    /// The property path a node's extras register is keyed under.
    ///
    /// It has neither the `common.` nor the `kind.` prefix, so ``NodePropertyCodec`` —
    /// the path every edit verb goes through — refuses it: an agent cannot write it.
    public static let extrasProperty = "extras"

    /// Records a local write of a node's whole extras register and returns the op to send.
    ///
    /// - Parameters:
    ///   - nodeID: The node whose extras changed.
    ///   - extras: Its new extras.
    /// - Returns: The one ``CRDTOperation/SetProperty`` to replicate.
    func processLocalSetExtras(nodeID: String, extras: PenExtras) -> [CRDTOperation] {
        let op = makeOp(.setProperty(CRDTOperation.SetProperty(
            nodeID: nodeID,
            property: Self.extrasProperty,
            value: .dictionary(extras.values)
        )))
        propertyMaps[nodeID, default: LWWPropertyMap()].record(property: Self.extrasProperty, at: op.id)
        return [op]
    }

    /// Returns `node` with its extras register set from a replicated value, or unchanged
    /// if the value is not the JSON object a register holds.
    ///
    /// - Parameters:
    ///   - value: The register's replicated value.
    ///   - node: The node to patch.
    /// - Returns: The patched node.
    func applyExtras(_ value: AnyCodable, to node: PenNode) -> PenNode {
        guard case let .dictionary(values) = value else { return node }
        var patched = node
        patched.extras = PenExtras(values)
        return patched
    }
}
