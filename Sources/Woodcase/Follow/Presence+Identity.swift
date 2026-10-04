//
//  Presence+Identity.swift
//  Woodcase
//

import Foundation

public extension Presence {
    /// One identity seen in the log.
    struct Identity: Friendly {
        /// Creates an identity.
        ///
        /// - Parameters:
        ///   - name: The `--as` name it writes under; empty for unattributed writes.
        ///   - order: Its position in order of first appearance, from zero.
        ///   - lastSeen: When it last wrote.
        ///   - changes: How many events it has written in the log read so far.
        ///   - latestChange: The node mark of its newest change, if that change named nodes.
        ///   - latestView: The node mark of its newest read, once views are logged.
        ///   - files: The canonical paths of the files it has touched, most recent first.
        public init(
            name: String,
            order: Int,
            lastSeen: Date,
            changes: Int,
            latestChange: NodeMark? = nil,
            latestView: NodeMark? = nil,
            files: [String] = []
        ) {
            self.name = name
            self.order = order
            self.lastSeen = lastSeen
            self.changes = changes
            self.latestChange = latestChange
            self.latestView = latestView
            self.files = files
        }

        /// The `--as` name it writes under.
        public var name: String

        /// Its position in order of first appearance, from zero.
        public var order: Int

        /// When it last wrote. Never moves backwards, whatever order events arrive in.
        public var lastSeen: Date

        /// How many events it has written in the log read so far.
        public var changes: Int

        /// The nodes its newest change touched — one mark per batch.
        ///
        /// Unchanged by an event that names no node (a variable, an import, an
        /// `external` row), which updates ``lastSeen`` and ``changes`` only.
        public var latestChange: NodeMark?

        /// The nodes its newest read touched. Filled once view events are logged.
        public var latestView: NodeMark?

        /// The canonical paths of the files it has touched, most recently touched first.
        public var files: [String]

        /// The node a cursor for this identity belongs on: the first node of whichever of
        /// ``latestChange`` and ``latestView`` is newer.
        public var cursorNode: String? {
            switch (latestChange, latestView) {
            case let (change?, view?):
                (view.time > change.time ? view : change).nodes.first
            case let (change?, nil):
                change.nodes.first
            case let (nil, view?):
                view.nodes.first
            case (nil, nil):
                nil
            }
        }
    }
}
