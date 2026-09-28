//
//  EditableDocument+Addressing.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// Resolves an address string to the node — or instance descendant — it names.
    ///
    /// ## Matching
    ///
    /// A path segment matches a node whose **id** equals the segment or whose
    /// **name** (`common.name`) equals it; a segment written `#ALu8G` matches by id
    /// only. Segments are consecutive parent→child steps, but the *first* segment may
    /// be any node in the document, not only a root — so `Header/Title` is a legal
    /// address for `Dashboard/Header/Title`. A node with no name is addressable only
    /// by its id, plain or behind the `#` marker.
    ///
    /// At every segment an id match beats a name match, so an address written in ids
    /// is never ambiguous — a node named after another node's id cannot shadow it.
    ///
    /// ## Stepping into a component instance
    ///
    /// When a segment resolves to a `ref` node and segments remain, the ref stands in
    /// for the component's root and the remainder resolves among the component's
    /// children — the component root is not a segment of its own. Nested refs recurse
    /// the same way.
    ///
    /// Inside an instance, an **id** may also skip the containers between the component
    /// root and the node: `Card1/Btn02` names the `ref` `Btn02` however deeply the
    /// component nests it. That is not a second grammar — it is the one the
    /// `descendants` map already uses, and the id-path `tree --expand` prints. A
    /// **name** never skips a step, so a repeated name deeper in a component cannot
    /// make a name path ambiguous. The result is
    /// ``ResolvedNodeAddress/instanceDescendant(refID:descendantKey:)``, whose key is
    /// exactly what the format writes in `descendants`. Everything else resolves to
    /// ``ResolvedNodeAddress/node(id:)`` — including a `ref` node at the end of a path,
    /// which is a node like any other.
    ///
    /// A child the instance **injected** into a component's slot frame is addressed the
    /// same way, and by the same id path `tree --expand` prints: `Inst0/Note0` by id,
    /// `Page/Filled/Body/Note` by name — through the slot frame, because a name never
    /// skips a step. Such a node exists only inside the instance's override, so a write
    /// to it is an override on the instance keyed exactly as
    /// ``PenRefExpander`` applies it: the injected node's own id, and the id path
    /// through an injected `ref` for a node inside the component it places.
    ///
    /// ## Tags
    ///
    /// `@hero` looks `hero` up in `tags`, the map a batch builds as it creates nodes.
    /// The value is a node id.
    ///
    /// A tag composes with a path. `@hero/Title` resolves the tag, then walks the
    /// remaining segments from there exactly as a path address does — component
    /// instances included, so `@card/Label` lands on the instance descendant. The tag
    /// is a starting point, not a whole address.
    ///
    /// - Parameters:
    ///   - address: The address as written.
    ///   - tags: Tag name → node id, for `@tag` addresses. Empty by default.
    /// - Returns: The resolved target.
    /// - Throws: ``EditingError/ambiguousAddress(address:candidates:)`` when more than
    ///   one target matches the whole address, listing every candidate by id and full
    ///   name path; ``EditingError/addressNotFound(address:nearMisses:)`` when none
    ///   does — including a malformed address, an unknown tag, and a tag pointing at a
    ///   node that is gone — listing every node whose name equals the last segment.
    func resolve(_ address: String, tags: [String: String] = [:]) throws -> ResolvedNodeAddress {
        guard let parsed = NodeAddress(address) else {
            throw EditingError.addressNotFound(address: address, nearMisses: [])
        }
        return try resolve(parsed, tags: tags)
    }

    /// Resolves a parsed address to the node — or instance descendant — it names.
    ///
    /// The semantics are described on ``resolve(_:tags:)-(String,_)``; this overload
    /// exists for callers that have already parsed, such as a batch runner holding a
    /// list of operations.
    ///
    /// - Parameters:
    ///   - address: The parsed address.
    ///   - tags: Tag name → node id, for `@tag` addresses. Empty by default.
    /// - Returns: The resolved target.
    /// - Throws: ``EditingError/ambiguousAddress(address:candidates:)`` or
    ///   ``EditingError/addressNotFound(address:nearMisses:)``.
    func resolve(_ address: NodeAddress, tags: [String: String] = [:]) throws -> ResolvedNodeAddress {
        let written = address.description

        switch address {
        case let .tag(name, path):
            guard let id = tags[name], nodes[id] != nil else {
                throw EditingError.addressNotFound(address: written, nearMisses: [])
            }
            guard !path.isEmpty else { return .node(id: id) }
            return try resolveWalk(
                from: [AddressCursor(refChain: [], nodeID: id)],
                through: path, written: written, missing: name
            )

        case let .path(segments):
            guard let first = segments.first else {
                throw EditingError.addressNotFound(address: written, nearMisses: [])
            }
            if address.isBare, let direct = directIDMatch(for: first) {
                return direct
            }
            return try resolveWalk(segments: segments, first: first, written: written)
        }
    }
}

// MARK: - Walking

private extension EditableDocument {
    /// The id-first result for a bare segment, or `nil` if no node has that id.
    func directIDMatch(for segment: String) -> ResolvedNodeAddress? {
        let id = NodeAddress.forcedID(in: segment) ?? segment
        return nodes[id] == nil ? nil : .node(id: id)
    }

    /// Walks every segment, then reports the single match, the ambiguity, or the miss.
    ///
    /// The first segment may name any node in the document, so the walk starts from
    /// every node that answers to it.
    func resolveWalk(segments: [String], first: String, written: String) throws -> ResolvedNodeAddress {
        let seeds = preferringIDMatches(
            nodes.keys
                .filter { matches(nodeID: $0, segment: first) }
                .map { AddressCursor(refChain: [], nodeID: $0) },
            segment: first
        )
        return try resolveWalk(
            from: seeds, through: Array(segments.dropFirst()), written: written, missing: first
        )
    }

    /// Steps a set of cursors down a path, then reports the single match, the ambiguity,
    /// or the miss.
    ///
    /// A `@tag` address enters here with one seed — the node the tag names — so the
    /// segments after the tag mean exactly what they mean after any other first
    /// segment, the step into a component instance included.
    ///
    /// - Parameters:
    ///   - seeds: Where the walk starts.
    ///   - path: The segments still to step, which may be empty.
    ///   - written: The address as the caller wrote it, for the error.
    ///   - missing: The segment to look for near misses of when `path` is empty — the
    ///     seed segment, which is the only thing a one-segment address could have meant.
    /// - Returns: The resolved target.
    /// - Throws: ``EditingError/ambiguousAddress(address:candidates:)`` or
    ///   ``EditingError/addressNotFound(address:nearMisses:)``.
    func resolveWalk(
        from seeds: [AddressCursor],
        through path: [String],
        written: String,
        missing: String
    ) throws -> ResolvedNodeAddress {
        var cursors = seeds
        var stalled: (before: [AddressCursor], segment: String)?
        for segment in path {
            let before = cursors
            cursors = preferringIDMatches(
                cursors.flatMap(steps(from:)).filter { matches(cursor: $0, segment: segment) },
                segment: segment
            )
            if cursors.isEmpty {
                stalled = (before, segment)
                break
            }
        }

        let ranked = cursors
            .map { cursor -> (resolved: ResolvedNodeAddress, candidate: NodeAddressCandidate) in
                let resolved = cursor.resolved
                return (resolved, NodeAddressCandidate(id: resolved.address, path: namePath(of: resolved)))
            }
            .sorted { ($0.candidate.path, $0.candidate.id) < ($1.candidate.path, $1.candidate.id) }

        if ranked.count == 1 { return ranked[0].resolved }
        if ranked.count > 1 {
            throw EditingError.ambiguousAddress(address: written, candidates: ranked.map(\.candidate))
        }
        let segment = path.last ?? missing
        throw EditingError.addressNotFound(
            address: written,
            nearMisses: stalled.flatMap { instanceNearMisses(from: $0.before, segment: $0.segment) }
                ?? nearMisses(forLastSegment: segment)
        )
    }

    /// Keeps only the cursors that match a segment by id, if there are any.
    ///
    /// An id beats a name at every segment, not just a bare one, so an address
    /// written entirely in ids — the form `tree --expand` prints — can never be
    /// made ambiguous by a node that happens to be named after another node's id.
    func preferringIDMatches(_ cursors: [AddressCursor], segment: String) -> [AddressCursor] {
        let byID = cursors.filter { $0.nodeID == segment }
        return byID.isEmpty ? cursors : byID
    }

    /// Whether a node answers to a segment, by id (forced or not) or by name.
    func matches(nodeID: String, segment: String) -> Bool {
        if let forced = NodeAddress.forcedID(in: segment) { return nodeID == forced }
        if nodeID == segment { return true }
        return componentNode(nodeID)?.common.name == segment
    }

    /// Whether a cursor answers to a segment.
    ///
    /// A cursor the walk reached by skipping containers inside a component answers to
    /// its **id** alone. Names keep their strict parent→child meaning, so a component
    /// that repeats a name further down cannot turn a name path that resolved
    /// yesterday into an ambiguity today.
    ///
    /// An injected node carries its own payload, because the store has none to read a
    /// name from.
    func matches(cursor: AddressCursor, segment: String) -> Bool {
        guard cursor.skippedContainers else {
            guard let injected = cursor.injected else {
                return matches(nodeID: cursor.nodeID, segment: segment)
            }
            if let forced = NodeAddress.forcedID(in: segment) { return injected.id == forced }
            return injected.id == segment || injected.common.name == segment
        }
        return (NodeAddress.forcedID(in: segment) ?? segment) == cursor.nodeID
    }

    /// The cursors one step below the given one.
    ///
    /// A `ref` stands in for its component root, so its step lands on the component's
    /// children and extends the ref chain; every other node steps to its own children.
    ///
    /// The step into an instance also lands, **by id only**, on every node further down
    /// the component. That is what makes `Card1/Btn02` an address when the component
    /// nests `Btn02` inside a group: a `descendants` key names a node by id and says
    /// nothing about the containers above it, and the id-path `tree --expand` prints is
    /// that key. The walk stops at a nested `ref` — a ref holds no children of its own
    /// in the flat store — so a node inside *its* component is reached by stepping
    /// through it, one more key step deeper.
    ///
    /// Which component a nested `ref` stands in for is
    /// ``componentRoot(ofInstanceChain:)``'s answer, not the flat store's, because that
    /// is the answer ``PenRefExpander`` acts on. Three things it settles that reading
    /// `ref` would not: an instance that repoints one of its component's refs steps
    /// into the component it repointed at; a `ref` the instance *injected* carries its
    /// payload on itself, there being no store entry to ask about; and a reusable
    /// component that is itself a `ref` to another component is followed to the far end
    /// of that chain, which is the subtree the expander actually clones.
    func steps(from cursor: AddressCursor) -> [AddressCursor] {
        guard let node = cursor.injected ?? componentNode(cursor.nodeID) else { return [] }
        guard case .ref = node.kind else { return childCursors(of: cursor) }

        let chain = cursor.refChain + [cursor.nodeID]
        guard let target = componentRoot(ofInstanceChain: chain) else { return [] }
        return componentChildIDs(of: target).flatMap { childID -> [AddressCursor] in
            let child = AddressCursor(refChain: chain, nodeID: childID)
            return [child] + deepCursors(below: child).map {
                var skipped = $0
                skipped.skippedContainers = true
                return skipped
            }
        }
    }

    /// The cursors one ordinary step below the given one.
    ///
    /// Inside an instance the children an override *injects* replace the node's own —
    /// the substitution ``PenRefExpander`` makes — and an injected container carries
    /// its own children inline, there being no store to hold them. A `ref` has no
    /// children of its own at all: ``steps(from:)`` handles the step into one.
    func childCursors(of cursor: AddressCursor) -> [AddressCursor] {
        let node = cursor.injected ?? componentNode(cursor.nodeID)
        if case .ref = node?.kind { return [] }
        if let injected = injectedChildren(of: cursor.nodeID, insideInstances: cursor.refChain) {
            return injected.map {
                AddressCursor(refChain: cursor.refChain, nodeID: $0.id, injected: $0)
            }
        }
        if let node = cursor.injected {
            return node.kind.inlineChildren.map {
                AddressCursor(refChain: cursor.refChain, nodeID: $0.id, injected: $0)
            }
        }
        return componentChildIDs(of: cursor.nodeID).map {
            AddressCursor(refChain: cursor.refChain, nodeID: $0)
        }
    }

    /// Every cursor below the given one, in no particular order, stopping at nested
    /// `ref` nodes.
    ///
    /// The walk skips an id it has already seen, for the reason ``ancestors(of:)``
    /// gives: a batch applied one operation at a time can pass through a state whose
    /// child map is transiently cyclic, and resolving an address has to terminate
    /// either way.
    ///
    /// - Parameter cursor: The subtree root, which is not itself included.
    /// - Returns: The cursors beneath it.
    func deepCursors(below cursor: AddressCursor) -> [AddressCursor] {
        var result: [AddressCursor] = []
        var seen: Set<String> = [cursor.nodeID]
        var frontier = childCursors(of: cursor)
        while let next = frontier.popLast() {
            guard seen.insert(next.nodeID).inserted else { continue }
            result.append(next)
            frontier.append(contentsOf: childCursors(of: next))
        }
        return result
    }

    /// The instance addresses a segment names, when the walk stalled stepping into one.
    ///
    /// A **name** never skips a step inside a component, so `Inst/Title` misses where
    /// `Inst/Body/Title` lands — and the definition's own `Title`, which the ordinary
    /// near-miss list would offer, is the wrong node: the caller wanted the copy this
    /// instance draws, not the component's original. So when the failing step was a
    /// step *into* an instance, the answer is the full path through that instance's
    /// tree, which is both an address that resolves and a demonstration of the rule.
    ///
    /// - Parameters:
    ///   - cursors: The partial matches the failing step started from.
    ///   - segment: The segment that matched nothing.
    /// - Returns: One candidate per node of the instance whose own name is `segment`,
    ///   or `nil` when the step entered no instance, or the instance holds no such
    ///   name — in which case the ordinary near-miss list is the better answer.
    func instanceNearMisses(from cursors: [AddressCursor], segment: String) -> [NodeAddressCandidate]? {
        var instances: [String] = []
        for cursor in cursors {
            guard case .ref = componentNode(cursor.nodeID)?.kind else { continue }
            let refID = cursor.refChain.first ?? cursor.nodeID
            if !instances.contains(refID) { instances.append(refID) }
        }
        guard !instances.isEmpty else { return nil }

        let found = instances
            .flatMap { refID in
                addressableDescendantKeys(ofInstance: refID).compactMap { key -> NodeAddressCandidate? in
                    guard node(ofInstance: refID, descendantKey: key)?.common.name == segment
                    else { return nil }
                    return NodeAddressCandidate(
                        id: "\(refID)\(NodeAddress.separator)\(key)",
                        path: namePath(ofDescendant: key, in: refID)
                    )
                }
            }
            .sorted { ($0.path, $0.id) < ($1.path, $1.id) }
        return found.isEmpty ? nil : found
    }

    /// Nodes anywhere in the document whose name equals the address's last segment.
    func nearMisses(forLastSegment segment: String) -> [NodeAddressCandidate] {
        nodes
            .filter { $0.value.common.name == segment }
            .map { NodeAddressCandidate(id: $0.key, path: namePath(of: $0.key)) }
            .sorted { ($0.path, $0.id) < ($1.path, $1.id) }
    }
}

// MARK: - Cursor

private extension EditableDocument {
    /// One partial match during a walk: where it is, and which instances it is inside.
    ///
    /// `refChain` is empty while the walk is in the document's own tree. Its first
    /// element is the outermost `ref` node — a real node in the flat store — and every
    /// later element is a nested `ref` inside a component, which is exactly the
    /// prefixing the format's `descendants` keys use.
    struct AddressCursor {
        /// Ref node ids from outermost inward; empty in the document's own tree.
        var refChain: [String]

        /// The node this cursor sits on, in the flat store.
        var nodeID: String

        /// The node as an override wrote it, for a child an instance injected into a
        /// slot; `nil` for a node the flat store holds.
        var injected: PenNode?

        /// Whether the walk reached this node by skipping containers inside a
        /// component, which only an id segment may do.
        var skippedContainers: Bool = false

        /// The address this cursor stands for.
        var resolved: ResolvedNodeAddress {
            guard let outermost = refChain.first else { return .node(id: nodeID) }
            let key = (refChain.dropFirst() + [nodeID]).joined(separator: String(NodeAddress.separator))
            return .instanceDescendant(refID: outermost, descendantKey: key)
        }
    }
}
