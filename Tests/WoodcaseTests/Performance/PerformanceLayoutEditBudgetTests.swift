//
//  PerformanceLayoutEditBudgetTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

extension PerformanceBudgets {
    /// Measures what one editor gesture costs the layout engine on a 2,000-node board.
    ///
    /// Each test applies the edit and asks ``EditableDocument/computeLayout(textMeasurer:)``
    /// for the new rects — everything an editor waits for between the gesture and the
    /// next frame, with real CoreText text measurement. Layout is root-granular today:
    /// any structural edit invalidates the whole cache, and a property edit re-lays out
    /// the whole root, so the 2,000-node `Board` root is re-laid out every time.
    ///
    /// The limits are the *targets* from `project/2026-10-04-sub-root-layout-design.md`
    /// (cost model), not today's figures, so each budget is a
    /// ``PerformanceBudget/Standing/target``: over it prints a `BUDGET-TARGET` line and
    /// never fails. The leaf that meets a target makes it enforced — the committed edit
    /// with the node-granular engine, reorder and resize with the hypothetical layout.
    /// Run:
    ///
    /// ```sh
    /// WOODCASE_BUDGET_STRICT=1 swift test -c release --filter PerformanceBudgets.LayoutEditTests 2>&1 | grep BUDGET
    /// ```
    ///
    /// A 2,000-node board costs seconds per gesture in a debug build, so the default
    /// `swift test` skips this suite; a release build or `WOODCASE_BUDGET_STRICT` runs it.
    @Suite(.enabled(
        if: PerformanceBudget.isStrict,
        "Needs a release build or WOODCASE_BUDGET_STRICT: a debug board gesture takes seconds."
    ))
    @MainActor
    struct LayoutEditTests {
        /// The board every gesture is measured on.
        static let nodeCount: Int = 2000

        private static let reorderBudget = PerformanceBudget(
            name: "layout reorder in a 400-row list on a 2000-node board",
            release: .milliseconds(1),
            standing: .target
        )
        private static let resizeBudget = PerformanceBudget(
            name: "layout resize of a list row on a 2000-node board",
            release: .milliseconds(2),
            standing: .target
        )
        private static let editBudget = PerformanceBudget(
            name: "layout committed text edit on a 2000-node board",
            release: .milliseconds(1),
            standing: .target
        )

        @Test("Reordering a row in the 400-row list is measured")
        func reorder() async throws {
            let board = try Board()
            let sample = try await PerformanceSample.measure(repetitions: Self.reorderBudget.repetitions) {
                board.attempt += 1
                try board.document.apply(.moveNode(EditOperation.MoveNode(
                    nodeID: board.rows[10],
                    newParentID: board.listID,
                    index: board.attempt.isMultiple(of: 2) ? 10 : 300
                )))
                board.document.computeLayout()
            }
            Self.reorderBudget.check(sample)
        }

        @Test("Resizing a row in the 400-row list is measured")
        func resize() async throws {
            let board = try Board()
            let sample = try await PerformanceSample.measure(repetitions: Self.resizeBudget.repetitions) {
                board.attempt += 1
                try board.document.apply(.setProperties(EditOperation.SetProperties(
                    nodeID: board.rows[200],
                    properties: ["kind.height": .int(40 + board.attempt)]
                )))
                board.document.computeLayout()
            }
            Self.resizeBudget.check(sample)
        }

        @Test("Committing a text edit in the list is measured")
        func committedEdit() async throws {
            let board = try Board()
            let sample = try await PerformanceSample.measure(repetitions: Self.editBudget.repetitions) {
                board.attempt += 1
                try board.document.apply(.setProperties(EditOperation.SetProperties(
                    nodeID: board.titles[200],
                    properties: ["kind.content": .string("Edited title number \(board.attempt)")]
                )))
                board.document.computeLayout()
            }
            Self.editBudget.check(sample)
        }

        /// A primed 2,000-node board and the ids the gestures act on.
        @MainActor
        private final class Board {
            let document: EditableDocument
            let listID: String
            let rows: [String]
            let titles: [String]
            var attempt = 0

            init() throws {
                let source = SyntheticPenDocument.makeEditorBoard(nodeCount: LayoutEditTests.nodeCount)
                let list = try #require(Self.find(SyntheticPenDocument.editorBoardListName, in: source.children))
                listID = list.id
                rows = list.kind.inlineChildren.map(\.id)
                titles = list.kind.inlineChildren.compactMap { $0.kind.inlineChildren.first?.id }
                document = EditableDocument(from: source)
                // The first layout is the cold one every editor pays once; the budgets
                // are for the edits after it.
                document.computeLayout()
            }

            private static func find(_ name: String, in nodes: [PenNode]) -> PenNode? {
                for node in nodes {
                    if node.common.name == name { return node }
                    if let found = find(name, in: node.kind.inlineChildren) { return found }
                }
                return nil
            }
        }
    }
}
