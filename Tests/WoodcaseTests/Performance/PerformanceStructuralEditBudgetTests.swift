//
//  PerformanceStructuralEditBudgetTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

extension PerformanceBudgets {
    /// Measures a one-node insert on a 2,500-node document of eight boards (Penumbra
    /// ruling R20): the insert lays out only the board that holds it, so it should cost
    /// about an eighth of a full layout of the document.
    ///
    /// Each repetition inserts a row into one board's list and asks
    /// ``EditableDocument/computeLayout(textMeasurer:)`` for the new rects, with real
    /// CoreText measurement. The full layout of the same document is printed beside it
    /// as an `INFO` line, the figure every insert cost before R20. Run:
    ///
    /// ```sh
    /// swift test -c release --filter PerformanceBudgets.StructuralEditTests 2>&1 | grep -E 'BUDGET|INFO'
    /// ```
    @Suite(.enabled(
        if: PerformanceBudget.isStrict,
        "Needs a release build or WOODCASE_BUDGET_STRICT: a debug 2,500-node layout takes seconds."
    ))
    @MainActor
    struct StructuralEditTests {
        /// The document's node count.
        static let nodeCount: Int = 2500

        /// The document's board count.
        static let boardCount: Int = 8

        private static let insertBudget = PerformanceBudget(
            name: "layout one-node insert on a 2500-node, 8-board document",
            release: .milliseconds(8),
            standing: .target
        )

        @Test("A one-node insert lays out one board of eight")
        func insert() async throws {
            let document = EditableDocument(from: Self.makeDocument())
            document.computeLayout()
            #expect(Self.count(document.materialize().children) == Self.nodeCount)

            let full = try await PerformanceSample.measure(repetitions: Self.insertBudget.repetitions) {
                let (expanded, _) = document.expandedDocument()
                _ = PenLayoutEngine.layout(PenVariableResolver.resolve(expanded))
            }
            print("INFO | full layout of a 2500-node, 8-board document | min \(PerformanceBudget.milliseconds(full.best))")

            var attempt = 0
            let sample = try await PerformanceSample.measure(repetitions: Self.insertBudget.repetitions) {
                attempt += 1
                document.clearDirtyNodes()
                try document.apply(.insertNode(EditOperation.InsertNode(
                    node: Self.text("inserted\(attempt)", "Inserted row \(attempt)"),
                    parentID: "list3",
                    index: 0
                )))
                document.computeLayout()
            }
            #expect(document.dirtyLayoutRootIDs == ["board3"])
            Self.insertBudget.check(sample)
        }

        /// Eight vertical boards side by side, each a title and a list of rows of a
        /// label and a swatch, filled to exactly ``nodeCount`` nodes.
        static func makeDocument() -> PenDocument {
            let perBoard = nodeCount / boardCount
            let boards = (0 ..< boardCount).map { index in
                // Board, title and list are three nodes; the rest is rows of three, and
                // what does not divide becomes loose labels.
                let budget = perBoard + (index < nodeCount % boardCount ? 1 : 0) - 3
                let rows = (0 ..< budget / 3).map { row in
                    PenNode(
                        id: "row\(index)x\(row)",
                        common: PenNodeCommon(),
                        kind: .frame(PenNode.FrameData(
                            width: .fillContainer(fallback: nil),
                            layout: .horizontal,
                            gap: .literal(8),
                            children: [
                                text("label\(index)x\(row)", "Board \(index) row \(row)"),
                                PenNode(
                                    id: "swatch\(index)x\(row)",
                                    common: PenNodeCommon(),
                                    kind: .rectangle(PenNode.RectangleData(width: .fixed(16), height: .fixed(16)))
                                ),
                            ]
                        ))
                    )
                }
                let loose = (0 ..< budget % 3).map { text("loose\(index)x\($0)", "Board \(index) note \($0)") }
                return PenNode(
                    id: "board\(index)",
                    common: PenNodeCommon(x: .literal(Double(index) * 400), y: .literal(0)),
                    kind: .frame(PenNode.FrameData(
                        width: .fixed(360),
                        layout: .vertical,
                        gap: .literal(4),
                        children: [text("title\(index)", "Board \(index)")] + loose + [
                            PenNode(
                                id: "list\(index)",
                                common: PenNodeCommon(),
                                kind: .frame(PenNode.FrameData(
                                    width: .fillContainer(fallback: nil),
                                    layout: .vertical,
                                    gap: .literal(2),
                                    children: rows
                                ))
                            ),
                        ]
                    ))
                )
            }
            return PenDocument(version: "2.17", children: boards)
        }

        private static func text(_ id: String, _ content: String) -> PenNode {
            PenNode(
                id: id,
                common: PenNodeCommon(),
                kind: .text(PenNode.TextData(width: .fitContent(fallback: nil), content: .literal(content)))
            )
        }

        private static func count(_ nodes: [PenNode]) -> Int {
            nodes.reduce(0) { $0 + 1 + count($1.kind.inlineChildren) }
        }
    }
}
