//
//  EditPlanner+SlotDuplicate.swift
//  Woodcase
//

import Foundation

public extension EditPlanner {
    /// Plans Duplicate: a copy of each node right after it, in its own parent — slot
    /// content in its slot, with fresh ids throughout, the nodes in the fills an
    /// instance among them writes included (Penumbra spec §13.5 rules 4 and 8).
    ///
    /// A copy of slot content is written into the slot's fill, the default content
    /// copied into one first when the slot shows it; a copy of a stored node is an
    /// insert after it. Penumbra's own offsets for a top-level duplicate are its own;
    /// this plans the in-place copy.
    ///
    /// The copies carry every connector whose two ends are both inside the duplicated
    /// nodes (``connectorIDs(enclosedBy:in:)``): each is copied at the top level, after
    /// the copies, its ends on them — an end on slot content names the copy in the fill
    /// (`instance/copy`) — and named in ``StructuralEditPlan/carriedConnectorIDs``. A
    /// connector with one end outside stays single. A duplicated connector whose ends
    /// were duplicated too follows the copies the same way (Ben's ruling of 2026-10-23,
    /// Penumbra spec §11).
    ///
    /// ```swift
    /// let plan = try EditPlanner.planDuplicate(nodeIDs: ["Filled/Row2/ItemB"], in: document)
    /// selection = plan.placedIDs
    /// ```
    ///
    /// Refused for a node inside an instance outside its slots' content
    /// (``EditRefusal/Code/insideInstance``) and for one naming nothing
    /// (``EditRefusal/Code/addressNotFound``).
    ///
    /// - Parameters:
    ///   - nodeIDs: The nodes, by stored or expanded id; a node inside another given
    ///     goes with it.
    ///   - document: The document, as it stands.
    /// - Returns: The edits, to submit as one, and the copies' ids in the order given.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planDuplicate(nodeIDs: [String], in document: EditableDocument) throws(EditRefusal) -> StructuralEditPlan {
        let session = SlotEditSession(document: document)
        let origins = try SlotOrigin.topMost(
            nodeIDs.map { id throws(EditRefusal) in try SlotOrigin(id, in: session) }, in: session
        )
        var stored: [EditOperation] = []
        var placed: [Placed] = []
        var copied: [String?: [Int]] = [:]
        var steps: [String: String] = [:]
        for origin in origins {
            switch origin {
            case let .document(id):
                let copy = try storedCopy(of: id, taken: &session.taken, in: document)
                steps.merge(copy.ids) { _, new in new }
                let parent = document.parentID(of: id)
                let original = siblingIndex(of: id, in: document)
                let index = original + 1 + (copied[parent] ?? []).count(where: { $0 < original })
                copied[parent, default: []].append(original)
                stored.append(.insertNode(EditOperation.InsertNode(node: copy.node, parentID: parent, index: index)))
                placed.append(.stored(copy.node.id))
            case let .content(refID, key):
                let copy = try duplicate(key, of: refID, in: session)
                steps.merge(copy.ids) { _, new in new }
                placed.append(copy.placed)
            }
        }
        // An end names the original as the document holds it now; a default content
        // copied into a fill renamed it first, and the duplicate renamed that.
        let materialized = StructuralEditPlan(operations: [], renamedIDs: session.renamedIDs)
        let end = { (path: String) in mappingSteps(of: materialized.renamed(path), through: steps) }
        let connectors = connectorCopies(
            of: connectorIDs(enclosedBy: nodeIDs, in: document), in: document, taken: &session.taken, end: end
        ).map { EditOperation.insertNode(EditOperation.InsertNode(node: $0)) }
        let overrides = session.writeOperations()
        let operations = followingCopies(stored, ends: end) + overrides + connectors
        // Each copy's index counts the copies before it, which the document as it stands
        // does not hold yet; the index was planned here, so the rest is what is checked.
        try validating(operations.map(\.withoutIndex), address: nodeIDs.first ?? "", in: document)
        return StructuralEditPlan(
            operations: operations,
            placedIDs: placed.map { $0.expandedID(in: session) },
            renamedIDs: session.renamedIDs,
            materializedSlotIDs: session.materializedSlotIDs,
            carriedConnectorIDs: connectors.compactMap { operation in
                guard case let .insertNode(insert) = operation else { return nil }
                return insert.node.id
            }
        )
    }
}

extension EditPlanner {
    /// A copy of a stored node, every id fresh, its fills' included, with old id → new
    /// id for each node it renamed.
    private static func storedCopy(
        of id: String, taken: inout Set<String>, in document: EditableDocument
    ) throws(EditRefusal) -> (node: PenNode, ids: [String: String]) {
        let subtree: PenNode
        do {
            subtree = try document.materializeSubtree(rootID: id)
        } catch {
            throw EditRefusal(error, address: id, in: document)
        }
        let plan = SubtreeIDPlan.regenerating(subtree, avoiding: taken)
        taken.formUnion(plan.ids)
        let renumbered = plan.applied(to: subtree)
        let fills = SlotJSON.fillRenames(in: renumbered, taken: &taken)
        return (SlotJSON.applyingFillRenames(fills, to: renumbered), plan.replacements.merging(fills) { _, new in new })
    }

    /// Copies one node of slot content into its fill, right after it, with old id → new
    /// id for each node it renamed.
    private static func duplicate(
        _ key: String, of refID: String, in session: SlotEditSession
    ) throws(EditRefusal) -> (placed: Placed, ids: [String: String]) {
        guard let before = session.map(of: refID), let siteIndex = before.nodes[key]?.siteIndex else {
            throw outsideSlotsRefusal(key)
        }
        let slotKey = before.sites[siteIndex].slotKey
        guard let (site, fill) = session.ensureFill(slotKey: session.current(slotKey, in: refID), in: refID),
              let map = session.map(of: refID),
              let localID = map.nodes[session.current(key, in: refID)]?.localID,
              let node = SlotJSON.node(localID, in: fill),
              let (parent, index) = SlotJSON.position(of: localID, in: fill)
        else { throw SlotMove.unreadable(key) }
        var copies: [String: String] = [:]
        let base = session.contentBase(refID: refID, slotKey: slotKey)
        let copy = SlotJSON.renumbered(.dictionary(node), oldBase: base, newBase: base, taken: &session.taken, renames: &copies)
        var list = fill
        SlotJSON.insert(copy, into: parent, at: index + 1, in: &list)
        session.setFill(list, of: site)
        let ids = Dictionary(copies.map { old, new in (lastStep(of: old), lastStep(of: new)) }) { first, _ in first }
        return (.slot(refID: refID, slotKey: slotKey, localID: SlotJSON.id(of: copy) ?? localID), ids)
    }

    /// The last id of a `/`-separated path.
    private static func lastStep(of path: String) -> String {
        path.split(separator: NodeAddress.separator).last.map(String.init) ?? path
    }
}

private extension EditOperation {
    /// An insert with no index — appended — and any other operation as it is.
    var withoutIndex: EditOperation {
        guard case var .insertNode(insert) = self else { return self }
        insert.index = nil
        return .insertNode(insert)
    }
}
