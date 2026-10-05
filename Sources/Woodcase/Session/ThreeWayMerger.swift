//
//  ThreeWayMerger.swift
//  Woodcase
//

import Foundation

/// The library's ``DocumentMerger``: ``DocumentMerge/merge(base:ours:theirs:)``.
///
/// ``DocumentMerge`` is a namespace of pure functions and cannot itself be handed to a
/// session as a value, so this is the value that stands for it. Pass it as `.threeWay`.
public struct ThreeWayMerger: DocumentMerger, Friendly {
    /// Creates the merger.
    public init() {}

    /// Merges with ``DocumentMerge/merge(base:ours:theirs:)``.
    ///
    /// - Parameters:
    ///   - base: The version both sides started from.
    ///   - ours: The local document.
    ///   - theirs: The external version.
    /// - Returns: The merge's operations and conflicts.
    public func merge(base: EditableDocument, ours: EditableDocument, theirs: EditableDocument) -> MergeResult {
        DocumentMerge.merge(base: base, ours: ours, theirs: theirs)
    }
}
