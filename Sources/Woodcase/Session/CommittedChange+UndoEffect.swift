//
//  CommittedChange+UndoEffect.swift
//  Woodcase
//

import Foundation

public extension CommittedChange {
    /// What a change did to its author's undo and redo stacks.
    ///
    /// An app that mirrors the session's stacks into a platform undo manager acts on
    /// this rather than inferring it from the change's other fields. Each flag maps to
    /// one thing the mirror does:
    ///
    /// | Flag | The mirror… |
    /// | --- | --- |
    /// | ``openedEntry`` | registers a new undo action |
    /// | ``joinedEntry`` | registers nothing: the most recent action now covers this change too |
    /// | ``consumedEntry`` | lets its own undo or redo action stand as taken |
    /// | ``filedReversal`` | registers the opposite action — a redo while undoing, an undo while redoing |
    /// | ``clearedRedo`` | drops its redo actions, which a platform undo manager cannot do alone without registering an undo |
    ///
    /// A local edit reports ``openedEntry`` or ``joinedEntry`` as its
    /// ``UndoGroup`` decided — neither for ``UndoGroup/none`` — and ``clearedRedo`` when
    /// the redo stack held anything. An undo or a redo that found an entry reports
    /// ``consumedEntry``, and ``filedReversal`` too unless every step was kept for
    /// another author, in which case the entry is gone and nothing replaces it. A change
    /// that applied nothing, a collaborator's change and a file merge report the empty
    /// set: they leave both stacks as they were.
    struct UndoEffect: OptionSet, Friendly {
        /// Creates an effect from its raw bits.
        ///
        /// - Parameter rawValue: The bits.
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        /// The bits.
        public let rawValue: UInt8

        /// A local edit pushed a new entry on the undo stack: ``UndoGroup/new``, or the
        /// first ``UndoGroup/coalesce(_:)`` edit of a group.
        public static let openedEntry = UndoEffect(rawValue: 1 << 0)

        /// A ``UndoGroup/coalesce(_:)`` edit joined the open entry, which now undoes it
        /// too; the stack's depth did not change.
        public static let joinedEntry = UndoEffect(rawValue: 1 << 1)

        /// An undo or a redo took its entry off the stack it reads from.
        public static let consumedEntry = UndoEffect(rawValue: 1 << 2)

        /// An undo or a redo filed the reversal of what it applied on the opposite
        /// stack: undo's on redo, redo's on undo.
        public static let filedReversal = UndoEffect(rawValue: 1 << 3)

        /// A local edit emptied a redo stack that held entries.
        public static let clearedRedo = UndoEffect(rawValue: 1 << 4)
    }
}
