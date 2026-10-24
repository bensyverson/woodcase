//
//  SlotMove.swift
//  Woodcase
//

import Foundation

/// One move that reaches a slot: the nodes taken from where they are, placed where they
/// go, each slot they leave or join rewritten once.
///
/// ``EditPlanner/planMove(nodeIDs:into:at:keepingDrawnPlace:snapping:in:layout:)`` hands a
/// move here when a node or the target is in an instance's slot. The geometry is read
/// first, from the layout of the document as it stands, whose ids are the ones the nodes
/// answer to before any default content is copied; then each touched slot showing its
/// default content is copied into a fill; then the nodes move.
struct SlotMove {
    /// Where a node landed, to name it afterward.
    private enum Landing {
        /// A stored node, by its id.
        case stored(String)
        /// A node in a slot's fill, by its id there.
        case slot(refID: String, slotKey: String, localID: String)
    }

    /// The plan's session.
    let session: SlotEditSession

    /// Where the nodes go.
    let destination: SlotDestination

    /// The layout of the document as it stands.
    let layout: PenLayoutState

    /// A new container the nodes move into — Group's wrapper — put into its slot once the
    /// slots touched show fills, before anything moves; `nil` for a plain move.
    var wrapper: Wrapper?

    /// The new parent's geometry when the layout cannot read it — a wrapper not drawn
    /// yet; `nil` reads it from the layout.
    var fixedTarget: TargetGeometry?

    /// A container a move makes and fills: Group's wrapper in a slot's content.
    struct Wrapper {
        /// The container's JSON.
        var json: AnyCodable
        /// The outermost instance.
        var refID: String
        /// The slot frame's key.
        var slotKey: String
        /// The key of the container in the slot's content it goes into, or `nil` for the
        /// slot frame.
        var containerKey: String?
        /// Where among that parent's children it goes; `nil` puts it last.
        var index: Int?
    }

    /// The document, as it stands.
    private var document: EditableDocument {
        session.document
    }

    /// Plans the move.
    ///
    /// - Parameters:
    ///   - origins: The nodes, top-most only.
    ///   - index: Where the first goes.
    ///   - offset: How far they are carried on the canvas, or `nil`.
    ///   - snapping: How each new `x`/`y` is rounded.
    /// - Returns: The plan.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    mutating func plan(
        _ origins: [SlotOrigin],
        at index: Int?,
        keepingDrawnPlace offset: PenPoint?,
        snapping: PlacementSnapping
    ) throws(EditRefusal) -> StructuralEditPlan {
        let target = fixedTarget ?? targetGeometry()
        let writes = origins.map { placementWrites(of: $0, into: target, movedBy: offset, snapping: snapping) }
        copyTouchedDefaults(origins)
        if let wrapper {
            try insert(
                wrapper.json, refID: wrapper.refID, slotKey: wrapper.slotKey,
                containerKey: wrapper.containerKey, at: wrapper.index
            )
        }

        var deletes: [EditOperation] = []
        var stored: [EditOperation] = []
        var landings: [Landing] = []
        var renames: [String: String] = [:]
        // The index counts the parent's children with the moving nodes taken out
        // (RunLanding): every node of slot content leaves its fill before any lands, so in
        // a slot each next node goes one place after the last; in a stored parent each
        // single move or insert takes the index that keeps the run whole.
        var takenOut: [Int: AnyCodable] = [:]
        for (step, origin) in origins.enumerated() {
            guard case let .content(refID, key) = origin else { continue }
            let taken = try take(key, from: refID)
            session.taken.subtract(SlotJSON.allIDs(in: [taken]))
            takenOut[step] = taken
        }
        var storedLanding = try storedRunLanding(origins, at: index)
        for (step, origin) in origins.enumerated() {
            let at = index.map { $0 + step }
            switch (origin, destination) {
            case let (.document(id), .document(parent)):
                stored += try EditPlanner.planRunStep(
                    id, into: parent, at: storedLanding?.land(id), keepingDrawnPlace: offset, snapping: snapping,
                    in: document, layout: layout
                )
                landings.append(.stored(id))

            case let (.document(id), .slot(refID, slotKey, containerKey)):
                let node = try Self.patched(storedSubtree(id), with: writes[step], address: id, in: document)
                session.taken.subtract(document.collectInsertedIDs(in: node))
                let json = try encoded(node, address: id)
                let base = session.contentBase(refID: refID, slotKey: slotKey)
                let kept = SlotJSON.keepingIDs(json, base: base, taken: &session.taken, renames: &renames)
                try insert(kept, refID: refID, slotKey: slotKey, containerKey: containerKey, at: at)
                deletes += deletion(of: id)
                landings.append(.slot(refID: refID, slotKey: slotKey, localID: SlotJSON.id(of: kept) ?? id))

            case let (.content(_, key), _):
                guard let taken = takenOut[step] else { throw Self.unreadable(key) }
                let moved = try Self.patched(taken, with: writes[step], address: key, in: document)
                switch destination {
                case let .slot(toRef, slotKey, containerKey):
                    let base = session.contentBase(refID: toRef, slotKey: slotKey)
                    let kept = SlotJSON.keepingIDs(moved, base: base, taken: &session.taken, renames: &renames)
                    try insert(kept, refID: toRef, slotKey: slotKey, containerKey: containerKey, at: at)
                    landings.append(.slot(refID: toRef, slotKey: slotKey, localID: SlotJSON.id(of: kept) ?? key))
                case let .document(parent):
                    let kept = SlotJSON.keepingIDs(moved, base: "", taken: &session.taken, renames: &renames)
                    guard let node = SlotJSON.node(from: kept) else { throw Self.unreadable(key) }
                    let index = storedLanding?.land(node.id)
                    stored.append(.insertNode(EditOperation.InsertNode(node: node, parentID: parent, index: index)))
                    landings.append(.stored(node.id))
                }
            }
        }

        let overrides = session.writeOperations()
        // An insert's index is right only once the run's edits before it have landed;
        // the run's index was checked by its landing.
        try validate(overrides + stored.compactMap(\.unindexedInsert), address: origins.first.map(describe) ?? "")
        return StructuralEditPlan(
            operations: deletes + overrides + stored,
            placedIDs: landings.map(expandedID),
            renamedIDs: session.renamedIDs,
            materializedSlotIDs: session.materializedSlotIDs
        )
    }

    /// The landing of the run's nodes in a stored destination, or `nil` for a slot, where
    /// every node of slot content is taken out of its fill before any lands.
    ///
    /// - Parameters:
    ///   - origins: The nodes, top-most only.
    ///   - index: Where the first goes, counted without the moving nodes.
    /// - Throws: ``EditRefusal`` for an index past the children left once the run is out.
    private func storedRunLanding(_ origins: [SlotOrigin], at index: Int?) throws(EditRefusal) -> RunLanding? {
        guard case let .document(parent) = destination else { return nil }
        let ids = origins.compactMap { origin -> String? in
            guard case let .document(id) = origin else { return nil }
            return id
        }
        return try EditPlanner.runLanding(
            at: index, in: parent, moving: ids, address: origins.first.map(describe) ?? "", of: document
        )
    }

    // MARK: - Geometry

    /// What the new parent offers a node: its canvas map, its chain's flips, and whether
    /// it lays its children out.
    struct TargetGeometry {
        /// The canvas map of the parent's own coordinates.
        var map: EditPlanner.Transform
        /// The flip parity of the parent's chain.
        var flips: (x: Bool, y: Bool)
        /// Whether the parent lays out its children.
        var laysOut: Bool
    }

    /// The new parent's geometry, from the layout as it stands.
    private func targetGeometry() -> TargetGeometry {
        switch destination {
        case let .document(parent):
            return TargetGeometry(
                map: EditPlanner.canvasMap(of: parent, in: document, layout: layout) ?? .identity,
                flips: EditPlanner.flipParity(of: parent, in: document),
                laysOut: EditPlanner.laysOut(parent, in: document)
            )
        case let .slot(refID, slotKey, containerKey):
            let key = containerKey ?? slotKey
            guard let map = session.map(of: refID), let node = map.nodes[key]?.node else {
                return TargetGeometry(map: .identity, flips: (false, false), laysOut: false)
            }
            let expanded = map.expandedID(of: key)
            return TargetGeometry(
                map: canvasMap(ofExpanded: expanded) ?? .identity,
                flips: Self.flipParity(ofExpanded: expanded, in: layout),
                laysOut: Self.laysOut(node)
            )
        }
    }

    /// The writes that keep a node's drawn size, and its drawn place given an offset.
    private func placementWrites(
        of origin: SlotOrigin,
        into target: TargetGeometry,
        movedBy offset: PenPoint?,
        snapping: PlacementSnapping
    ) -> [String: AnyCodable] {
        guard let subject = subject(of: origin) else { return [:] }
        let absolute = subject.node.common.layoutPosition == .absolute
        let placing: EditPlanner.Placing? = target.laysOut ? (absolute ? .absolute : nil) : .free
        guard let offset, let placing else {
            return EditPlanner.keptSizeWrites(
                of: subject.node, drawnSize: subject.drawnSize, laidOut: target.laysOut && !absolute
            )
        }
        return EditPlanner.placementWrites(
            of: subject, newParentMap: target.map, newParentFlips: target.flips,
            placing: placing, movedBy: offset, snapping: snapping
        )
    }

    /// A node as the layout drew it, or `nil` for a stored move — which the single-move
    /// planner places — and for a node the layout did not draw.
    private func subject(of origin: SlotOrigin) -> EditPlanner.PlacementSubject? {
        switch origin {
        case let .document(id):
            guard case .slot = destination, let node = document.node(id: id) else { return nil }
            let parent = document.parentID(of: id)
            let expanded = document.expandedID(of: .node(id: id))
            guard let drawn = canvasMap(ofExpanded: expanded),
                  let parentMap = EditPlanner.canvasMap(of: parent, in: document, layout: layout)
            else { return nil }
            return EditPlanner.PlacementSubject(
                node: node, drawn: drawn, drawnSize: layout.rects[expanded]?.drawnSize,
                oldParentMap: parentMap, oldParentFlips: EditPlanner.flipParity(of: parent, in: document)
            )
        case let .content(refID, key):
            guard let map = session.map(of: refID), let entry = map.nodes[key], let parentKey = entry.parentKey
            else { return nil }
            let expanded = map.expandedID(of: key)
            let parent = map.expandedID(of: parentKey)
            guard let drawn = canvasMap(ofExpanded: expanded), let parentMap = canvasMap(ofExpanded: parent)
            else { return nil }
            return EditPlanner.PlacementSubject(
                node: entry.node, drawn: drawn, drawnSize: layout.rects[expanded]?.drawnSize,
                oldParentMap: parentMap, oldParentFlips: Self.flipParity(ofExpanded: parent, in: layout)
            )
        }
    }

    /// The canvas map of a node of the expanded document.
    private func canvasMap(ofExpanded id: String) -> EditPlanner.Transform? {
        PenLayoutEngine.canvasPlacement(of: id, in: layout.document, layoutRects: layout.rects)?.transform
    }

    /// Whether a node and its ancestors in the expanded document flip, taken together.
    ///
    /// - Parameters:
    ///   - id: The node's expanded id.
    ///   - layout: The layout, whose document is the expanded one.
    static func flipParity(ofExpanded id: String, in layout: PenLayoutState) -> (x: Bool, y: Bool) {
        var pending = layout.document.children.reversed().map { (node: $0, parity: (x: false, y: false)) }
        while let (node, parent) = pending.popLast() {
            var parity = parent
            if node.common.flipX?.literalValue == true { parity.x.toggle() }
            if node.common.flipY?.literalValue == true { parity.y.toggle() }
            if node.id == id { return parity }
            pending.append(contentsOf: node.kind.inlineChildren.reversed().map { (node: $0, parity: parity) })
        }
        return (false, false)
    }

    /// Whether a node lays out its children: a frame whose layout is not `none`.
    static func laysOut(_ node: PenNode) -> Bool {
        guard case let .frame(data) = node.kind else { return false }
        return (data.layout ?? .horizontal) != .none
    }

    // MARK: - Moving

    /// Copies the default content of every slot the move touches into a fill.
    private func copyTouchedDefaults(_ origins: [SlotOrigin]) {
        var touched: [(refID: String, slotKey: String)] = []
        if case let .slot(refID, slotKey, _) = destination { touched.append((refID, slotKey)) }
        for case let .content(refID, key) in origins {
            guard let map = session.map(of: refID), let site = map.nodes[key]?.siteIndex else { continue }
            touched.append((refID, map.sites[site].slotKey))
        }
        for (refID, slotKey) in touched {
            _ = session.ensureFill(slotKey: session.current(slotKey, in: refID), in: refID)
        }
    }

    /// Takes a node of slot content out of its fill.
    private func take(_ key: String, from refID: String) throws(EditRefusal) -> AnyCodable {
        let current = session.current(key, in: refID)
        guard let map = session.map(of: refID), let entry = map.nodes[current], let index = entry.siteIndex,
              var fill = session.fill(of: map.sites[index]),
              let taken = SlotJSON.remove(entry.localID, from: &fill)
        else { throw Self.unreadable(key) }
        session.setFill(fill, of: map.sites[index])
        return taken
    }

    /// Puts a node into a slot, or a container in its content.
    private func insert(
        _ json: AnyCodable, refID: String, slotKey: String, containerKey: String?, at index: Int?
    ) throws(EditRefusal) {
        guard session.insert(json, refID: refID, slotKey: slotKey, containerKey: containerKey, at: index)
        else { throw Self.unreadable(slotKey) }
    }

    /// A stored node with its subtree.
    private func storedSubtree(_ id: String) throws(EditRefusal) -> PenNode {
        do {
            return try document.materializeSubtree(rootID: id)
        } catch {
            throw EditRefusal(error, address: id, in: document)
        }
    }

    /// The deletes a stored node's move into a slot makes: the node, and every connector
    /// attached to it or to anything inside it, which would be left naming nothing.
    private func deletion(of id: String) -> [EditOperation] {
        let connectors = EditPlanner.connectorIDs(attachedTo: Set(document.descendantIDs(of: id)), in: document)
        return (connectors + [id]).map { .deleteNode(EditOperation.DeleteNode(nodeID: $0)) }
    }

    /// The id a landed node answers to after the edit.
    private func expandedID(of landing: Landing) -> String {
        switch landing {
        case let .stored(id):
            // A stored node is selected by its own id, an instance among them.
            return id
        case let .slot(refID, slotKey, localID):
            guard let map = session.map(of: refID),
                  let site = map.site(slotKey: session.current(slotKey, in: refID))
            else { return refID + String(NodeAddress.separator) + localID }
            return map.expandedID(of: map.sites[site].contentPrefix + localID)
        }
    }

    /// How an origin is named in a refusal.
    private func describe(_ origin: SlotOrigin) -> String {
        switch origin {
        case let .document(id): id
        case let .content(refID, key): refID + String(NodeAddress.separator) + key
        }
    }

    /// Runs the document's own checks on the planned edits — the loop guard among them.
    private func validate(_ operations: [EditOperation], address: String) throws(EditRefusal) {
        do {
            for operation in operations {
                try document.validate(operation)
            }
        } catch {
            throw EditRefusal(error, address: address, in: document)
        }
    }

    // MARK: - Nodes in fills

    /// A node with placement writes applied: through the model, only when there are any.
    static func patched(
        _ json: AnyCodable, with writes: [String: AnyCodable], address: String, in document: EditableDocument
    ) throws(EditRefusal) -> AnyCodable {
        guard !writes.isEmpty else { return json }
        guard let node = SlotJSON.node(from: json) else { throw unreadable(address) }
        do {
            return try SlotJSON.json(of: NodePropertyCodec.setting(writes, on: node))
        } catch {
            throw EditRefusal(error, address: address, in: document)
        }
    }

    /// A stored node with placement writes applied.
    static func patched(
        _ node: PenNode, with writes: [String: AnyCodable], address: String, in document: EditableDocument
    ) throws(EditRefusal) -> PenNode {
        guard !writes.isEmpty else { return node }
        do {
            return try NodePropertyCodec.setting(writes, on: node)
        } catch {
            throw EditRefusal(error, address: address, in: document)
        }
    }

    /// A node encoded for a fill.
    private func encoded(_ node: PenNode, address: String) throws(EditRefusal) -> AnyCodable {
        do {
            return try SlotJSON.json(of: node)
        } catch {
            throw EditRefusal(error, address: address, in: document)
        }
    }

    /// The refusal for slot content the plan could not read back — a fill the model
    /// cannot decode.
    static func unreadable(_ address: String) -> EditRefusal {
        EditRefusal(
            code: .documentRefused,
            address: address,
            message: "\(address) is in a slot fill Woodcase can't read; nothing was changed."
        )
    }
}

private extension EditOperation {
    /// This operation without its index when it is an insert, to check against the
    /// document as it stands; `nil` otherwise.
    var unindexedInsert: EditOperation? {
        guard case var .insertNode(insert) = self else { return nil }
        insert.index = nil
        return .insertNode(insert)
    }
}
