//
//  EditableDocument+FillInstances.swift
//  Woodcase
//

import Foundation

/// The instances written inside slot fills, which no stored node holds.
///
/// A ref an instance writes into a slot is inline JSON in that instance's `descendants`
/// map, so ``instanceIDs(ofComponent:)``, which reads the flat store, cannot see it. It
/// still expands like any other instance, and breaks as loudly when its component goes,
/// so every guard that counts the instances a change would strand counts these too, and
/// a delete under ``EditOperation/DeleteNode/Instances/detach`` detaches them where they
/// stand (``FillInstanceDetacher``).
extension EditableDocument {
    /// Every instance of a component written inside a slot fill.
    ///
    /// Such an instance has no stored identity, so it is named by its expanded address:
    /// the stored ref that writes the fill, each instance the fill steps into, then its
    /// own id (`Card1/Btn2`, `Card1/Tag/Btn3`) — the id path `tree --expand` prints and
    /// ``resolve(_:tags:)-(String,_)`` reads. An instance inside the fill of another
    /// instance of the same component is left out: it goes with that one.
    ///
    /// ``instanceIDs(ofComponent:)`` answers the stored instances; the two together are
    /// every instance the document draws of the component.
    ///
    /// - Parameter componentID: The component's node id.
    /// - Returns: The addresses, their stored refs ordered by full name path as
    ///   ``instanceIDs(ofComponent:)`` orders them, each one's in key and tree order.
    public func instanceIDsInFills(ofComponent componentID: String) -> [String] {
        instanceIDsInFills(of: [componentID], outside: [])
    }

    /// The addresses of the instances of some components that slot fills write, the
    /// fills of some stored refs left out.
    ///
    /// - Parameters:
    ///   - components: The components.
    ///   - skipped: Stored refs whose fills are not read — ones a change removes.
    /// - Returns: The addresses, as ``instanceIDsInFills(ofComponent:)`` orders them.
    func instanceIDsInFills(of components: Set<String>, outside skipped: Set<String>) -> [String] {
        fillHosts(outside: skipped).flatMap { host in
            host.fills.flatMap { fill in
                FillInstanceDetacher.instances(of: components, in: fill.children, base: host.base)
            }
        }
    }

    /// The overrides that detach, in place, every instance of the components a delete
    /// removes that a surviving fill writes: one per stored ref and `descendants` key,
    /// carrying the key's whole new `children`.
    ///
    /// A fill on a ref the delete removes goes with it, and one on an instance the delete
    /// detaches as a stored node is detached by that expansion
    /// (``detachPlans(deleting:)``), so neither is rewritten here. Each override is an
    /// ordinary edit — recorded, replicated and undone like any other — and they run
    /// before the stored detaches, touching none of the nodes those plans read.
    ///
    /// - Parameters:
    ///   - op: The delete.
    ///   - plans: The stored detaches it makes, whose ids the fills' detaches avoid.
    /// - Returns: The overrides, empty for a delete that strands no fill instance or
    ///   is not under ``EditOperation/DeleteNode/Instances/detach``.
    func fillDetaches(
        deleting op: EditOperation.DeleteNode,
        besides plans: [PlannedDetach]
    ) -> [EditOperation.OverrideDescendant] {
        guard op.instances == .detach, nodes[op.nodeID] != nil else { return [] }
        let doomed = Set(descendantIDs(of: op.nodeID))
        let removed = doomed.filter { componentRegistry[$0] != nil }
        var taken = idsInUse
        for plan in plans {
            taken.formUnion(collectInsertedIDs(in: plan.subtree))
        }
        return fillDetaches(of: removed, outside: doomed.union(plans.map(\.refID)), avoiding: taken)
    }

    /// The overrides that detach, in place, every instance of some components a fill
    /// writes, the fills of some stored refs left out.
    ///
    /// - Parameters:
    ///   - components: The components whose instances to detach.
    ///   - skipped: Stored refs whose fills are not rewritten.
    ///   - taken: The ids the detaches may not take.
    /// - Returns: One override per stored ref and key whose fill changes.
    func fillDetaches(
        of components: Set<String>,
        outside skipped: Set<String>,
        avoiding taken: Set<String>
    ) -> [EditOperation.OverrideDescendant] {
        guard !components.isEmpty else { return [] }
        let hosts = fillHosts(outside: skipped)
        // Most documents write no instance of the component into any fill: answer them
        // without materializing the registry an expansion needs.
        guard hosts.contains(where: { host in
            host.fills.contains { !FillInstanceDetacher.instances(of: components, in: $0.children, base: host.base).isEmpty }
        }) else { return [] }

        var detacher = FillInstanceDetacher(
            components: components,
            registry: materializedComponents(),
            cache: PenRefExpander.ResolverCache(loops: componentLoopIndex),
            replica: crdtDocument?.peerID,
            taken: taken
        )
        var result: [EditOperation.OverrideDescendant] = []
        for host in hosts {
            for fill in host.fills {
                var found: [String] = []
                let rewritten = detacher.detaching(fill.children, base: host.base, found: &found)
                guard !found.isEmpty else { continue }
                result.append(EditOperation.OverrideDescendant(
                    refNodeID: host.refID,
                    descendantID: fill.key,
                    properties: [SlotJSON.childrenKey: .array(rewritten)]
                ))
            }
        }
        return result
    }

    /// A stored ref that writes slot fills, and the fills.
    struct SlotFillHost: Friendly {
        /// One fill: a `descendants` key and its `children`.
        struct Fill: Friendly {
            /// The key in the ref's `descendants` map.
            var key: String

            /// The fill's node JSONs.
            var children: [AnyCodable]
        }

        /// The stored `ref` node.
        var refID: String

        /// Its fills, keys sorted.
        var fills: [Fill]

        /// The expanded-id prefix the fills' nodes answer to (`Card1/`).
        var base: String {
            refID + String(NodeAddress.separator)
        }
    }

    /// Every stored ref that writes a slot fill, ordered by full name path, skipping some.
    ///
    /// - Parameter skipped: Stored refs to leave out.
    /// - Returns: The refs and their fills.
    func fillHosts(outside skipped: Set<String>) -> [SlotFillHost] {
        nodes
            .compactMap { id, node -> SlotFillHost? in
                guard !skipped.contains(id), case let .ref(data) = node.kind, let descendants = data.descendants
                else { return nil }
                let fills = descendants.keys.sorted().compactMap { key -> SlotFillHost.Fill? in
                    guard case let .array(children)? = descendants[key]?.properties[SlotJSON.childrenKey] else { return nil }
                    return SlotFillHost.Fill(key: key, children: children)
                }
                return fills.isEmpty ? nil : SlotFillHost(refID: id, fills: fills)
            }
            .sorted { (namePath(of: $0.refID), $0.refID) < (namePath(of: $1.refID), $1.refID) }
    }
}
