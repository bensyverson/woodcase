//
//  LayoutEditBudget.swift
//  WoodcasePerfFixtures
//

import Foundation
import Woodcase

/// What one editor gesture costs the root-granular layout engine on a 2,000-node board,
/// and the targets it is measured against.
///
/// Each measurement applies the edit and asks ``EditableDocument/computeLayout(textMeasurer:)``
/// for the new rects — everything an editor waits for between the gesture and the next
/// frame, with real CoreText text measurement. Layout is root-granular here: any
/// structural edit invalidates the whole cache, and a property edit re-lays out the whole
/// root, so the 2,000-node `Board` root is re-laid out every time.
///
/// The limits are the *targets* from `project/2026-10-04-sub-root-layout-design.md`
/// (cost model), not today's figures, so each budget is a
/// ``PerformanceBudget/Standing/target``: over it prints a `BUDGET-TARGET` line and never
/// fails. The leaf that meets a target makes it enforced.
@MainActor
public enum LayoutEditBudget {
    /// The board every gesture is measured on.
    public static let nodeCount: Int = 2000

    /// Reordering a row of the 400-row list.
    public static let reorder = PerformanceBudget(
        name: "layout reorder in a 400-row list on a 2000-node board",
        release: .milliseconds(1),
        standing: .target
    )

    /// Resizing a row of the list.
    public static let resize = PerformanceBudget(
        name: "layout resize of a list row on a 2000-node board",
        release: .milliseconds(2),
        standing: .target
    )

    /// Committing a text edit in the list.
    public static let edit = PerformanceBudget(
        name: "layout committed text edit on a 2000-node board",
        release: .milliseconds(1),
        standing: .target
    )

    /// Times reordering a row of the list back and forth.
    ///
    /// - Returns: The sample to check against ``reorder``.
    /// - Throws: Whatever the edit throws, or a ``PerformanceFixture/SetupError``.
    public static func measureReorder() async throws -> PerformanceSample {
        let board = try EditorBoard(nodeCount: nodeCount)
        board.document.computeLayout()
        var attempt = 0
        return try await PerformanceSample.measure(repetitions: reorder.repetitions) {
            attempt += 1
            try board.document.apply(.moveNode(EditOperation.MoveNode(
                nodeID: board.rows[10],
                newParentID: board.listID,
                index: attempt.isMultiple(of: 2) ? 10 : 300
            )))
            board.document.computeLayout()
        }
    }

    /// Times resizing a row of the list.
    ///
    /// - Returns: The sample to check against ``resize``.
    /// - Throws: Whatever the edit throws, or a ``PerformanceFixture/SetupError``.
    public static func measureResize() async throws -> PerformanceSample {
        let board = try EditorBoard(nodeCount: nodeCount)
        board.document.computeLayout()
        var attempt = 0
        return try await PerformanceSample.measure(repetitions: resize.repetitions) {
            attempt += 1
            try board.document.apply(.setProperties(EditOperation.SetProperties(
                nodeID: board.rows[200],
                properties: ["kind.height": .int(40 + attempt)]
            )))
            board.document.computeLayout()
        }
    }

    /// Times committing a text edit in the list.
    ///
    /// - Returns: The sample to check against ``edit``.
    /// - Throws: Whatever the edit throws, or a ``PerformanceFixture/SetupError``.
    public static func measureEdit() async throws -> PerformanceSample {
        let board = try EditorBoard(nodeCount: nodeCount)
        board.document.computeLayout()
        var attempt = 0
        return try await PerformanceSample.measure(repetitions: edit.repetitions) {
            attempt += 1
            try board.document.apply(.setProperties(EditOperation.SetProperties(
                nodeID: board.titles[200],
                properties: ["kind.content": .string("Edited title number \(attempt)")]
            )))
            board.document.computeLayout()
        }
    }
}
