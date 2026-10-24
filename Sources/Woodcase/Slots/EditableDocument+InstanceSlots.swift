//
//  EditableDocument+InstanceSlots.swift
//  Woodcase
//

import Foundation

/// An instance's slots, read for Layers, the inspector and every slot menu, and the one
/// drop-target question a drag asks inside an instance.
///
/// Every answer is read from the instance as the expansion prepares it (``SlotMap``), so a
/// slot's content is exactly what is drawn: the fill, or the component's default content
/// with the instance's overrides folded in. Ids are the expanded ids an editor holds.
public extension EditableDocument {
    /// The slots an instance shows: those its component defines, at any depth of the
    /// component's own tree, in tree order. A slot of an instance nested in it is that
    /// instance's, read by its own id.
    ///
    /// ```swift
    /// document.slots(ofInstance: "Filled").map(\.id)                  // ["Filled/List"]
    /// document.slots(ofInstance: "PanelInst/PScr/Screen").map(\.id)   // ["PanelInst/PScr/List"]
    /// ```
    ///
    /// - Parameter id: The instance: its stored `ref` node, its expanded root id, or the
    ///   expanded id of an instance inside another or inside a fill.
    /// - Returns: The slots, empty for anything that is not an instance.
    func slots(ofInstance id: String) -> [InstanceSlot] {
        guard let (map, rootID) = instanceRoot(of: id) else { return [] }
        return map.sites.filter { $0.instanceRootID == rootID }.map { slot(of: $0, in: map) }
    }

    /// The slot whose frame has this expanded id, as the instance that holds it shows it.
    ///
    /// - Parameter id: The slot frame's expanded id (`Filled/List`).
    /// - Returns: The slot, or `nil` for any other node — a slot frame in a component's
    ///   own definition included, which is an ordinary frame there.
    func slot(_ id: String) -> InstanceSlot? {
        guard let (map, key) = instanceKey(of: id), let index = map.site(slotKey: key) else { return nil }
        return slot(of: map.sites[index], in: map)
    }

    /// The slot whose content holds a node, at any depth of that content — inside a frame
    /// in it, not inside an instance in it, whose nodes are that instance's.
    ///
    /// - Parameter id: The node's expanded id.
    /// - Returns: The innermost slot holding it, or `nil` for a slot frame itself, a node
    ///   of an instance outside its slots, and a node outside instances.
    func slot(containing id: String) -> InstanceSlot? {
        guard let (map, key) = instanceKey(of: id), let index = map.nodes[key]?.siteIndex else { return nil }
        return slot(of: map.sites[index], in: map)
    }

    /// Whether a container can take children — the drop-target question a drag, a paste
    /// and the creation tools ask.
    ///
    /// Inside an instance only its slots take children (Penumbra spec §13.5 rule 5): a
    /// slot frame at any depth — of the instance's component, of an instance nested in
    /// it, of an instance in one of its fills — and a frame or group inside a slot's
    /// content, which is the instance's own. Anything else inside an instance does not,
    /// its root included. Outside instances a frame, a group and the canvas do. A drop
    /// that would close a component loop is a separate question
    /// (``componentLoop(moving:under:)``).
    ///
    /// - Parameter containerID: A stored id, an expanded id, or `nil` for the canvas.
    /// - Returns: Whether children can go there.
    func acceptsChildren(_ containerID: String?) -> Bool {
        guard let containerID else { return true }
        if let node = node(id: containerID) { return SlotDestination.isContainer(node) }
        return (try? SlotDestination(containerID, in: SlotEditSession(document: self))) != nil
    }
}

extension EditableDocument {
    /// The map of the outermost instance an expanded id is inside, and the key it names.
    func instanceKey(of id: String) -> (map: SlotMap, key: String)? {
        guard let first = id.split(separator: NodeAddress.separator).first.map(String.init),
              first != id, case .ref? = node(id: first)?.kind,
              let map = slotMap(of: first), let key = map.key(ofExpandedID: id)
        else { return nil }
        return (map, key)
    }

    /// The map an instance is in, and the expanded id of the instance's root.
    private func instanceRoot(of id: String) -> (map: SlotMap, rootID: String)? {
        if case .ref? = node(id: id)?.kind, let map = slotMap(of: id) {
            return (map, expandedID(of: .node(id: id)))
        }
        if case let .node(refID)? = resolve(expandedID: id), case .ref? = node(id: refID)?.kind,
           let map = slotMap(of: refID)
        {
            return (map, expandedID(of: .node(id: refID)))
        }
        guard let (map, key) = instanceKey(of: id), map.nodes[key]?.componentRootID != nil else { return nil }
        return (map, map.expandedID(of: key))
    }

    /// One site, as the public read gives it.
    private func slot(of site: SlotMap.Site, in map: SlotMap) -> InstanceSlot {
        let state: InstanceSlot.State = !site.isFilled ? .default : (site.contentKeys.isEmpty ? .empty : .filled)
        let suggested: [String] = if case let .frame(data) = site.frame.kind { data.slot ?? [] } else { [] }
        return InstanceSlot(
            id: map.expandedID(of: site.slotKey),
            instanceID: site.instanceRootID,
            refID: map.refID,
            name: site.frame.common.name ?? site.componentSlotID,
            componentID: site.componentID,
            componentSlotID: site.componentSlotID,
            state: state,
            contentIDs: site.contentKeys.map(map.expandedID(of:)),
            suggestedComponents: suggested.map { id in
                InstanceSlot.SuggestedComponent(id: id, name: reusableComponent(id).map { $0.common.name ?? id })
            }
        )
    }
}
