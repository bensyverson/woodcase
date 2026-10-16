//
//  PenClip+PasteLoops.swift
//  Woodcase
//

import Foundation

extension PenClip {
    /// Refuses a paste that would make components contain each other (``ComponentLoop``).
    ///
    /// The graph read is the target's after the paste: its components, own and imported,
    /// with every component the paste brings — the definitions and any component among
    /// the copies — under their new ids. A loop closes in one of two ways:
    ///
    /// - **Into a component**: a parent copies land in is a component, or inside one, and
    ///   something the copies landing there render reaches back to it. An edge between two
    ///   members of a loop the target already holds closes nothing new, as the loop guard
    ///   on ``EditableDocument`` reads it.
    /// - **Among what the paste brings**: a component it brings reaches back to itself, as
    ///   a clip of a document that already held a loop would.
    ///
    /// The same check guards every insert as it is applied; running it here refuses the
    /// paste as a whole, before anything is written, naming the loop by component name.
    ///
    /// - Parameters:
    ///   - content: The copied roots, rewritten, with their new ids.
    ///   - definitions: The definitions the paste inserts, rewritten, with their new ids.
    ///   - parentIDs: Where each copy lands, in the same order; `nil` for the canvas.
    ///   - theirs: The target's components, own and imported, by id.
    ///   - document: The target document.
    /// - Throws: ``PasteError/wouldCloseComponentLoop(_:)``.
    static func refuseComponentLoops(
        content: [PenNode],
        definitions: [PenNode],
        parentIDs: [String?],
        among theirs: [String: PenNode],
        in document: EditableDocument
    ) throws {
        var registry = theirs
        var brought: [String] = []
        var pending = definitions + content
        while let node = pending.popLast() {
            if node.common.reusable == true {
                registry[node.id] = node
                brought.append(node.id)
            }
            pending += node.kind.inlineChildren
        }
        var memo: [String: [String]] = [:]
        let targets: (String) -> [String] = { vertex in
            if let known = memo[vertex] { return known }
            var seen: Set<String> = []
            let found = registry[vertex].map(ComponentLoopIndex.renderedInSubtree(of:))?.filter { seen.insert($0).inserted } ?? []
            memo[vertex] = found
            return found
        }
        let name: (String) -> String = { registry[$0]?.common.name ?? $0 }

        var landing: [String: [PenNode]] = [:]
        var parents: [String] = []
        for (node, parentID) in zip(content, parentIDs) {
            guard let parentID else { continue }
            if landing[parentID] == nil { parents.append(parentID) }
            landing[parentID, default: []].append(node)
        }
        for parentID in parents {
            var seen: Set<String> = []
            let rendered = (landing[parentID] ?? []).flatMap(ComponentLoopIndex.renderedInSubtree(of:))
                .filter { seen.insert($0).inserted }
            let groups = document.componentLoopIndex.groupOf
            let sites = ([parentID] + document.componentAncestors(of: parentID)).filter { document.componentRegistry[$0] != nil }
            for site in sites {
                for start in rendered {
                    if let group = groups[site], groups[start] == group { continue }
                    guard let walk = start == site ? [] : ComponentLoopIndex.path(from: start, to: site, targets: targets)
                    else { continue }
                    throw PasteError.wouldCloseComponentLoop(loop([site] + walk, name: name))
                }
            }
        }
        for component in brought.sorted() {
            for start in targets(component) {
                guard let walk = start == component ? [] : ComponentLoopIndex.path(from: start, to: component, targets: targets)
                else { continue }
                throw PasteError.wouldCloseComponentLoop(loop([component] + walk, name: name))
            }
        }
    }

    /// A loop from its cycle of component ids, named.
    private static func loop(_ cycle: [String], name: (String) -> String) -> ComponentLoop {
        ComponentLoop(members: cycle.map { ComponentLoop.Member(id: $0, name: name($0)) })
    }
}
