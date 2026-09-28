//
//  EditableDocument+Guards.swift
//  Woodcase
//

import Foundation

/// Consequence guards: the checks an operation runs when its effect would reach
/// past the node it names.
///
/// Two operations can do damage a caller did not ask for. Deleting a reusable
/// component strands every instance of it, and an override can be dropped on the way
/// to the pixels — by naming a descendant the component does not have, or by carrying a
/// value the node it patches cannot decode, which leaves the *unpatched* node behind.
/// All of them refuse here, carrying what a message needs to name the remedy.
extension EditableDocument {
    // MARK: - Descendant walking

    /// A node's id followed by every descendant's, in tree order.
    ///
    /// - Parameter nodeID: The subtree root.
    /// - Returns: The root and its descendants. A node that is not in the document
    ///   returns just its own id.
    func descendantIDs(of nodeID: String) -> [String] {
        var result = [nodeID]
        for childID in componentChildIDs(of: nodeID) {
            result.append(contentsOf: descendantIDs(of: childID))
        }
        return result
    }

    // MARK: - Component instances

    /// Every `ref` node in the document that points at the given component.
    ///
    /// Includes refs nested inside other components' definitions — those expand
    /// through the outer component, so they break just as loudly as a ref on a page.
    ///
    /// Public because it is a question worth asking on its own, not only a guard:
    /// `woodcase get --instances` is this call and nothing else, reordered.
    ///
    /// - Parameter componentID: The component's node id.
    /// - Returns: The instances' ids, ordered by full name path so the list a caller
    ///   prints is stable across runs.
    public func instanceIDs(ofComponent componentID: String) -> [String] {
        nodes
            .filter { _, node in
                if case let .ref(refData) = node.kind { return refData.ref == componentID }
                return false
            }
            .map(\.key)
            .sorted { (namePath(of: $0), $0) < (namePath(of: $1), $1) }
    }

    /// The instances a delete would strand, refusing when it is not allowed to.
    ///
    /// A delete strands an instance when the deleted subtree defines a reusable
    /// component and a `ref` to that component survives outside the subtree. Under
    /// ``EditOperation/DeleteNode/Instances/refuse`` that is an error; under
    /// ``EditOperation/DeleteNode/Instances/detach`` the survivors come back so the
    /// caller can detach them before the delete lands.
    ///
    /// - Parameter op: The delete about to be applied.
    /// - Returns: The instances to detach first, empty when the delete strands none.
    /// - Throws: ``EditingError/componentHasInstances(componentID:instanceIDs:)``.
    func instancesToDetach(for op: EditOperation.DeleteNode) throws -> [String] {
        guard nodes[op.nodeID] != nil else { return [] }
        let doomed = Set(descendantIDs(of: op.nodeID))
        var stranded: [String] = []
        for componentID in doomedComponents(in: doomed, target: op.nodeID) {
            let survivors = instanceIDs(ofComponent: componentID).filter { !doomed.contains($0) }
            guard !survivors.isEmpty else { continue }
            guard op.instances == .detach else {
                throw EditingError.componentHasInstances(
                    componentID: componentID,
                    instanceIDs: survivors
                )
            }
            stranded.append(contentsOf: survivors)
        }
        return stranded
    }

    /// The reusable components inside a doomed subtree, the delete's own target first.
    ///
    /// The target leads because it is the node the caller named: when a delete strands
    /// instances of several components, that is the one to complain about first.
    private func doomedComponents(in doomed: Set<String>, target: String) -> [String] {
        var result = doomed.filter { componentRegistry[$0] != nil }.sorted()
        guard let index = result.firstIndex(of: target) else { return result }
        result.remove(at: index)
        return [target] + result
    }

    // MARK: - Override targets

    /// Refuses an override whose descendant key names nothing in the component.
    ///
    /// The format's own editor accepts such a key and silently does nothing, which is worse
    /// than an error: the caller reads back a stored override that will never apply.
    /// This lists what the component does contain instead.
    ///
    /// A ref whose component is not in ``componentRegistry`` — an unresolved import,
    /// say — is left alone: there is nothing to check the key against, and refusing
    /// would reject an edit that may well be correct.
    ///
    /// A key naming content the instance wrote into a slot itself is refused on its
    /// own terms: the node exists and draws, but Pen drops any override on it. An
    /// override *addressed* to such a node never reaches here as one — the batch planner
    /// rewrites it into the slot fill first (``slotFillRewrite(of:)``).
    ///
    /// - Parameter op: The override about to be applied.
    /// - Throws: ``EditingError/overrideOnOwnSlotContent(refID:descendantKey:slotPath:)``
    ///   or ``EditingError/overrideTargetNotFound(refID:descendantKey:candidates:)``.
    func validateOverrideTarget(_ op: EditOperation.OverrideDescendant) throws {
        guard case let .ref(refData) = nodes[op.refNodeID]?.kind else { return }
        guard reusableComponent(refData.ref) != nil else { return }

        if let slot = ownSlotPath(ofInstance: op.refNodeID, descendantKey: op.descendantID) {
            throw EditingError.overrideOnOwnSlotContent(
                refID: op.refNodeID, descendantKey: op.descendantID, slotPath: slot
            )
        }
        let keys = overridableDescendantKeys(ofInstance: op.refNodeID)
        guard !keys.contains(op.descendantID), !resolvesAsPen(op) else { return }
        let own = ownSlotContentKeys(ofInstance: op.refNodeID)

        throw EditingError.overrideTargetNotFound(
            refID: op.refNodeID,
            descendantKey: op.descendantID,
            // Only the keys an address can reach: a component *root* is patchable and
            // so belongs to `keys`, but `Card1/CardC` is not an address any resolver
            // accepts, and offering one teaches a form that does not work. The root's
            // own properties are written by overriding the instance itself. Content the
            // instance wrote into a slot itself is an address but no key Pen applies.
            candidates: addressableDescendantKeys(ofInstance: op.refNodeID)
                .filter { !own.contains($0) }
                .map { key in
                    NodeAddressCandidate(
                        id: "\(op.refNodeID)\(NodeAddress.separator)\(key)",
                        path: namePath(ofDescendant: key, in: op.refNodeID)
                    )
                }
        )
    }

    /// Refuses an override whose value the node it patches cannot take.
    ///
    /// ``PenNodePatcher/patchNode(_:with:)`` merges an override onto the component's
    /// node as raw JSON, and its answer to a merge that will not decode is the
    /// *unpatched* node — so a value of the wrong shape leaves an override that `get`
    /// confirms back forever and that never changes a pixel. This is the other half of
    /// ``validateOverrideTarget(_:)``: that one refuses a key naming nothing, this one
    /// refuses a value nothing can read.
    ///
    /// Each key is judged on its own, so the message can name the one that was wrong.
    /// Two entries are exempt. An override carrying a `type` key replaces the node whole
    /// rather than patching it, so there is no merge to fail; and a ref whose component
    /// is not in ``componentRegistry`` — an unresolved import — names no node this
    /// document can check the value against, exactly as ``validateOverrideTarget(_:)``
    /// leaves it alone.
    ///
    /// - Parameter op: The override about to be applied.
    /// - Throws: ``EditingError/overrideValueRejected(refID:descendantKey:key:expected:actual:)``.
    func validateOverrideValues(_ op: EditOperation.OverrideDescendant) throws {
        guard op.properties[PenDescendantOverride.typeKey] == nil,
              let definition = patchedDefinitionNode(
                  ofInstance: op.refNodeID, descendantKey: op.descendantID
              )
        else { return }

        for key in op.properties.keys.sorted() {
            let value = op.properties[key] ?? .null
            do {
                _ = try PenNodePatcher.patched(definition, with: [key: value])
            } catch {
                let field = NodePropertyCodec.fieldName(forRawKey: key)
                throw EditingError.overrideValueRejected(
                    refID: op.refNodeID,
                    descendantKey: op.descendantID,
                    key: key,
                    expected: NodePropertyCodec.expectedShape(of: field),
                    actual: NodePropertyCodec.actualShape(of: value, field: field, failure: error)
                )
            }
        }
    }

    /// The node inside a component that a `descendants` key patches.
    ///
    /// A key is one or more node ids joined by `/` — a node directly in the component,
    /// then the key within each nested ref's own component. Every one of those ids is a
    /// node of the flat store, because a component definition lives in the document
    /// like anything else, so the last segment names the node the override lands on.
    ///
    /// - Parameter descendantKey: The key as stored in a ref's `descendants` map.
    /// - Returns: The node it patches, or `nil` when the key names nothing.
    func definitionNode(forDescendantKey descendantKey: String) -> PenNode? {
        guard let last = descendantKey.split(separator: NodeAddress.separator).last else {
            return nil
        }
        return componentNode(String(last))
    }

    /// The node inside a component that an override on *this instance* patches.
    ///
    /// ``definitionNode(forDescendantKey:)`` answers from the key alone, which is all a
    /// key that has already been validated needs. This one asks first whether the ref's
    /// component is one this document holds: for an unresolved import the key belongs to
    /// a component Woodcase has never seen, so a node whose id happens to match it is
    /// not the node the override will patch — and anything that reads the definition to
    /// judge or reshape a value must not read that one.
    ///
    /// - Parameters:
    ///   - refNodeID: The instance's `ref` node id.
    ///   - descendantKey: The key inside its `descendants` map.
    /// - Returns: The node the override patches, or `nil` when the document cannot say.
    func patchedDefinitionNode(ofInstance refNodeID: String, descendantKey: String) -> PenNode? {
        guard case let .ref(refData) = nodes[refNodeID]?.kind,
              reusableComponent(refData.ref) != nil
        else { return nil }
        return node(ofInstance: refNodeID, descendantKey: descendantKey)
    }

    /// The name of the reusable component a node belongs to.
    ///
    /// - Parameter nodeID: A node inside a component definition.
    /// - Returns: The nearest reusable ancestor's name — the node's own if it is the
    ///   component root — or `nil` when the node is not inside one, or it is unnamed.
    func componentName(holding nodeID: String) -> String? {
        var current: String? = nodeID
        var seen: Set<String> = []
        while let id = current, seen.insert(id).inserted {
            if let node = componentNode(id), node.common.reusable == true { return node.common.name }
            current = componentParentID(of: id)
        }
        return nil
    }
}
