//
//  LayoutOracle.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// The answer an incremental layout must equal: a full layout of the same document,
/// built from nothing.
///
/// The document is materialized and read into a *fresh* ``EditableDocument``, so no
/// cache the edited document holds — expansion, revision or layout — can leak into
/// the answer. Compare its result to an incremental one with `==`: rects are compared
/// bit for bit, and a node either side has that the other lacks is a difference too.
///
/// This is the root-granular oracle `2lTgnU` needed; `bDA99O` widens it to every
/// fixture and a spread of writes.
enum LayoutOracle {
    /// A full layout of the document as it stands.
    ///
    /// - Parameters:
    ///   - document: The document to lay out; it is only read.
    ///   - textMeasurer: The measurer the incremental layout used.
    /// - Returns: Every expanded node's rect.
    @MainActor
    static func fullLayout(of document: EditableDocument, textMeasurer: @escaping TextMeasurer) -> [String: PenRect] {
        let fresh = EditableDocument(from: document.materialize())
        let (expanded, _) = fresh.expandedDocument()
        return PenLayoutEngine.layout(PenVariableResolver.resolve(expanded), textMeasurer: textMeasurer)
    }
}
