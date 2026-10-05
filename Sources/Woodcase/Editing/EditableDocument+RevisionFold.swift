//
//  EditableDocument+RevisionFold.swift
//  Woodcase
//

import Foundation

extension EditableDocument {
    /// The revision of a node, folding in its subtree and the components it renders.
    ///
    /// When the fold meets a component already on its chain, that component is in a
    /// cyclic group whose revision is not known yet: the groups are resolved
    /// (``resolveComponentCycles(reachableFrom:)``) and the fold starts again, reusing
    /// everything it memoized. Each restart resolves at least the group it met, so there
    /// are no more restarts than cyclic groups.
    ///
    /// - Parameter nodeID: The node to hash.
    /// - Returns: The revision, or `nil` for a node that is not in the document.
    func foldedRevision(of nodeID: String) -> String? {
        while true {
            switch fold(nodeID, markers: []) {
            case let .revision(revision): return revision
            case let .cycle(component): resolveComponentCycles(reachableFrom: component)
            }
        }
    }

    /// How one fold ended.
    enum FoldOutcome {
        /// The revision, or `nil` for a node not in the document.
        case revision(String?)

        /// The fold met this component already on its chain, in a group not resolved yet.
        case cycle(String)
    }

    /// Folds one node's revision.
    ///
    /// The fold runs from a work list rather than by recursion: a debug build reserved
    /// 2.2 KB a level, and a deep tree overflowed a Swift task's stack
    /// (`project/2026-09-26-debug-stack-depth.md`). Each node is still finished — and
    /// memoized — before its next sibling starts, as a recursive fold would.
    ///
    /// - Parameters:
    ///   - nodeID: The node to hash.
    ///   - markers: The members of the cyclic group being resolved, each folded in as a
    ///     marker naming it rather than by its revision. A node whose fold met a marker
    ///     is not memoized: its value is the group's working hash, not its revision.
    /// - Returns: The revision, or the component a fold with no markers met on its chain.
    func fold(_ nodeID: String, markers: Set<String>) -> FoldOutcome {
        var stack: [RevisionFold] = []
        switch beginFold(of: nodeID, folding: []) {
        case let .finished(revision, _): return .revision(revision)
        case let .pending(fold): stack.append(fold)
        }

        while let last = stack.indices.last {
            guard stack[last].next < stack[last].steps.count else {
                let (revision, cachable) = finishFold(stack.removeLast())
                guard !stack.isEmpty else { return .revision(revision) }
                stack[stack.count - 1].absorb(revision, cachable: cachable)
                continue
            }
            let step = stack[last].steps[stack[last].next]
            stack[last].next += 1

            let folding: Set<String>
            switch step {
            case .child:
                folding = stack[last].folding
            case let .component(id):
                if markers.contains(id) {
                    stack[last].absorb(Self.cycleMarker(id), cachable: false)
                    continue
                }
                if let shared = _revisionCache?.cycles[id] {
                    stack[last].absorb(shared, cachable: true)
                    continue
                }
                if stack[last].folding.contains(id) {
                    // Resolving a group, every group below it is already known, so this
                    // cannot happen; a marker keeps the fold total if it ever does.
                    guard !markers.isEmpty else { return .cycle(id) }
                    stack[last].absorb(Self.cycleMarker(id), cachable: false)
                    continue
                }
                folding = stack[last].folding.union([id])
            }
            switch beginFold(of: step.id, folding: folding) {
            case let .finished(revision, cachable): stack[last].absorb(revision, cachable: cachable)
            case let .pending(fold): stack.append(fold)
            }
        }
        return .revision(nil)
    }

    /// What a reference to a member of the cyclic group being resolved folds in.
    ///
    /// - Parameter component: The member.
    /// - Returns: A marker naming it.
    static func cycleMarker(_ component: String) -> String {
        "cycle:\(component)"
    }

    /// Starts folding one node: its memoized revision, `nil` for a node not in the
    /// document, or the fold still to run over what it contains.
    private func beginFold(of nodeID: String, folding: Set<String>) -> RevisionFold.Start {
        if let cached = _revisionCache?.entries[nodeID] { return .finished(cached, cachable: true) }
        guard let node = nodes[nodeID] else { return .finished(nil, cachable: true) }

        let childIDs = children[nodeID]
        let encoding = encoding(of: node, declaresEmptyChildren: childIDs == [])
        let hasher = encoding.hasher
        let steps = (childIDs ?? []).map(RevisionFold.Step.child)
            + encoding.rendered.map(RevisionFold.Step.component)
        return .pending(RevisionFold(nodeID: nodeID, folding: folding, hasher: hasher, steps: steps))
    }

    /// A node's own canonical encoding, hashed, with the ids it renders — from the cache
    /// when the node has not been written since it was encoded.
    ///
    /// A declared-empty list folds in no child, so it is hashed as the file writes it —
    /// `"children": []` — to tell it from a container that declares none.
    private func encoding(of node: PenNode, declaresEmptyChildren: Bool) -> RevisionCache.Encoding {
        if let known = _revisionCache?.encodings[node.id], known.declaresEmptyChildren == declaresEmptyChildren {
            return known
        }
        var hasher = FNV1aHasher()
        var written = node
        if declaresEmptyChildren { written.kind = node.kind.withChildren([]) }
        hasher.combine(Self.revisionEncoder.encodeCanonical(written))
        let encoding = RevisionCache.Encoding(
            hasher: hasher,
            declaresEmptyChildren: declaresEmptyChildren,
            rendered: componentsRendered(by: node)
        )
        if _revisionCache == nil {
            _revisionCache = RevisionCache()
        }
        _revisionCache?.encodings[node.id] = encoding
        return encoding
    }

    /// Ends a node's fold, memoizing the revision when it may be.
    private func finishFold(_ fold: RevisionFold) -> (revision: String, cachable: Bool) {
        let revision = fold.hasher.hexString
        if fold.cachable {
            if _revisionCache == nil {
                _revisionCache = RevisionCache()
            }
            _revisionCache?.store(revision, for: fold.nodeID)
        }
        return (revision, fold.cachable)
    }
}
