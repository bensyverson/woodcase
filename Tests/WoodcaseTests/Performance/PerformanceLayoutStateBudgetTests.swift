//
//  PerformanceLayoutStateBudgetTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

extension PerformanceBudgets {
    /// Measures node-granular layout on a 2,000-node board: a hypothetical reorder and
    /// resize, as a live gesture previews them, and a committed edit.
    ///
    /// Each gesture is timed on a ``PenLayoutState`` built once — what a host holds between
    /// frames — with real CoreText text measurement. The committed edit times
    /// ``PenLayoutState/update(to:invalidation:)`` alone: the edit is applied and the
    /// document expanded and resolved outside the clock, because that is the host's
    /// pipeline (Penumbra expands per board on its own actor), not layout. The limits are
    /// the design's budgets (`project/2026-10-04-sub-root-layout-design.md`, cost model).
    /// Run:
    ///
    /// ```sh
    /// WOODCASE_BUDGET_STRICT=1 swift test -c release --filter PerformanceBudgets.LayoutStateTests 2>&1 | grep BUDGET
    /// ```
    @Suite(.enabled(
        if: PerformanceBudget.isStrict,
        "Needs a release build or WOODCASE_BUDGET_STRICT: a debug board layout takes seconds."
    ))
    @MainActor
    struct LayoutStateTests {
        private static let reorderBudget = PerformanceBudget(
            name: "hypothetical reorder in a 400-row list on a 2000-node board",
            release: .milliseconds(1),
            repetitions: 20
        )
        private static let resizeBudget = PerformanceBudget(
            name: "hypothetical resize of a list row on a 2000-node board",
            release: .milliseconds(2),
            repetitions: 20
        )
        private static let updateBudget = PerformanceBudget(
            name: "committed text edit, node-granular update on a 2000-node board",
            release: .milliseconds(1),
            repetitions: 20
        )

        @Test("A hypothetical reorder in the 400-row list is within budget")
        func hypotheticalReorder() async throws {
            let board = try Board()
            var attempt = 0
            let sample = try await PerformanceSample.measure(repetitions: Self.reorderBudget.repetitions) {
                attempt += 1
                let change = board.state.hypothetical([.move(board.rows[10], toIndex: attempt.isMultiple(of: 2) ? 300 : 20)])
                try #require(!change.isEmpty)
            }
            Self.reorderBudget.check(sample)
        }

        @Test("A hypothetical resize of a list row is within budget")
        func hypotheticalResize() async throws {
            let board = try Board()
            var attempt = 0
            let sample = try await PerformanceSample.measure(repetitions: Self.resizeBudget.repetitions) {
                attempt += 1
                let change = board.state.hypothetical([.size(board.rows[200], width: nil, height: Double(40 + attempt))])
                try #require(!change.isEmpty)
            }
            Self.resizeBudget.check(sample)
        }

        @Test("A committed text edit updates within budget")
        func committedUpdate() throws {
            let board = try Board()
            var elapsed: [Duration] = []
            // Every document stays alive past the clock: the state lets go of the one it
            // held, and freeing a 2,000-node tree is the host's churn, not layout.
            var documents: [PenDocument] = [board.state.document]
            for attempt in 0 ..< Self.updateBudget.repetitions {
                board.document.clearDirtyNodes()
                try board.document.apply(.setProperties(EditOperation.SetProperties(
                    nodeID: board.titles[200],
                    // A length that differs from the last edit's, so the title resizes.
                    properties: ["kind.content": .string("Edited title" + String(repeating: " x", count: attempt % 3 + 1))]
                )))
                let resolved = PenVariableResolver.resolve(board.document.expandedDocument().0)
                let invalidation = board.document.layoutInvalidation
                documents.append(resolved)
                let clock = ContinuousClock.now
                let change = board.state.update(to: resolved, invalidation: invalidation)
                elapsed.append(clock.duration(to: ContinuousClock.now))
                try #require(!change.stats.containersLaidOut.isEmpty)
            }
            Self.updateBudget.check(PerformanceSample(elapsed: elapsed))
            #expect(documents.count == Self.updateBudget.repetitions + 1)
        }

        /// A 2,000-node board laid out once, and the ids the gestures act on.
        @MainActor
        private final class Board {
            let document: EditableDocument
            var state: PenLayoutState
            let rows: [String]
            let titles: [String]

            init() throws {
                let source = SyntheticPenDocument.makeEditorBoard(nodeCount: LayoutEditTests.nodeCount)
                let list = try #require(Self.find(SyntheticPenDocument.editorBoardListName, in: source.children))
                rows = list.kind.inlineChildren.map(\.id)
                titles = list.kind.inlineChildren.compactMap { $0.kind.inlineChildren.first?.id }
                document = EditableDocument(from: source)
                document.primeLayoutCache(with: [:])
                // The first layout is the cold one a host pays once; the budgets are for
                // the gestures after it.
                state = PenLayoutState(document: PenVariableResolver.resolve(document.expandedDocument().0))
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
