//
//  PenClip+PasteSlot.swift
//  Woodcase
//

import Foundation

extension PenClip {
    /// A paste's copies written into an instance's slot.
    struct SlotLanding {
        /// The edits that write them: one `children` override of the slot, and the
        /// connector ends a default content copied into a fill renamed.
        var operations: [EditOperation]

        /// The expanded ids the copies answer to, in order.
        var placedIDs: [String]

        /// The expanded-id prefix of the slot's content (`Filled/`), which a connector end
        /// naming a copy takes.
        var contentBase: String

        /// The ids of the copies' nodes, every depth of their inline trees: the ids a
        /// connector end's first step names a copy by.
        var inlineIDs: Set<String>

        /// The expanded ids the copies answer to once the paste is in.
        ///
        /// The slot planner names an instance of a component the same paste brings by its
        /// path alone, since the document does not hold that component yet; it answers to
        /// its component root's id after that, as every instance does.
        ///
        /// - Parameters:
        ///   - roots: The copies, in the order they were written.
        ///   - definitions: The ids of the components the paste inserts.
        func placedIDs(of roots: [PenNode], definitions: Set<String>) -> [String] {
            zip(roots, placedIDs).map { root, id in
                guard case let .ref(data) = root.kind, definitions.contains(data.ref) else { return id }
                return id + String(NodeAddress.separator) + data.ref
            }
        }

        /// Every id a copy holds: its inline tree's, and those of the nodes in the fills its
        /// instances write.
        static func ids(in root: PenNode) -> [String] {
            var ids = SlotJSON.fillIDs(in: root)
            var pending = [root]
            while let node = pending.popLast() {
                ids.append(node.id)
                pending.append(contentsOf: node.kind.inlineChildren)
            }
            return ids
        }

        /// A pasted connector with each end that names a copy rewritten to name it in the
        /// fill (`Filled/Card`): Pen keeps a connection at the top level, so it stays there
        /// while the nodes it joins live in the instance's fill.
        func attaching(_ connector: PenNode) -> PenNode {
            guard case var .connection(data) = connector.kind else { return connector }
            data.source.path = inFill(data.source.path)
            data.target.path = inFill(data.target.path)
            return PenNode(id: connector.id, common: connector.common, kind: .connection(data), extras: connector.extras)
        }

        /// A path that names a copy, prefixed with the slot's content base.
        private func inFill(_ path: String) -> String {
            let first = path.split(separator: NodeAddress.separator, maxSplits: 1).first.map(String.init) ?? path
            return inlineIDs.contains(first) ? contentBase + path : path
        }
    }

    /// Writes the placed copies into the slot a site names, through the slot planner.
    ///
    /// - Parameters:
    ///   - roots: The copies, placed, in order.
    ///   - site: The site, inside a slot.
    ///   - reserving: Ids the paste draws for other nodes — its definitions, its
    ///     connectors — that a default content copied into a fill must not take.
    ///   - document: The target document.
    /// - Returns: The landing.
    /// - Throws: ``PasteError/wouldCloseComponentLoop(_:)`` for a loop the slot write
    ///   would close, ``PasteError/slotRefused(_:)`` for anything else the planner refuses.
    static func landing(
        _ roots: [PenNode], at site: PasteSite, reserving: Set<String>, in document: EditableDocument
    ) throws -> SlotLanding {
        let planned: (plan: StructuralEditPlan, contentBase: String?)
        do {
            planned = try EditPlanner.planInsert(
                roots, into: site.parentID, at: site.index, reserving: reserving, in: document
            )
        } catch {
            if case let .componentLoop(loop)? = error.detail { throw PasteError.wouldCloseComponentLoop(loop) }
            throw PasteError.slotRefused(error)
        }
        var inline: Set<String> = []
        var pending = roots
        while let node = pending.popLast() {
            inline.insert(node.id)
            pending.append(contentsOf: node.kind.inlineChildren)
        }
        return SlotLanding(
            operations: planned.plan.operations,
            placedIDs: planned.plan.placedIDs,
            contentBase: planned.contentBase ?? "",
            inlineIDs: inline
        )
    }
}
