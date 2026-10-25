//
//  CRDTDocument+Existence.swift
//  Woodcase
//

import Foundation

/// A node's existence as replica state: one last-writer-wins register per id.
///
/// A ``CRDTOperation/Payload/createNode(_:)`` writes "alive" and a
/// ``CRDTOperation/Payload/deleteNode(_:)`` writes "deleted"; the write with the newer
/// timestamp wins, whatever order they arrive in. So a delete undone — the node created
/// again under its own id — comes back on every peer, and a delete concurrent with that
/// undo removes the node everywhere only if it is the newer of the two. The register's
/// value is membership in ``tombstones``; its timestamp is ``existenceTimestamps``. A
/// node that came with the document has never been written, and any write beats it.
///
/// A create writes every property of the node it carries, so it is also the floor of
/// each of the node's property registers: a property write older than the create that
/// brought the node back loses to it, even on a peer where it arrives afterwards.
///
/// Property writes newer than a node's latest existence write are never lost to a
/// delete. Those that arrive while the node is deleted, and those the node held when a
/// delete removed it, are kept as ``dormantWrites``; when a newer create brings the node
/// back, each kept write newer than that create is applied on top of it, so every
/// register still resolves by its own last-writer-wins rule. A write older than the
/// id's latest existence write can never win again — any create that would bring the
/// node back is newer still — so it is not kept.
extension CRDTDocument {
    /// A property write kept for a deleted node, to apply if a newer create brings it back.
    public struct DormantWrite: Friendly {
        /// The write's timestamp: the operation's id.
        public var timestamp: Timestamp

        /// The written value, in .pen JSON shape.
        public var value: AnyCodable

        /// Creates a kept write.
        ///
        /// - Parameters:
        ///   - timestamp: The write's timestamp.
        ///   - value: The written value.
        public init(timestamp: Timestamp, value: AnyCodable) {
            self.timestamp = timestamp
            self.value = value
        }
    }

    /// Whether a write at `timestamp` is newer than the id's latest existence write, or
    /// the id has none.
    ///
    /// A create or a delete that is newer wins the register. A property write that is
    /// newer postdates the create that last brought the node into being, which wrote
    /// every property it carries; one that is not can never win.
    ///
    /// - Parameters:
    ///   - nodeID: The node.
    ///   - timestamp: The write's timestamp.
    /// - Returns: `true` when the write is newer.
    func postdatesExistence(of nodeID: String, at timestamp: Timestamp) -> Bool {
        guard let current = existenceTimestamps[nodeID] else { return true }
        return timestamp > current
    }

    /// Takes a winning existence write into the register.
    ///
    /// Every property write newer than it that the node holds is kept dormant first, read
    /// from `node`, so a delete loses none of them and a create can apply them on top of
    /// what it carries; older kept writes are dropped, as no later create can be older.
    /// The node's property registers start again, floored by the write.
    ///
    /// - Parameters:
    ///   - nodeID: The node.
    ///   - alive: `true` for a create, `false` for a delete.
    ///   - timestamp: The write's timestamp, which ``postdatesExistence(of:at:)`` accepted.
    ///   - node: The node as the flat store holds it, or `nil` when it holds none.
    func recordExistence(of nodeID: String, alive: Bool, at timestamp: Timestamp, holding node: PenNode?) {
        var kept = (dormantWrites[nodeID] ?? [:]).filter { $0.value.timestamp > timestamp }
        if let node, let map = propertyMaps[nodeID] {
            for (property, written) in map.timestamps where written > timestamp {
                guard kept[property].map({ $0.timestamp < written }) ?? true,
                      let value = registerValue(at: property, of: node) else { continue }
                kept[property] = DormantWrite(timestamp: written, value: value)
            }
        }
        existenceTimestamps[nodeID] = timestamp
        propertyMaps[nodeID] = LWWPropertyMap()
        dormantWrites[nodeID] = kept.isEmpty ? nil : kept
        if alive {
            tombstones.remove(nodeID)
        } else {
            tombstones.insert(nodeID)
        }
    }

    /// Keeps a property write that arrived while its node is deleted, when it is newer
    /// than the delete and than any write already kept for the same property.
    ///
    /// - Parameters:
    ///   - write: The property write.
    ///   - timestamp: Its timestamp.
    func keepDormant(_ write: CRDTOperation.SetProperty, at timestamp: Timestamp) {
        guard postdatesExistence(of: write.nodeID, at: timestamp),
              dormantWrites[write.nodeID]?[write.property].map({ $0.timestamp < timestamp }) ?? true
        else { return }
        dormantWrites[write.nodeID, default: [:]][write.property] = DormantWrite(timestamp: timestamp, value: write.value)
    }

    /// The node a winning create brings into being: what it carries, with every write
    /// kept for it applied on top in timestamp order and recorded in its property
    /// registers. The kept writes are spent.
    ///
    /// Call after ``recordExistence(of:alive:at:holding:)``, which has dropped every kept
    /// write older than the create.
    ///
    /// - Parameter node: The node the create carries, children stripped.
    /// - Returns: The node to write to the flat store.
    func applyingDormantWrites(to node: PenNode) -> PenNode {
        guard let kept = dormantWrites.removeValue(forKey: node.id) else { return node }
        var result = node
        for (property, write) in kept.sorted(by: { $0.value.timestamp < $1.value.timestamp }) {
            result = applyingProperty(property, value: write.value, to: result)
            propertyMaps[node.id, default: LWWPropertyMap()].record(property: property, at: write.timestamp)
        }
        return result
    }
}
