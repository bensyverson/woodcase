//
//  LayoutOracle.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// The answer an incremental layout must equal: a full layout of the same document,
/// built from nothing.
///
/// The document is materialized and read into a *fresh* ``EditableDocument`` with the
/// same read context — the libraries its imported instances expand from — so no cache
/// the edited document holds (expansion, revision or layout) can leak into the answer.
/// Compare its result to an incremental one with `==`: rects are compared bit for bit,
/// and a node either side has that the other lacks is a difference too.
/// ``differences(_:_:)`` names the ids that differ, for a failure message a reader can
/// act on.
enum LayoutOracle {
    /// A full layout of the document as it stands.
    ///
    /// - Parameters:
    ///   - document: The document to lay out; it is only read.
    ///   - textMeasurer: The measurer the incremental layout used.
    ///   - options: The options the incremental layout used — the cards it drew raw.
    ///   - purpose: What the incremental layout's document was expanded for: export
    ///     strips component definitions, a canvas lays them out like any board.
    /// - Returns: Every expanded node's rect.
    @MainActor
    static func fullLayout(
        of document: EditableDocument,
        textMeasurer: @escaping TextMeasurer,
        options: PenLayoutOptions = PenLayoutOptions(),
        purpose: PenRefExpander.Purpose = .export
    ) -> [String: PenRect] {
        let fresh = EditableDocument(from: document.materialize())
        fresh.readContext = document.readContext
        let expanded = fresh.expanded(for: purpose)
        return PenLayoutEngine.layout(PenVariableResolver.resolve(expanded), textMeasurer: textMeasurer, options: options)
    }

    /// The ids whose rects differ between two layouts, each with both sides, sorted and
    /// capped so a failure reads in a line or two.
    ///
    /// - Parameters:
    ///   - incremental: The layout under test.
    ///   - full: The oracle's layout.
    ///   - limit: The most differences to describe.
    /// - Returns: One description per differing id, empty when the layouts are equal.
    static func differences(
        _ incremental: [String: PenRect],
        _ full: [String: PenRect],
        limit: Int = 6
    ) -> [String] {
        let ids = Set(incremental.keys).union(full.keys).filter { incremental[$0] != full[$0] }
        return ids.sorted().prefix(limit).map { id in
            "\(id): \(describe(incremental[id])) vs full \(describe(full[id]))"
        }
    }

    private static func describe(_ rect: PenRect?) -> String {
        guard let rect else { return "missing" }
        return "(\(rect.x), \(rect.y), \(rect.width)×\(rect.height))"
    }
}
