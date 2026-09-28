//
//  CRDTDocument+PropertyCodec.swift
//  Woodcase
//

import Foundation

/// The CRDT's view of node properties.
///
/// There is one implementation of the property-path vocabulary —
/// ``NodePropertyCodec`` — and this is the lenient face of it. A remote peer's
/// operation must never crash or throw its way out of ``CRDTDocument/processRemote(operation:document:)``,
/// so a path this peer does not recognise (it holds a different kind for that
/// node after a concurrent type change) or a value it cannot decode leaves the
/// property as it was, rather than nilling it out as this codec used to.
///
/// Local edits take the throwing path instead, so the caller learns what was
/// wrong with the key or the value.
extension CRDTDocument {
    // MARK: - Property application

    /// Returns `nodeID`'s node with one property set from a CRDT write.
    ///
    /// - Parameters:
    ///   - nodeID: The node the write addresses.
    ///   - property: The property path.
    ///   - value: The new value in .pen JSON shape.
    ///   - document: The flat store to read the node from.
    /// - Returns: The patched node, or the node unchanged if the write does not apply.
    func applyPropertyToNode(nodeID: String, property: String, value: AnyCodable, document: EditableDocument) -> PenNode {
        guard let node = document.nodes[nodeID] else {
            // This shouldn't happen — caller checks first
            return PenNode(id: nodeID, common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        }
        if property == Self.extrasProperty {
            return applyExtras(value, to: node)
        }
        return (try? NodePropertyCodec.setting(value, at: property, on: node)) ?? node
    }

    /// Returns `common` with one shared property set, or unchanged if the write does not apply.
    ///
    /// - Parameters:
    ///   - property: The `common.*` path.
    ///   - value: The new value in .pen JSON shape.
    ///   - common: The shared properties to patch.
    /// - Returns: The patched shared properties.
    func applyCommonProperty(property: String, value: AnyCodable, to common: PenNodeCommon) -> PenNodeCommon {
        // The node's identity only decorates an error this path discards.
        (try? NodePropertyCodec.setting(value, at: property, on: common, nodeID: "", nodeType: "")) ?? common
    }

    /// Returns `kind` with one kind property set, or unchanged if the write does not apply.
    ///
    /// - Parameters:
    ///   - property: The `kind.*` path.
    ///   - value: The new value in .pen JSON shape.
    ///   - kind: The kind payload to patch.
    /// - Returns: The patched kind.
    func applyKindProperty(property: String, value: AnyCodable, to kind: PenNode.Kind) -> PenNode.Kind {
        (try? NodePropertyCodec.setting(value, at: property, on: kind, nodeID: "")) ?? kind
    }

    // MARK: - Value extraction

    /// Reads a `common.*` path for replication, or ``AnyCodable/null`` if it does not apply.
    ///
    /// - Parameters:
    ///   - property: The `common.*` path.
    ///   - common: The shared properties to read.
    /// - Returns: The value in .pen JSON shape.
    func extractCommonValue(property: String, from common: PenNodeCommon) -> AnyCodable {
        (try? NodePropertyCodec.commonValue(at: property, of: common, nodeID: "", nodeType: "")) ?? .null
    }

    /// Reads a `kind.*` path for replication, or ``AnyCodable/null`` if it does not apply.
    ///
    /// - Parameters:
    ///   - property: The `kind.*` path.
    ///   - kind: The kind payload to read.
    /// - Returns: The value in .pen JSON shape.
    func extractKindValue(property: String, from kind: PenNode.Kind) -> AnyCodable {
        (try? NodePropertyCodec.kindValue(at: property, of: kind, nodeID: "")) ?? .null
    }
}
