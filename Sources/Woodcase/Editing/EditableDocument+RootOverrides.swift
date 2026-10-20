//
//  EditableDocument+RootOverrides.swift
//  Woodcase
//

import Foundation

/// An instance's *root* overrides: the component root's own properties as this one
/// `ref` shows them.
///
/// A component instance has two surfaces and one address. `set` writes the ref node —
/// where it sits, whether it draws — and `override` with no descendant path writes what
/// the ref *shows*: the component root's width, its fills, its corner radius. The
/// format keeps them apart by keeping the ref's own keys reserved, so the same
/// separation is enforced here rather than left to a caller to remember.
extension EditableDocument {
    /// Applies an ``EditOperation/OverrideRoot`` operation.
    ///
    /// - Parameter op: The override operation parameters.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` if the ref node doesn't exist,
    ///   ``EditingError/notARefNode(id:)`` if the node is not a `ref`,
    ///   ``EditingError/rootOverrideKeyReserved(refID:key:reason:)`` for a key the ref
    ///   node carries for itself, or
    ///   ``EditingError/rootOverrideValueRejected(refID:key:expected:actual:)`` for a
    ///   value the component root cannot take.
    func applyOverrideRoot(_ op: EditOperation.OverrideRoot) throws {
        nodes[op.refNodeID] = try overriddenNode(for: op)

        // A root override can change the instance's size — invalidate its layout.
        invalidateLayoutCache(for: op.refNodeID, category: .layout)
    }

    /// The ref node an ``EditOperation/OverrideRoot`` would store, checked as
    /// ``applyOverrideRoot(_:)`` checks it, with nothing written.
    ///
    /// - Parameters:
    ///   - op: The override operation parameters.
    ///   - base: The ref node to merge into in place of the stored one: an earlier
    ///     preview of it (``previewNodes(for:)``); `nil` merges into the node as it stands.
    /// - Returns: The ref node with the root overrides merged in.
    /// - Throws: What ``applyOverrideRoot(_:)`` throws.
    func overriddenNode(for op: EditOperation.OverrideRoot, onto base: PenNode? = nil) throws -> PenNode {
        var (node, refData) = try requireRef(op.refNodeID, onto: base)
        try validateRootOverrideKeys(op)
        try validateRootOverrideValues(op)
        try refuseComponentLoops(closedBy: .overrideRoot(op))

        let overrides = Self.merging(
            op.properties, into: refData.rootOverrides ?? [:], removing: op.unset
        )
        refData.rootOverrides = overrides.isEmpty ? nil : overrides
        // A raw operation naming a Woodcase-owned key stores it on the ref's own metadata,
        // as a planned one does (rule 6).
        let moved = PenNode.movingRootNaturalKeys(node.common, refData)
        node.common = moved.common
        node.kind = .ref(moved.data)
        return node
    }

    /// Refuses a root override whose key the ref node reserves for itself.
    ///
    /// Written into the file, a reserved key is indistinguishable from the ref's own:
    /// `opacity` there *is* the instance's opacity, and `descendants` there is an
    /// override named `descendants` patching a property no node has. Both read back
    /// exactly as written and mean something the caller did not ask for, so they are
    /// refused at the write, where the other command can still be named.
    ///
    /// Unsetting is judged the same way: a reserved key was never storable, so asking
    /// to remove it is asking about the wrong surface.
    ///
    /// - Parameter op: The override about to be applied.
    /// - Throws: ``EditingError/rootOverrideKeyReserved(refID:key:reason:)``.
    func validateRootOverrideKeys(_ op: EditOperation.OverrideRoot) throws {
        for key in op.properties.keys.sorted() + op.unset {
            guard let reason = RootOverrideRefusal.refusing(key) else { continue }
            throw EditingError.rootOverrideKeyReserved(refID: op.refNodeID, key: key, reason: reason)
        }
    }

    /// Refuses a root override whose value the component root cannot take.
    ///
    /// The half of ``validateOverrideValues(_:)`` that applies to the root: a root
    /// override is merged onto the component's root node as raw JSON when the instance
    /// expands, and ``PenNodePatcher/patchNode(_:with:)``'s answer to a merge that will
    /// not decode is the *unpatched* node — an override that reads back forever and
    /// never draws.
    ///
    /// - Parameter op: The override about to be applied.
    /// - Throws: ``EditingError/rootOverrideValueRejected(refID:key:expected:actual:)``.
    func validateRootOverrideValues(_ op: EditOperation.OverrideRoot) throws {
        guard let root = componentRoot(ofInstance: op.refNodeID) else { return }

        for key in op.properties.keys.sorted() {
            let value = op.properties[key] ?? .null
            do {
                _ = try PenNodePatcher.patched(root, with: [key: value])
            } catch {
                let field = NodePropertyCodec.fieldName(forRawKey: key)
                throw EditingError.rootOverrideValueRejected(
                    refID: op.refNodeID,
                    key: key,
                    expected: NodePropertyCodec.expectedShape(of: field),
                    actual: NodePropertyCodec.actualShape(of: value, field: field, failure: error)
                )
            }
        }
    }

    /// The component root node an instance's root overrides patch.
    ///
    /// Read through ``effectiveRefData(of:insideInstances:)`` so that an instance which
    /// has been repointed answers with the component it points at now, and `nil` for a
    /// component this document does not hold — an unresolved import names a root no
    /// value can be judged against, exactly as a descendant override leaves one alone.
    ///
    /// - Parameter refNodeID: The instance's `ref` node id.
    /// - Returns: The component's root node, or `nil` when the document cannot say.
    func componentRoot(ofInstance refNodeID: String) -> PenNode? {
        guard let componentID = effectiveRefData(of: refNodeID, insideInstances: [])?.ref,
              reusableComponent(componentID) != nil
        else { return nil }
        return componentNode(componentID)
    }
}
