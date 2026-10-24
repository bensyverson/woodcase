//
//  EditPlanner+Swap.swift
//  Woodcase
//

import Foundation

public extension EditPlanner {
    /// Plans swapping an instance to another component or variant, keeping each of its
    /// fills where it can (Penumbra spec §13.5 rule 14).
    ///
    /// Each fill the instance wrote moves to the new component's slot of the same name —
    /// matched by the slot frame's name and the names of the nested instances it sits in,
    /// so `List` finds `List` whatever its id — and a fill whose slot the new component
    /// lacks is dropped, its name in ``SwapPlan/droppedSlots`` for the swap's notice ("The
    /// content of slot *Actions* was removed"). Figma drops slot content on a variant
    /// switch; this is the answer to that complaint. The instance's other overrides are
    /// left as they are.
    ///
    /// An instance placed in another instance's slot swaps inside that fill, as one
    /// `children` override of the slot, the default content copied into a fill first when
    /// the slot shows it.
    ///
    /// ```swift
    /// let plan = try EditPlanner.planSwap(instanceID: "Filled", to: "ScreenDark", in: document)
    /// plan.droppedSlots   // ["Footer"]
    /// ```
    ///
    /// Refused for a node that is not an instance
    /// (``EditRefusal/Code/overrideOutsideInstance``), for an instance inside another
    /// that is not slot content (``EditRefusal/Code/insideInstance``), for a component the
    /// document does not define (``EditRefusal/Code/addressNotFound``), and for a swap
    /// that would make a component contain itself
    /// (``EditRefusal/Code/wouldCloseComponentLoop``).
    ///
    /// - Parameters:
    ///   - instanceID: The instance: its stored `ref` id, its expanded root id, or the
    ///     expanded id of an instance in a slot.
    ///   - componentID: The component to place instead.
    ///   - document: The document, as it stands.
    /// - Returns: The edits, to submit as one, and the slots kept and dropped by name.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planSwap(instanceID: String, to componentID: String, in document: EditableDocument) throws(EditRefusal) -> SwapPlan {
        guard document.reusableComponent(componentID) != nil else {
            throw EditRefusal(
                code: .addressNotFound, address: componentID, message: "No component has the id \(componentID)."
            )
        }
        let session = SlotEditSession(document: document)
        switch try session.place(of: instanceID) {
        case let .stored(id):
            guard case var .ref(data)? = document.node(id: id)?.kind else { throw notAnInstanceRefusal(instanceID) }
            let swap = swappedFills((data.descendants ?? [:]).mapValues(\.properties), of: data, to: componentID, in: document)
            data.ref = componentID
            data.descendants = swap.entries.isEmpty ? nil : swap.entries.mapValues { PenDescendantOverride(properties: $0) }
            let operations: [EditOperation] = [.updateKind(EditOperation.UpdateKind(nodeID: id, kind: .ref(data)))]
            try validating(operations, address: instanceID, in: document)
            return SwapPlan(operations: operations, keptSlots: swap.kept, droppedSlots: swap.dropped)

        case let .inInstance(refID, key):
            return try swapInFill(key, of: refID, to: componentID, in: session, address: instanceID)
        }
    }
}

extension EditPlanner {
    /// What a swap does to an instance's fills.
    struct FillSwap {
        /// The instance's `descendants`, each fill under its new slot's key.
        var entries: SlotFillLocation.Entries

        /// The names of the slots whose fills moved.
        var kept: [String] = []

        /// The names of the slots whose fills were dropped.
        var dropped: [String] = []
    }

    /// The id an instance is walked under when it is not one the document stores.
    static let swapProbeID = "\u{0}slot-swap-probe"

    /// Moves each fill an instance wrote to the new component's slot of the same name.
    ///
    /// - Parameters:
    ///   - entries: The instance's `descendants`.
    ///   - data: Its `ref` payload as it stands.
    ///   - componentID: The component it will place.
    ///   - document: The document.
    /// - Returns: The rewritten `descendants`, and what moved and what was dropped.
    static func swappedFills(
        _ entries: SlotFillLocation.Entries,
        of data: PenNode.RefData,
        to componentID: String,
        in document: EditableDocument
    ) -> FillSwap {
        var swap = FillSwap(entries: entries)
        let probe = { (data: PenNode.RefData) in
            PenNode(id: swapProbeID, common: PenNodeCommon(), kind: .ref(data))
        }
        guard let before = document.slotMap(ofInstance: probe(data)) else { return swap }
        let after = document.slotMap(ofInstance: probe(PenNode.RefData(ref: componentID)))
        let targets = (after?.sites ?? []).filter(\.location.hops.isEmpty)
        var used: Set<String> = []
        var moved: [(key: String, entry: [String: AnyCodable])] = []
        for site in before.sites where site.location.hops.isEmpty {
            let key = site.location.key
            guard let entry = swap.entries[key], entry[SlotJSON.childrenKey] != nil else { continue }
            swap.entries.removeValue(forKey: key)
            let path = slotPath(site, in: before)
            let name = path.last ?? key
            if let after, let match = targets.first(where: {
                !used.contains($0.location.key) && slotPath($0, in: after) == path
            }) {
                used.insert(match.location.key)
                moved.append((match.location.key, entry))
                swap.kept.append(name)
            } else {
                swap.dropped.append(name)
            }
        }
        for (key, entry) in moved {
            swap.entries[key] = (swap.entries[key] ?? [:]).merging(entry) { _, fill in fill }
        }
        return swap
    }

    /// A slot's name, after the names of the nested instances between it and its
    /// instance: what a slot of the new component must match.
    private static func slotPath(_ site: SlotMap.Site, in map: SlotMap) -> [String] {
        var names = [site.frame.common.name ?? site.componentSlotID]
        var cursor = map.nodes[site.slotKey]?.parentKey
        var seen: Set<String> = []
        while let key = cursor, seen.insert(key).inserted, let node = map.nodes[key] {
            if node.componentRootID != nil { names.insert(node.node.common.name ?? node.localID, at: 0) }
            cursor = node.parentKey
        }
        return names
    }

    /// Swaps an instance that is slot content, inside the fill that holds it.
    private static func swapInFill(
        _ key: String, of refID: String, to componentID: String, in session: SlotEditSession, address: String
    ) throws(EditRefusal) -> SwapPlan {
        guard let before = session.map(of: refID), let entry = before.nodes[key], entry.componentRootID != nil,
              let siteIndex = entry.siteIndex
        else { throw outsideSlotsRefusal(address) }
        let slotKey = before.sites[siteIndex].slotKey
        guard let (site, fill) = session.ensureFill(slotKey: session.current(slotKey, in: refID), in: refID),
              let localID = session.map(of: refID)?.nodes[session.current(key, in: refID)]?.localID,
              let json = SlotJSON.node(localID, in: fill),
              case let .ref(data)? = SlotJSON.node(from: .dictionary(json))?.kind
        else { throw SlotMove.unreadable(address) }
        let swap = swappedFills(SlotFillLocation.descendantEntries(of: json), of: data, to: componentID, in: session.document)
        var list = fill
        SlotJSON.replace(localID, in: &list) { node in
            node["ref"] = .string(componentID)
            if swap.entries.isEmpty {
                node.removeValue(forKey: SlotJSON.descendantsKey)
            } else {
                node[SlotJSON.descendantsKey] = .dictionary(swap.entries.mapValues { AnyCodable.dictionary($0) })
            }
        }
        session.setFill(list, of: site)
        let operations = session.writeOperations()
        try validating(operations, address: address, in: session.document)
        return SwapPlan(operations: operations, keptSlots: swap.kept, droppedSlots: swap.dropped)
    }

    /// The refusal for a swap of a node that is not an instance.
    private static func notAnInstanceRefusal(_ id: String) -> EditRefusal {
        EditRefusal(code: .overrideOutsideInstance, address: id, message: "\(id) is not an instance; only an instance swaps its component.")
    }
}
