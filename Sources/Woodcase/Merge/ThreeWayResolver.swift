//
//  ThreeWayResolver.swift
//  Woodcase
//

import Foundation

/// Decides a three-way merge: what the local document becomes when an external
/// version of the same base is folded into it (`project/2026-10-04-three-way-diff-design.md`,
/// algorithm steps 2–4).
///
/// It reads the two change sets base→ours and base→theirs and resolves them key by key:
/// a key only the external side changed takes its value; a key only the local side
/// changed, or both changed alike, needs nothing; a key both changed differently keeps
/// the local value and is reported. Existence, placement, child order and the document
/// keys follow the same rule, with the exceptions the design records — a node one side
/// deleted and the other edited, an insert under a deleted node, a component the merge
/// still has an instance of.
///
/// The result is a ``MergeResolution``: a target state, not yet operations.
struct ThreeWayResolver {
    /// The common ancestor of both sides.
    let base: EditableDocument

    /// The local side, which the merge's operations will apply to.
    let ours: EditableDocument

    /// The external side being folded in.
    let theirs: EditableDocument

    /// What the local side changed since the base.
    var oursChanges = DocumentChanges()

    /// What the external side changed since the base.
    var theirsChanges = DocumentChanges()

    /// The local nodes the merge removes.
    var removed: Set<String> = []

    /// The external inserts the merge does not take, because their parent does not survive.
    var dropped: Set<String> = []

    /// The parent each node takes when it is not the one the local side gives it, and
    /// each external insert's parent; `.some(nil)` is the top level.
    var parentOf: [String: String?] = [:]

    /// The merged content of every node whose content is not the local one.
    var contents: [String: PenNode] = [:]

    /// The merged child list of every container whose list is not the local one.
    var childLists: [String: [String]?] = [:]

    /// The merged top-level order, when it is not the local one.
    var rootOrder: [String]?

    /// The document keys that take the external value.
    var documentKeys: Set<DocumentChangeKey> = []

    /// What the merge could not take from both sides, in the order it was found.
    var conflicts: [MergeConflict] = []

    /// Creates a resolver over three versions of one document.
    ///
    /// - Parameters:
    ///   - base: The common ancestor.
    ///   - ours: The local side.
    ///   - theirs: The external side.
    init(base: EditableDocument, ours: EditableDocument, theirs: EditableDocument) {
        self.base = base
        self.ours = ours
        self.theirs = theirs
    }

    /// Resolves the merge.
    ///
    /// - Returns: The merged state of everything the merge changes in the local document.
    mutating func run() -> MergeResolution {
        oursChanges = DocumentChanges(from: base, to: ours)
        theirsChanges = DocumentChanges(from: base, to: theirs)
        resolveExistence()
        resolveContent()
        resolveParents()
        keepComponentsForInstances()
        resolveChildLists()
        keepContainersHoldingChildren()
        resolveDocument()
        return assemble()
    }

    // MARK: - Shared queries

    /// Whether a node is in the merged document.
    ///
    /// - Parameter id: The node's id.
    func survives(_ id: String) -> Bool {
        if ours.nodes[id] != nil { return !removed.contains(id) }
        return theirs.nodes[id] != nil && base.nodes[id] == nil && !dropped.contains(id)
    }

    /// Whether a node's merged type can hold children, as the content merge will decide
    /// it: ours' type when ours changed the kind (or both added the node), else theirs'.
    ///
    /// - Parameter id: The node's id.
    func canHoldChildren(_ id: String) -> Bool {
        guard let local = ours.nodes[id] else { return theirs.nodes[id]?.kind.canHaveChildren ?? false }
        if let original = base.nodes[id], original.kind == local.kind, let external = theirs.nodes[id] {
            return external.kind.canHaveChildren
        }
        return local.kind.canHaveChildren
    }

    /// A node's parent in the merged document; `nil` for a top-level node.
    ///
    /// - Parameter id: The node's id.
    func finalParent(of id: String) -> String? {
        if let entry = parentOf[id] { return entry }
        return ours.nodes[id] != nil ? ours.parents[id] : theirs.parents[id]
    }

    /// Whether a side changed a node in a way that counts as editing it: its content, its
    /// parent, whether it declares children, or the order of the children it kept. A
    /// child joining is the child's edit, and a child leaving is not the container's.
    ///
    /// - Parameter change: The node's change from the base, held on both sides.
    func isEdited(_ change: NodeChange) -> Bool {
        guard change.existence == .kept else { return false }
        if change.keys.contains(where: { $0 != .children }) { return true }
        guard change.keys.contains(.children) else { return false }
        let before = change.from?.children ?? []
        let after = change.to?.children ?? []
        let common = Set(before).intersection(after)
        return before.filter(common.contains) != after.filter(common.contains)
    }

    /// Records a conflict.
    ///
    /// - Parameters:
    ///   - subject: What the conflict is about.
    ///   - kind: How the two sides collided.
    ///   - base: The base value, or `nil` if the base does not hold the subject.
    ///   - ours: The local value, or `nil` if the local side does not hold it.
    ///   - theirs: The external value, or `nil` if the external side does not hold it.
    mutating func report(
        _ subject: MergeConflict.Subject,
        _ kind: MergeConflict.Kind,
        base: AnyCodable? = nil,
        ours: AnyCodable? = nil,
        theirs: AnyCodable? = nil
    ) {
        conflicts.append(MergeConflict(subject: subject, kind: kind, base: base, ours: ours, theirs: theirs))
    }

    // MARK: - Result

    /// Gathers the merged state of every node that differs from the local one.
    private func assemble() -> MergeResolution {
        var resolution = MergeResolution(removed: removed, rootOrder: rootOrder, document: documentKeys, conflicts: conflicts)
        let touched = Set(contents.keys).union(parentOf.keys).union(childLists.keys)
        for id in touched where survives(id) {
            let local = ours.nodes[id]
            guard let node = contents[id] ?? local ?? theirs.nodes[id] else { continue }
            let children = childLists[id] ?? (local != nil ? ours.children[id] : theirs.children[id])
            let state = NodeChange.State(node: node, parentID: finalParent(of: id), children: children)
            if let local, state == NodeChange.State(node: local, parentID: ours.parents[id], children: ours.children[id]) {
                continue
            }
            resolution.nodes[id] = state
        }
        return resolution
    }
}
