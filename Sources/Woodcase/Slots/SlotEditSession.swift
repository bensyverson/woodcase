//
//  SlotEditSession.swift
//  Woodcase
//

import Foundation

/// One structural plan's rewrite of the slots it touches, kept until the plan is done.
///
/// A plan may take several nodes out of a fill, put them in another, and copy a default
/// content into a fill first. Each change rewrites the outermost instance's
/// `descendants` map in this session — never the document — and the walk that answers
/// "what does this slot hold now" reads the rewrite in progress
/// (``EditableDocument/slotMap(of:descendants:)``). At the end ``writeOperations()``
/// writes each changed key once, so a slot is one `children` override however many
/// changes reached it, and moves the connector ends that named default content a copy
/// renamed.
final class SlotEditSession {
    /// Where a node an id names lives.
    enum Place: Equatable {
        /// A node with storage of its own, outside any instance.
        case stored(String)

        /// A node inside an instance, by the outermost instance and the key it names it by.
        case inInstance(refID: String, key: String)
    }

    /// The document the plan is for, as it stands.
    let document: EditableDocument

    /// Expanded id before → after, for nodes a default content copy renamed.
    private(set) var renamedIDs: [String: String] = [:]

    /// The slot frames whose default content became a fill, by expanded id.
    private(set) var materializedSlotIDs: [String] = []

    /// Every id in use, the ones this plan draws included; read on first use.
    lazy var taken: Set<String> = document.idsInUse

    /// The rewritten `descendants` of each instance touched, by its `ref` node.
    private var entries: [String: SlotFillLocation.Entries] = [:]

    /// Each touched instance's `descendants` as it stands.
    private var original: [String: SlotFillLocation.Entries] = [:]

    /// The maps read so far, until their instance's map is rewritten.
    private var maps: [String: SlotMap] = [:]

    /// Starts a session.
    init(document: EditableDocument) {
        self.document = document
    }

    // MARK: - Reading

    /// The map of an instance as the session has rewritten it.
    func map(of refID: String) -> SlotMap? {
        if let cached = maps[refID] { return cached }
        let found = document.slotMap(of: refID, descendants: entries[refID])
        maps[refID] = found
        return found
    }

    /// Where the node an id names lives: a stored id, or an expanded id an editor holds.
    ///
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/addressNotFound``.
    func place(of id: String) throws(EditRefusal) -> Place {
        if document.node(id: id) != nil { return .stored(id) }
        let separator = NodeAddress.separator
        if let first = id.split(separator: separator).first.map(String.init),
           case .ref? = document.node(id: first)?.kind,
           let key = map(of: first)?.key(ofExpandedID: id)
        {
            return .inInstance(refID: first, key: key)
        }
        switch document.resolve(expandedID: id) {
        case let .node(found)?:
            return .stored(found)
        case let .instanceDescendant(refID, key)?:
            return .inInstance(refID: refID, key: key)
        case nil:
            throw EditRefusal(code: .addressNotFound, address: id, message: "No node has the id \(id).")
        }
    }

    /// The key a node answers to after the renames this session made.
    func current(_ key: String, in refID: String) -> String {
        let separator = String(NodeAddress.separator)
        let renamed = StructuralEditPlan(operations: [], renamedIDs: renamedIDs).renamed(refID + separator + key)
        return String(renamed.dropFirst(refID.count + separator.count))
    }

    // MARK: - Fills

    /// A site's fill as the session has rewritten it, or `nil` while it shows its default.
    func fill(of site: SlotMap.Site) -> [AnyCodable]? {
        site.location.fill(in: currentEntries(of: site.location.refID))
    }

    /// Writes a site's fill.
    func setFill(_ children: [AnyCodable]?, of site: SlotMap.Site) {
        rewrite(site.location.refID) { site.location.setFill(children, in: &$0) }
    }

    /// Rewrites one instance's `descendants`.
    func rewrite(_ refID: String, _ body: (inout SlotFillLocation.Entries) -> Void) {
        var current = currentEntries(of: refID)
        body(&current)
        entries[refID] = current
        maps[refID] = nil
    }

    /// One instance's `descendants` as the session has rewritten them.
    func currentEntries(of refID: String) -> SlotFillLocation.Entries {
        if let rewritten = entries[refID] { return rewritten }
        let stored = Self.storedEntries(of: refID, in: document)
        original[refID] = stored
        return stored
    }

    /// A site's fill, copying the default content into one first when the slot has none.
    ///
    /// - Parameters:
    ///   - slotKey: The slot frame's key.
    ///   - refID: The outermost instance.
    /// - Returns: The site after the copy, and its fill.
    func ensureFill(slotKey: String, in refID: String) -> (site: SlotMap.Site, fill: [AnyCodable])? {
        guard let map = map(of: refID), let index = map.site(slotKey: slotKey) else { return nil }
        let site = map.sites[index]
        if let fill = fill(of: site) { return (site, fill) }
        materialize(site, in: map)
        guard let after = self.map(of: refID), let again = after.site(slotKey: slotKey) else { return nil }
        return (after.sites[again], fill(of: after.sites[again]) ?? [])
    }

    /// Puts a node into a slot, or a container in its content, copying the slot's
    /// default content into a fill first.
    ///
    /// - Parameters:
    ///   - json: The node JSON.
    ///   - refID: The outermost instance.
    ///   - slotKey: The slot frame's key, as it was before this session renamed anything.
    ///   - containerKey: The container's key in the slot's content, or `nil` for the slot.
    ///   - index: Where among the children it goes; `nil` puts it last.
    /// - Returns: `false` when the slot or the container is not there.
    @discardableResult
    func insert(_ json: AnyCodable, refID: String, slotKey: String, containerKey: String?, at index: Int?) -> Bool {
        guard let (site, fill) = ensureFill(slotKey: current(slotKey, in: refID), in: refID),
              let map = map(of: refID)
        else { return false }
        let container = containerKey.flatMap { map.nodes[current($0, in: refID)]?.localID }
        var list = fill
        guard SlotJSON.insert(json, into: container, at: index, in: &list) else { return false }
        setFill(list, of: site)
        return true
    }

    /// The expanded-id prefix a slot's content answers to (`Filled/`, `HostInst/Nest/`).
    func contentBase(refID: String, slotKey: String) -> String {
        let prefix = map(of: refID).flatMap { map in
            map.site(slotKey: current(slotKey, in: refID)).map { map.sites[$0].contentPrefix }
        } ?? ""
        return refID + String(NodeAddress.separator) + prefix
    }

    // MARK: - Finishing

    /// The connectors the plan deletes, whose ends are not rewritten.
    var deletedConnectorIDs: Set<String> = []

    /// Every edit the session's rewrites make: ``overrideOperations()``, then
    /// ``connectorOperations()``.
    func writeOperations() -> [EditOperation] {
        overrideOperations() + connectorOperations()
    }

    /// The connector ends that named default content this session copied into a fill,
    /// rewritten to the copies (Penumbra spec §13.5 rule 6): an end names a node by its id
    /// path, which for slot content is the expanded path the renames map.
    func connectorOperations() -> [EditOperation] {
        guard !renamedIDs.isEmpty else { return [] }
        let renames = StructuralEditPlan(operations: [], renamedIDs: renamedIDs)
        return document.nodeIDsInDocumentOrder().compactMap { id in
            guard !deletedConnectorIDs.contains(id), case var .connection(data)? = document.node(id: id)?.kind
            else { return nil }
            let source = renames.renamed(data.source.path)
            let target = renames.renamed(data.target.path)
            guard source != data.source.path || target != data.target.path else { return nil }
            data.source.path = source
            data.target.path = target
            return .updateKind(EditOperation.UpdateKind(nodeID: id, kind: .connection(data)))
        }
    }

    /// The overrides that write every rewrite: one per changed key, in key order.
    func overrideOperations() -> [EditOperation] {
        var operations: [EditOperation] = []
        for refID in entries.keys.sorted() {
            let before = original[refID] ?? Self.storedEntries(of: refID, in: document)
            let after = entries[refID] ?? [:]
            for key in Set(before.keys).union(after.keys).sorted() {
                let old = before[key] ?? [:]
                let new = after[key] ?? [:]
                guard old != new else { continue }
                let properties = new.filter { old[$0.key] != $0.value }
                let unset = old.keys.filter { new[$0] == nil }.sorted()
                operations.append(.overrideDescendant(EditOperation.OverrideDescendant(
                    refNodeID: refID, descendantID: key, properties: properties, unset: unset
                )))
            }
        }
        return operations
    }

    // MARK: - Private

    /// An instance's stored `descendants`, as entries.
    private static func storedEntries(of refID: String, in document: EditableDocument) -> SlotFillLocation.Entries {
        guard case let .ref(data)? = document.node(id: refID)?.kind else { return [:] }
        return (data.descendants ?? [:]).mapValues(\.properties)
    }

    /// Copies a site's default content into a fill: its overrides folded in, fresh ids,
    /// and the keys that named the default content removed, since nothing they name is
    /// drawn any more.
    private func materialize(_ site: SlotMap.Site, in map: SlotMap) {
        let separator = String(NodeAddress.separator)
        let base = map.refID + separator + site.contentPrefix
        var renames: [String: String] = [:]
        var localIDs: [String] = []
        var fill: [AnyCodable] = []
        for node in site.frame.kind.inlineChildren {
            let local = Self.strippingPrefix(String(site.frame.id.dropLast(site.componentSlotID.count)), from: node)
            localIDs.append(contentsOf: document.collectInsertedIDs(in: local))
            guard let json = try? SlotJSON.json(of: local) else { continue }
            fill.append(SlotJSON.renumbered(json, oldBase: base, newBase: base, taken: &taken, renames: &renames))
        }
        let ownerPrefix = String(site.location.key.dropLast(site.componentSlotID.count))
        rewrite(map.refID) { entries in
            site.location.modifyMap(in: &entries) { owner in
                for key in owner.keys where Self.names(key, anyOf: localIDs, under: ownerPrefix) {
                    owner.removeValue(forKey: key)
                }
            }
            site.location.setFill(fill, in: &entries)
        }
        renamedIDs.merge(renames) { _, new in new }
        materializedSlotIDs.append(map.expandedID(of: site.slotKey))
    }

    /// Whether a `descendants` key names one of some nodes, or a node inside one.
    private static func names(_ key: String, anyOf ids: [String], under prefix: String) -> Bool {
        ids.contains { id in
            let named = prefix + id
            return key == named || key.hasPrefix(named + String(NodeAddress.separator))
        }
    }

    /// A prepared node and its inline children with an id prefix taken off.
    private static func strippingPrefix(_ prefix: String, from node: PenNode) -> PenNode {
        PenTreeRewrite.rewrite(node, context: ()) { current, _ in
            let id = current.id.hasPrefix(prefix) ? String(current.id.dropFirst(prefix.count)) : current.id
            return .descend(PenNode(id: id, common: current.common, kind: current.kind, extras: current.extras), ())
        } ?? node
    }
}
