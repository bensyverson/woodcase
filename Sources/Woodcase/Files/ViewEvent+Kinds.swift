//
//  ViewEvent+Kinds.swift
//  Woodcase
//

public extension ViewEvent {
    /// The read verb that logged a view.
    ///
    /// A line naming a verb this build does not know fails to decode and is skipped by
    /// the reader, the way an unknown ``ActivityEvent/Kind`` is.
    enum Verb: String, Friendly, CaseIterable {
        /// `woodcase tree`: the rows it printed.
        case tree
        /// `woodcase get`: the node, its subtree.
        case get
        /// `woodcase find`: the matches.
        case find
        /// `woodcase shot`: what the picture showed.
        case shot
        /// `woodcase render`: the roots drawn.
        case render
        /// `woodcase clip`: the subtrees a copy took.
        case clip
    }

    /// How much of the document under each node a read covered.
    enum Scope: String, Friendly, CaseIterable {
        /// The listed nodes themselves.
        case nodes
        /// The listed nodes and everything under them.
        case subtrees
    }
}
