//
//  LayoutStateBudget.swift
//  WoodcasePerfFixtures
//

import Foundation
import Woodcase

/// Node-granular layout on a 2,000-node board, and its budgets: a hypothetical reorder
/// and resize, as a live gesture previews them, a committed edit, and a committed edit
/// inside the component every card instance draws.
///
/// Each gesture is timed on a ``PenLayoutState`` built once — what a host holds between
/// frames — with real CoreText text measurement. The committed edit times
/// ``PenLayoutState/update(to:invalidation:)`` alone: the edit is applied and the
/// document expanded and resolved outside the clock, because that is the host's pipeline
/// (Penumbra expands per board on its own actor), not layout. The limits are the design's
/// budgets (`project/2026-10-04-sub-root-layout-design.md`, cost model).
@MainActor
public enum LayoutStateBudget {
    /// A hypothetical reorder of a row of the 400-row list.
    public static let reorder = PerformanceBudget(
        name: "hypothetical reorder in a 400-row list on a 2000-node board",
        release: .milliseconds(1),
        repetitions: 20
    )

    /// A hypothetical resize of a row of the list.
    public static let resize = PerformanceBudget(
        name: "hypothetical resize of a list row on a 2000-node board",
        release: .milliseconds(2),
        repetitions: 20
    )

    /// A committed edit inside the component definition.
    ///
    /// Every instance of the component is laid out whole, with its spine: 25.4 ms when
    /// such an edit laid out the whole board, 13.7 ms naming the instances (2026-10-12,
    /// `WoodcasePerformance.md`). The limit sits between, so the board-wide fallback
    /// coming back fails it.
    public static let definition = PerformanceBudget(
        name: "committed edit inside the component, node-granular update on a 2000-node board",
        release: .milliseconds(20),
        repetitions: 20
    )

    /// A committed text edit in the list.
    public static let update = PerformanceBudget(
        name: "committed text edit, node-granular update on a 2000-node board",
        release: .milliseconds(1),
        repetitions: 20
    )

    /// An editor board laid out once into a ``PenLayoutState``.
    @MainActor
    public final class Board {
        /// The board and the ids its gestures act on.
        public let board: EditorBoard

        /// The layout a host holds between frames.
        public var state: PenLayoutState

        /// Generates the board and lays it out — the cold layout a host pays once.
        ///
        /// - Throws: A ``PerformanceFixture/SetupError`` from ``EditorBoard``.
        public init() throws {
            board = try EditorBoard(nodeCount: LayoutEditBudget.nodeCount)
            board.document.primeLayoutCache(with: [:])
            state = PenLayoutState(document: PenVariableResolver.resolve(board.document.expandedDocument().0))
        }
    }

    /// Times a hypothetical reorder of a list row, alternating its destination.
    ///
    /// - Returns: The sample to check against ``reorder``.
    /// - Throws: A ``PerformanceFixture/SetupError`` when a reorder changes nothing.
    public static func measureReorder() async throws -> PerformanceSample {
        let layout = try Board()
        let board = layout.board
        var attempt = 0
        return try await PerformanceSample.measure(repetitions: reorder.repetitions) {
            attempt += 1
            let change = layout.state.hypothetical([
                .move(board.rows[10], toIndex: attempt.isMultiple(of: 2) ? 300 : 20),
            ])
            guard !change.isEmpty else { throw PerformanceFixture.SetupError("A hypothetical reorder changed nothing.") }
        }
    }

    /// Times a hypothetical resize of a list row, to a new height each time.
    ///
    /// - Returns: The sample to check against ``resize``.
    /// - Throws: A ``PerformanceFixture/SetupError`` when a resize changes nothing.
    public static func measureResize() async throws -> PerformanceSample {
        let layout = try Board()
        let board = layout.board
        var attempt = 0
        return try await PerformanceSample.measure(repetitions: resize.repetitions) {
            attempt += 1
            let change = layout.state.hypothetical([.size(board.rows[200], width: nil, height: Double(40 + attempt))])
            guard !change.isEmpty else { throw PerformanceFixture.SetupError("A hypothetical resize changed nothing.") }
        }
    }

    /// Times the node-granular update after a committed text edit in the list.
    ///
    /// - Returns: The sample to check against ``update``.
    /// - Throws: Whatever the edit throws, or a ``PerformanceFixture/SetupError`` when an
    ///   update lays nothing out.
    public static func measureUpdate() throws -> PerformanceSample {
        let layout = try Board()
        return try measureCommitted(update, on: layout, node: layout.board.titles[200], text: "Edited title")
    }

    /// Times the node-granular update after a committed edit inside the component.
    ///
    /// - Returns: The sample to check against ``definition``.
    /// - Throws: Whatever the edit throws, or a ``PerformanceFixture/SetupError`` when an
    ///   update lays nothing out.
    public static func measureDefinitionEdit() throws -> PerformanceSample {
        let layout = try Board()
        return try measureCommitted(definition, on: layout, node: layout.board.definitionText, text: "Edited card text")
    }

    /// Applies `budget.repetitions` text edits to `node`, each a different length so the
    /// text resizes, and times only ``PenLayoutState/update(to:invalidation:)``.
    private static func measureCommitted(
        _ budget: PerformanceBudget,
        on layout: Board,
        node: String,
        text: String
    ) throws -> PerformanceSample {
        let document = layout.board.document
        var elapsed: [Duration] = []
        // Every document stays alive past the clock: the state lets go of the one it
        // held, and freeing a 2,000-node tree is the host's churn, not layout.
        var documents: [PenDocument] = [layout.state.document]
        for attempt in 0 ..< budget.repetitions {
            document.clearDirtyNodes()
            try document.apply(.setProperties(EditOperation.SetProperties(
                nodeID: node,
                properties: ["kind.content": .string(text + String(repeating: " x", count: attempt % 3 + 1))]
            )))
            let resolved = PenVariableResolver.resolve(document.expandedDocument().0)
            let invalidation = document.layoutInvalidation
            documents.append(resolved)
            let clock = ContinuousClock.now
            let change = layout.state.update(to: resolved, invalidation: invalidation)
            elapsed.append(clock.duration(to: ContinuousClock.now))
            guard !change.stats.containersLaidOut.isEmpty else {
                throw PerformanceFixture.SetupError("A committed edit to \(node) laid nothing out.")
            }
        }
        withExtendedLifetime(documents) {}
        return PerformanceSample(elapsed: elapsed)
    }
}
