//
//  EditableDocument+GranularInverse.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// The guarded steps that undo an operation, captured before it is applied.
    ///
    /// Where ``prepareInverse(of:)`` snapshots whole structs and absolute indices, this
    /// returns steps a session can apply around other authors' later work:
    ///
    /// - A property write (after ``EditOperation/normalized(in:)``) undoes as one
    ///   ``EditOperation/setProperties(_:)`` per path, restoring that path's old value —
    ///   and a write of `common.metadata` as one per metadata entry it changes, each
    ///   guarded by that entry's key (<doc:PenMetadataNamespace>).
    /// - An override undoes as one step per key: restore the key's old value, or unset a
    ///   key the edit added. A key the edit unset that was never there needs no step.
    /// - A move, a delete and a detach put nodes back through a ``Placement`` anchored
    ///   on the sibling they sat after; ``GuardedInverse/resolved(in:)`` turns it into
    ///   an index when the step is applied.
    /// - Everything else wraps ``prepareInverse(of:)``'s operations, guarded by the
    ///   forward operation's keys.
    ///
    /// Apply the steps in order, each through ``GuardedInverse/resolved(in:)``. A detach,
    /// or a delete that detaches instances, gets ``prepareInverse(of:)``'s complete
    /// inverse, its re-inserts anchored like any other.
    ///
    /// - Parameter operation: The operation about to be applied.
    /// - Returns: The steps that undo it, each guarded by the keys it restores.
    /// - Throws: ``EditingError`` if a node, variable, import or axis the inverse
    ///   needs is missing, or a property path is unknown.
    func granularInverse(of operation: EditOperation) throws -> [GuardedInverse] {
        let normalized = operation.normalized(in: self)
        switch normalized {
        case let .setProperties(op):
            return try propertySteps(op)
        case let .overrideDescendant(op):
            return try overrideSteps(op)
        case let .overrideRoot(op):
            return try rootOverrideSteps(op)
        default:
            let keys = try ChangeKey.keys(of: normalized, in: self)
            return try prepareInverse(of: normalized).map {
                GuardedInverse(operation: $0, keys: keys, placement: placement(restoring: $0))
            }
        }
    }
}

extension EditableDocument {
    /// One step per path, each writing back that path's value as it stands; one per
    /// entry a `common.metadata` write changes.
    private func propertySteps(_ op: EditOperation.SetProperties) throws -> [GuardedInverse] {
        let node = try requireNode(op.nodeID)
        return try op.properties.keys.sorted().flatMap { path -> [GuardedInverse] in
            if path == NodePropertyCodec.metadataPath, let value = op.properties[path] {
                return try metadataEntrySteps(writing: value, on: node)
            }
            return try [GuardedInverse(
                operation: .setProperties(EditOperation.SetProperties(
                    nodeID: op.nodeID,
                    properties: [path: NodePropertyCodec.value(at: path, of: node)]
                )),
                keys: [.property(node: op.nodeID, path: path)]
            )]
        }
    }

    /// One step per descendant-override key the edit touches.
    private func overrideSteps(_ op: EditOperation.OverrideDescendant) throws -> [GuardedInverse] {
        let entry = try requireRefData(op.refNodeID).descendants?[op.descendantID]?.properties ?? [:]
        return Self.keyedRestores(of: op.properties, unset: op.unset, from: entry).map { restore in
            GuardedInverse(
                operation: .overrideDescendant(EditOperation.OverrideDescendant(
                    refNodeID: op.refNodeID,
                    descendantID: op.descendantID,
                    properties: restore.properties,
                    unset: restore.unset
                )),
                keys: [.override(ref: op.refNodeID, descendant: op.descendantID, key: restore.key)]
            )
        }
    }

    /// One step per root-override key the edit touches.
    private func rootOverrideSteps(_ op: EditOperation.OverrideRoot) throws -> [GuardedInverse] {
        let existing = try requireRefData(op.refNodeID).rootOverrides ?? [:]
        return Self.keyedRestores(of: op.properties, unset: op.unset, from: existing).map { restore in
            GuardedInverse(
                operation: .overrideRoot(EditOperation.OverrideRoot(
                    refNodeID: op.refNodeID,
                    properties: restore.properties,
                    unset: restore.unset
                )),
                keys: [.rootOverride(ref: op.refNodeID, key: restore.key)]
            )
        }
    }

    /// What undoes a write to each key of an override map, sorted by key.
    ///
    /// A key the map held is written back; a key the write brought in is unset; a key
    /// the write removed that was never there is left alone.
    private static func keyedRestores(
        of properties: [String: AnyCodable],
        unset: [String],
        from existing: [String: AnyCodable]
    ) -> [(key: String, properties: [String: AnyCodable], unset: [String])] {
        Set(properties.keys).union(unset).sorted().compactMap { key in
            if let old = existing[key] { return (key, [key: old], []) }
            if properties[key] != nil { return (key, [:], [key]) }
            return nil
        }
    }

    /// The ref payload of a node, or the error ``prepareInverse(of:)`` would raise.
    private func requireRefData(_ nodeID: String) throws -> PenNode.RefData {
        guard case let .ref(data) = try requireNode(nodeID).kind else {
            throw EditingError.notARefNode(id: nodeID)
        }
        return data
    }

    /// The anchored placement for a step that puts a node back where it stands now.
    ///
    /// - Parameter inverse: One operation of ``prepareInverse(of:)``'s result.
    /// - Returns: The node's current placement for a move or an insert of a node the
    ///   document holds now; `nil` for anything else.
    private func placement(restoring inverse: EditOperation) -> Placement? {
        switch inverse {
        case let .moveNode(move): Placement.of(move.nodeID, in: self)
        case let .insertNode(insert): Placement.of(insert.node.id, in: self)
        default: nil
        }
    }
}
