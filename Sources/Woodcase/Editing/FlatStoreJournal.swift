//
//  FlatStoreJournal.swift
//  Woodcase
//

import Foundation

/// What a change wrote to a collaborative document's flat store, each entry as it stood
/// before the change first wrote it.
///
/// A collaborator's batch reaches the flat store only as ``DocumentMutation``s and the
/// reconciliation that follows them, and both note every node, parent link and children
/// list here before they write it; a local edit in collaborative mode notes its own
/// structural footprint (``noteFootprint(of:in:)``). That makes the journal the change's
/// whole footprint: the reconciliation (``EditableDocument/reconcileChildrenWithParents(after:)``)
/// reads from it which nodes and lists it has to settle, and a session's
/// ``ChangeInvalidation/RemoteProbe`` compares what it names with the document after —
/// both in proportion to what the change wrote rather than to the document.
struct FlatStoreJournal: Friendly {
    /// Each written node as it was: `nil` for one the batch created.
    private(set) var nodes: [String: PenNode?] = [:]

    /// Each node whose parent link was written, with the parent it had: `nil` for none.
    private(set) var parents: [String: String?] = [:]

    /// Each parent whose children list was written, with the list it had: `nil` for
    /// none declared.
    private(set) var children: [String: [String]?] = [:]

    /// The root order, if the batch wrote it.
    private(set) var rootOrder: [String]?

    /// An empty journal.
    init() {}

    /// Whether the batch wrote no parent link, children list or root order and created or
    /// removed no node — so the placement of every node is as it was.
    ///
    /// - Parameter document: The document after the batch.
    /// - Returns: `true` when there is nothing for a reconciliation to settle.
    func movesNothing(in document: EditableDocument) -> Bool {
        parents.isEmpty && children.isEmpty && rootOrder == nil
            && nodes.allSatisfy { id, before in (before == nil) == (document.nodes[id] == nil) }
    }

    /// Notes a node about to be written.
    ///
    /// - Parameters:
    ///   - nodeID: The node.
    ///   - document: The document, before the write.
    mutating func noteNode(_ nodeID: String, in document: EditableDocument) {
        guard nodes.index(forKey: nodeID) == nil else { return }
        nodes[nodeID] = .some(document.nodes[nodeID])
    }

    /// Notes a parent link about to be written.
    ///
    /// - Parameters:
    ///   - nodeID: The node whose parent is written.
    ///   - document: The document, before the write.
    mutating func noteParent(of nodeID: String, in document: EditableDocument) {
        guard parents.index(forKey: nodeID) == nil else { return }
        parents[nodeID] = .some(document.parents[nodeID])
    }

    /// Notes a children list about to be written — the root order for `nil`.
    ///
    /// - Parameters:
    ///   - parentID: The parent whose list is written, or `nil` for the root order.
    ///   - document: The document, before the write.
    mutating func noteChildren(of parentID: String?, in document: EditableDocument) {
        guard let parentID else {
            if rootOrder == nil { rootOrder = document.rootOrder }
            return
        }
        guard children.index(forKey: parentID) == nil else { return }
        children[parentID] = .some(document.children[parentID])
    }

    /// Notes the placement a local editing operation is about to write: the nodes it
    /// inserts or deletes, the node it moves, and the lists they leave and join.
    ///
    /// Property writes place nothing and note nothing. A detach, a replace and a
    /// detaching delete reach the CRDT as these primitives, so each primitive notes its
    /// own.
    ///
    /// - Parameters:
    ///   - operation: The operation, about to be applied.
    ///   - document: The document, before it is applied.
    mutating func noteFootprint(of operation: EditOperation, in document: EditableDocument) {
        switch operation {
        case let .insertNode(op):
            noteChildren(of: op.parentID, in: document)
            for nodeID in document.collectInsertedIDs(in: op.node) {
                noteNode(nodeID, in: document)
                noteParent(of: nodeID, in: document)
                noteChildren(of: nodeID, in: document)
            }
        case let .deleteNode(op):
            noteChildren(of: document.parents[op.nodeID], in: document)
            for nodeID in document.descendantIDs(of: op.nodeID) {
                noteNode(nodeID, in: document)
                noteParent(of: nodeID, in: document)
                noteChildren(of: nodeID, in: document)
            }
        case let .moveNode(op):
            noteParent(of: op.nodeID, in: document)
            noteChildren(of: document.parents[op.nodeID], in: document)
            noteChildren(of: op.newParentID, in: document)
        default:
            break
        }
    }

    /// Notes everything one mutation is about to write.
    ///
    /// - Parameters:
    ///   - mutation: The mutation.
    ///   - document: The document, before it is applied.
    mutating func note(_ mutation: DocumentMutation, in document: EditableDocument) {
        switch mutation {
        case let .setNode(node):
            noteNode(node.id, in: document)
        case let .removeNode(nodeID):
            noteNode(nodeID, in: document)
            noteChildren(of: nodeID, in: document)
            noteChildren(of: document.parents[nodeID], in: document)
        case let .setChildren(parentID, _):
            noteChildren(of: parentID, in: document)
        case let .setParent(nodeID, parentID):
            noteParent(of: nodeID, in: document)
            noteChildren(of: document.parents[nodeID], in: document)
            noteChildren(of: parentID, in: document)
        case let .removeParent(nodeID):
            noteParent(of: nodeID, in: document)
        case .setVariable, .removeVariable, .setImport, .removeImport, .setThemeAxis, .removeThemeAxis,
             .setDocumentProperty:
            break
        }
    }
}
