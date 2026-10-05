//
//  ComponentLoop.swift
//  Woodcase
//

import Foundation

/// Components that contain each other: A renders an instance of B and B renders one of
/// A, or A renders itself, through any chain.
///
/// A loop is a design error. An edit that would close one is refused with
/// ``EditingError/wouldCloseComponentLoop(path:)``; a file that already holds one still
/// reads, but no instance of a loop's member is expanded inside the expansion of another
/// member — that nesting is ignored, everywhere the expansion is mirrored. The document
/// reports what it holds as ``EditableDocument/componentLoops``, and a read through
/// ``PenFileTransaction`` records it on ``PenReadContext/componentLoops`` for the caller to
/// report — the library prints nothing; the `woodcase` CLI says it on standard error, and
/// `woodcase lint` reports each as an error. See <doc:ComponentLoops>.
///
/// One loop is one group of components that all reach each other — a strongly
/// connected component of the graph in which a component points at every component an
/// instance anywhere in its subtree renders, slot content and repointed refs included.
public struct ComponentLoop: Friendly, CustomStringConvertible {
    /// One component in a loop.
    public struct Member: Friendly {
        /// The component's node id.
        public var id: String

        /// The component's display name: its `name`, or its id when it has none.
        public var name: String

        /// Creates a member.
        ///
        /// - Parameters:
        ///   - id: The component's node id.
        ///   - name: Its display name.
        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// Every component in the loop. The first ``cycleLength`` of them are a cycle, in
    /// render order — each renders the next, and the last renders the first — starting
    /// from the member with the lowest id; any others follow in id order.
    public var members: [Member]

    /// How many of ``members``, from the first, make the cycle: all of them for a loop
    /// that is one ring, fewer for a group tangled from several.
    public var cycleLength: Int

    /// Creates a loop.
    ///
    /// - Parameters:
    ///   - members: The components, the cycle first.
    ///   - cycleLength: How many of them, from the first, make the cycle; every one when
    ///     `nil`.
    public init(members: [Member], cycleLength: Int? = nil) {
        self.members = members
        self.cycleLength = min(cycleLength ?? members.count, members.count)
    }

    /// The members' ids, in order.
    public var ids: [String] {
        members.map(\.id)
    }

    /// The cycle written out by name and closed: `Card → Badge → Card`, or `Row → Row`
    /// for a component that renders itself — then any other member of the loop.
    public var description: String {
        let cycle = members.prefix(cycleLength).map(\.name)
        var text = (cycle + cycle.prefix(1)).joined(separator: " → ")
        let rest = members.dropFirst(cycleLength).map(\.name)
        if !rest.isEmpty {
            text += " (with \(rest.joined(separator: ", ")) in the same loop)"
        }
        return text
    }
}
