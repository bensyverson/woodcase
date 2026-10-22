//
//  StructuralEditBudget.swift
//  WoodcasePerfFixtures
//

import Foundation
import Woodcase

/// A one-node insert on a 2,500-node document of eight boards (Penumbra ruling R20), and
/// its target: the insert lays out only the board that holds it, so it should cost about
/// an eighth of a full layout of the document.
///
/// Each repetition inserts a row into one board's list and asks
/// ``EditableDocument/computeLayout(textMeasurer:)`` for the new rects, with real CoreText
/// measurement. The full layout of the same document is measured beside it, the figure
/// every insert cost before R20.
@MainActor
public enum StructuralEditBudget {
    /// The document's node count.
    public static let nodeCount: Int = 2500

    /// The document's board count.
    public static let boardCount: Int = 8

    /// The list every repetition inserts into.
    public static let insertListID = "list3"

    /// The board that holds ``insertListID``.
    public static let insertBoardID = "board3"

    /// The insert's target.
    public static let insert = PerformanceBudget(
        name: "layout one-node insert on a 2500-node, 8-board document",
        release: .milliseconds(8),
        standing: .target
    )

    /// What one measurement found.
    public struct Measurement: Friendly {
        /// A full layout of the document, for an `INFO` line beside the budget.
        public var fullLayout: PerformanceSample

        /// The inserts, to check against ``insert``.
        public var insert: PerformanceSample
    }

    /// Times a full layout of `document`, then `insert.repetitions` one-node inserts into
    /// ``insertListID``, each followed by a layout.
    ///
    /// - Parameter document: ``makeDocument()``, editable and laid out once.
    /// - Returns: Both samples.
    /// - Throws: Whatever an insert throws.
    public static func measure(on document: EditableDocument) async throws -> Measurement {
        let full = await PerformanceSample.measure(repetitions: insert.repetitions) {
            let (expanded, _) = document.expandedDocument()
            _ = PenLayoutEngine.layout(PenVariableResolver.resolve(expanded))
        }
        var attempt = 0
        let inserts = try await PerformanceSample.measure(repetitions: insert.repetitions) {
            attempt += 1
            document.clearDirtyNodes()
            try document.apply(.insertNode(EditOperation.InsertNode(
                node: text("inserted\(attempt)", "Inserted row \(attempt)"),
                parentID: insertListID,
                index: 0
            )))
            document.computeLayout()
        }
        return Measurement(fullLayout: full, insert: inserts)
    }

    /// The `INFO` line for the full layout beside the budget.
    ///
    /// - Parameter sample: ``Measurement/fullLayout``.
    /// - Returns: One `INFO` line.
    public static func fullLayoutLine(_ sample: PerformanceSample) -> String {
        "INFO | full layout of a 2500-node, 8-board document | min \(PerformanceBudget.milliseconds(sample.best))"
    }

    /// Eight vertical boards side by side, each a title and a list of rows of a label
    /// and a swatch, filled to exactly ``nodeCount`` nodes.
    public static func makeDocument() -> PenDocument {
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

    /// How many nodes `nodes` and their inline descendants hold.
    public static func count(_ nodes: [PenNode]) -> Int {
        nodes.reduce(0) { $0 + 1 + count($1.kind.inlineChildren) }
    }

    /// A fit-content text node.
    private static func text(_ id: String, _ content: String) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(),
            kind: .text(PenNode.TextData(width: .fitContent(fallback: nil), content: .literal(content)))
        )
    }
}
