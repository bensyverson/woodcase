//
//  SpansStaleWarnings.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// The warning a `set` or an `override` prints when it leaves a text's spans stale.
///
/// A text's styled runs record the words they were made for. A `set` that changes the
/// content and does not restate `common.metadata.woodcase.spans` for the new words leaves
/// them stale: they are kept, ignored, and the text draws plain. The write is applied —
/// guessing where the runs should move would be worse — but it says so, one line on
/// standard error in exactly the form `lint` prints the `spans-stale` finding. A text inside
/// an instance takes spans of its own through an override, and an `override` of its content
/// that leaves them stale says so the same way. Only spans
/// the write made stale are reported; ones that were stale already are `lint`'s business.
enum SpansStaleWarnings {
    /// The warning line for a node whose spans this write made stale, if any.
    ///
    /// - Parameters:
    ///   - nodeID: The node the write targeted.
    ///   - wereStale: Whether its spans were stale before the write.
    ///   - document: The document after the write.
    /// - Returns: One line, or none.
    static func lines(for nodeID: String, wereStale: Bool, in document: EditableDocument) -> [String] {
        guard !wereStale, let finding = DocumentLinter.spansStaleFinding(nodeID: nodeID, in: document) else { return [] }
        return [RootOverlapWarnings.line(of: finding)]
    }

    /// The warning line for a text inside an instance whose own spans this override made
    /// stale, if any.
    ///
    /// - Parameters:
    ///   - target: Where the override was written; only a text inside an instance has any.
    ///   - wereStale: Whether its spans were stale before the write.
    ///   - document: The document after the write.
    /// - Returns: One line, or none.
    static func lines(overriding target: ResolvedNodeAddress, wereStale: Bool, in document: EditableDocument) -> [String] {
        guard !wereStale, let finding = finding(at: target, in: document) else { return [] }
        return [RootOverlapWarnings.line(of: finding)]
    }

    /// The `spans-stale` finding for the instance text at `target` now, if any.
    static func finding(at target: ResolvedNodeAddress, in document: EditableDocument) -> LintFinding? {
        guard case let .instanceDescendant(refID, key) = target else { return nil }
        return DocumentLinter.spansStaleFinding(instance: refID, descendantKey: key, in: document)
    }
}
