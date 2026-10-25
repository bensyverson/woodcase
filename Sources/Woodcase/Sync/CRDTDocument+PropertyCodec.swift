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
/// so a path this peer does not recognize (it holds a different kind for that
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
        return applyingProperty(property, value: value, to: node)
    }

    /// Returns `node` with one property set from a CRDT write.
    ///
    /// - Parameters:
    ///   - property: The property path: a register's path as a ``CRDTOperation/SetProperty``
    ///     names it.
    ///   - value: The new value in .pen JSON shape.
    ///   - node: The node to patch.
    /// - Returns: The patched node, or the node unchanged if the write does not apply.
    func applyingProperty(_ property: String, value: AnyCodable, to node: PenNode) -> PenNode {
        if property == Self.extrasProperty {
            return applyExtras(value, to: node)
        }
        if let written = NodePropertyCodec.settingMetadataEntry(value, at: property, on: node) {
            return written
        }
        if let written = Self.settingOverrideEntry(value, at: property, on: node) {
            return written
        }
        return (try? NodePropertyCodec.setting(value, at: property, on: node)) ?? node
    }

    /// Reads the value a node holds in one of its property registers: what a
    /// ``CRDTOperation/SetProperty`` to `property` would write to give it that value.
    ///
    /// The inverse of ``applyingProperty(_:value:to:)``, register by register: the extras
    /// register whole, a metadata entry or an override entry (wrapped, as it travels)
    /// by its entry path, and any other path through ``NodePropertyCodec``.
    ///
    /// - Parameters:
    ///   - property: The register's path.
    ///   - node: The node to read.
    /// - Returns: The value, ``AnyCodable/null`` for an absent entry, or `nil` when the
    ///   path names nothing this node's kind holds.
    func registerValue(at property: String, of node: PenNode) -> AnyCodable? {
        if property == Self.extrasProperty {
            return .dictionary(node.extras.values)
        }
        if property.hasPrefix(NodePropertyCodec.metadataPath + ".") {
            return NodePropertyCodec.metadataEntries(of: node.common.metadata)[property] ?? .null
        }
        if property.hasPrefix(Self.descendantEntryPrefix) || property.hasPrefix(Self.rootOverrideEntryPrefix) {
            guard case let .ref(ref) = node.kind else { return nil }
            return Self.overrideEntries(of: ref)[property] ?? .null
        }
        return try? NodePropertyCodec.value(at: property, of: node)
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
