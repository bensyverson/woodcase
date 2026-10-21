//
//  FigmaNodeTree.swift
//  Woodcase
//

/// A Figma message's flat node list as a tree: each node by GUID, each parent's children in
/// layer order, and the roots a selection pastes.
///
/// A node names its parent and its place among its siblings in `parentIndex`: the parent's
/// GUID and a fractional-index `position` string. Siblings sort by position, compared byte
/// by byte, which puts the bottom layer first — Pen's child order. The roots are the
/// children of every page (`CANVAS`) that is not `internalOnly`; the internal canvas holds
/// what a selection depends on without showing it — component masters, styles, variables.
struct FigmaNodeTree {
    /// Every node the message creates or modifies, by GUID.
    private(set) var records: [FigmaGUID: KiwiRecord] = [:]
    /// Each parent's children, bottom layer first.
    private(set) var children: [FigmaGUID: [FigmaGUID]] = [:]
    /// The selected layers: each visible page's children, page by page.
    private(set) var roots: [FigmaGUID] = []

    /// The tree of a decoded `Message`.
    ///
    /// - Throws: ``FigmaImportError/malformedMessage(_:)`` when the message has no
    ///   `nodeChanges`, or a change has no GUID.
    init(message: KiwiRecord) throws(FigmaImportError) {
        guard let changes = message["nodeChanges"]?.arrayValue else { throw .malformedMessage("it has no nodeChanges") }
        var positions: [FigmaGUID: [UInt8]] = [:]
        var parents: [(child: FigmaGUID, parent: FigmaGUID)] = []
        for change in changes {
            guard let record = change.recordValue, let guid = FigmaGUID(record["guid"]) else {
                throw .malformedMessage("a node change has no guid")
            }
            if record["phase"]?.enumName == "REMOVED" { continue }
            records[guid] = record
            if let parent = FigmaGUID(record["parentIndex"]?["guid"]) {
                parents.append((guid, parent))
                positions[guid] = Array((record["parentIndex"]?["position"]?.stringValue ?? "").utf8)
            }
        }
        for (child, parent) in parents {
            children[parent, default: []].append(child)
        }
        func precedes(_ lhs: FigmaGUID, _ rhs: FigmaGUID) -> Bool {
            let left = positions[lhs] ?? [], right = positions[rhs] ?? []
            if left != right { return left.lexicographicallyPrecedes(right) }
            return (lhs.sessionID, lhs.localID) < (rhs.sessionID, rhs.localID)
        }
        for parent in children.keys {
            children[parent]?.sort(by: precedes)
        }
        let pages = records.filter { _, record in
            record["type"]?.enumName == "CANVAS" && record["internalOnly"]?.boolValue != true
        }.keys.sorted(by: precedes)
        roots = pages.flatMap { children[$0] ?? [] }
    }

    /// The node's type, as the schema's `NodeType` names it.
    func type(of guid: FigmaGUID) -> String {
        records[guid]?["type"]?.enumName ?? ""
    }

    /// Every node under `guid`, `guid` first, depth first, without entering an instance:
    /// an instance's content is its component's.
    func subtree(_ guid: FigmaGUID) -> [FigmaGUID] {
        var result: [FigmaGUID] = []
        var work = [guid]
        while let next = work.popLast() {
            result.append(next)
            guard type(of: next) != "INSTANCE" else { continue }
            work += (children[next] ?? []).reversed()
        }
        return result
    }
}
