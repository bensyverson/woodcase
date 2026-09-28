//
//  RevisionFold.swift
//  Woodcase
//

import Foundation

/// One node whose revision ``EditableDocument/revision(of:)`` is still folding: the
/// hash so far, and what remains to fold into it.
///
/// The fold keeps these on a stack on the heap rather than in recursive calls, so its
/// stack use does not grow with the document's depth.
struct RevisionFold {
    /// How starting a node's fold turned out.
    enum Start {
        /// The revision is known already — memoized, or `nil` for a node not in the
        /// document — with whether it may be memoized.
        case finished(String?, cachable: Bool)

        /// The node's own bytes are hashed; its children and components remain.
        case pending(RevisionFold)
    }

    /// One thing folded into a node's revision, in order.
    enum Step {
        /// A child in the flat store.
        case child(String)

        /// A component the node renders through.
        case component(String)

        /// The node the step folds in.
        var id: String {
            switch self {
            case let .child(id), let .component(id): id
            }
        }
    }

    /// The node being hashed.
    let nodeID: String

    /// The components already being folded in on this chain.
    let folding: Set<String>

    /// The hash so far.
    var hasher: FNV1aHasher

    /// Its children, then its components.
    let steps: [Step]

    /// The index of the next step.
    var next = 0

    /// Whether the revision may be memoized so far.
    var cachable = true

    /// Folds in one child's or component's result.
    ///
    /// - Parameters:
    ///   - revision: Its revision, or `nil` for a node not in the document.
    ///   - cachable: Whether that revision may be memoized.
    mutating func absorb(_ revision: String?, cachable: Bool) {
        if let revision { hasher.combine(revision) }
        self.cachable = self.cachable && cachable
    }
}
