//
//  EditableDocument+Address.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// The shortest-to-read address that always resolves back to a node: its full name
    /// path, with the id marker wherever a name alone would name another node too.
    ///
    /// ``namePath(of:)-(ResolvedNodeAddress)`` reads best but can be ambiguous: two
    /// siblings named `Title` both print `Board/Title`, which
    /// ``resolve(_:tags:)-(String,_)`` — and so `woodcase get` — refuses as matching two
    /// nodes. This is the same path with ``NodeAddress/marker(forID:)`` standing in for
    /// each segment the resolver could not tell apart by name:
    ///
    /// - a segment whose name a sibling shares (`Page/Board/#r1`), or that is a sibling's
    ///   id, since an id beats a name at every step;
    /// - a segment whose name cannot be a segment at all — missing, holding a `/`, or
    ///   beginning with `#` or `@` — as in ``namePath(of:)-(String)``;
    /// - the first segment, when the path from it would also match from some other node of
    ///   that name — a first segment may name any node in the document, not only a root
    ///   (`#S1/Item`).
    ///
    /// Inside a component instance the siblings are the ones the resolver steps among
    /// there, so two instances of one component named `Chip` print `Board/#Inst/Label`,
    /// and the steps through a nested instance are named as ``namePath(ofDescendant:in:)``
    /// names them. This is the string an editor copies to hand an agent or the CLI.
    ///
    /// - Parameter resolved: A resolved address.
    /// - Returns: An address that resolves to `resolved`.
    func address(of resolved: ResolvedNodeAddress) -> String {
        guard let path = cursorPath(to: resolved), let root = path.first else {
            return idAddress(of: resolved)
        }
        let rest = zip(path, path.dropFirst()).map { parent, child in
            addressSegment(for: child, among: steps(from: parent))
        }
        let rootName = componentNode(root.nodeID).map(pathSegment(of:)) ?? NodeAddress.marker(forID: root.nodeID)
        let named = joinedAddress([rootName] + rest)
        if (try? resolve(named)) == resolved { return named }
        let anchored = joinedAddress([NodeAddress.marker(forID: root.nodeID)] + rest)
        return (try? resolve(anchored)) == resolved ? anchored : idAddress(of: resolved)
    }
}

// MARK: - Building the path

private extension EditableDocument {
    /// The resolver's cursors from a stored root down to `resolved`, one per segment.
    func cursorPath(to resolved: ResolvedNodeAddress) -> [AddressCursor]? {
        let storedID = resolved.targetID
        guard nodes[storedID] != nil else { return nil }
        let stored = (Array(ancestors(of: storedID).reversed()) + [storedID])
            .map { AddressCursor(refChain: [], nodeID: $0) }
        guard case let .instanceDescendant(_, key) = resolved, let instance = stored.last else { return stored }
        var seen: Set<ResolvedNodeAddress> = []
        guard let inside = path(from: instance, to: resolved, key: key, seen: &seen) else { return nil }
        return stored + inside
    }

    /// The cursors below `cursor` leading to `target`, found depth-first along the steps
    /// a name may take (never the id-only skips).
    ///
    /// A nested instance is only stepped into when the target's key runs through it, which
    /// also bounds the walk through a component that places itself.
    func path(
        from cursor: AddressCursor,
        to target: ResolvedNodeAddress,
        key: String,
        seen: inout Set<ResolvedNodeAddress>
    ) -> [AddressCursor]? {
        for child in steps(from: cursor) where !child.skippedContainers {
            let resolved = child.resolved
            if resolved == target { return [child] }
            guard seen.insert(resolved).inserted else { continue }
            if isInstanceRoot(child), let childKey = resolved.descendantKey,
               !key.hasPrefix(childKey + String(NodeAddress.separator))
            {
                continue
            }
            if let rest = path(from: child, to: target, key: key, seen: &seen) {
                return [child] + rest
            }
        }
        return nil
    }

    /// Whether a cursor sits on a `ref`, which the walk steps through into its component.
    func isInstanceRoot(_ cursor: AddressCursor) -> Bool {
        guard case .ref? = (cursor.injected ?? componentNode(cursor.nodeID))?.kind else { return false }
        return true
    }

    /// One segment: the node's name when that name picks it alone out of `siblings`,
    /// otherwise its id marker.
    func addressSegment(for cursor: AddressCursor, among siblings: [AddressCursor]) -> String {
        let marker = NodeAddress.marker(forID: cursor.nodeID)
        guard let node = cursor.injected ?? componentNode(cursor.nodeID) else { return marker }
        let name = pathSegment(of: node)
        guard name != marker else { return marker }
        let matching = preferringIDMatches(siblings.filter { matches(cursor: $0, segment: name) }, segment: name)
        return matching.count == 1 && matching[0].resolved == cursor.resolved ? name : marker
    }

    /// The address written in id markers alone, which names every step by id.
    func idAddress(of resolved: ResolvedNodeAddress) -> String {
        let steps = [resolved.targetID] + (resolved.descendantKey?
            .split(separator: NodeAddress.separator).map(String.init) ?? [])
        return joinedAddress(steps.map(NodeAddress.marker(forID:)))
    }

    /// Segments joined into an address.
    func joinedAddress(_ segments: [String]) -> String {
        segments.joined(separator: String(NodeAddress.separator))
    }
}
