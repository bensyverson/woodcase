//
//  SyntheticPenDocument.swift
//  WoodcaseTests
//

import Foundation
import Woodcase

/// A deterministic synthetic document of any size: nested frames with text leaves.
///
/// The real fixtures are small — `woodcase-app.pen` is 392 authored nodes — so a
/// budget measured only against them says nothing about the documents an editor will
/// reach. This builds one of any node count, with no randomness anywhere: the same
/// `nodeCount` always produces an identical document, so a figure measured today can
/// be compared with one measured next month.
///
/// ## The shape
///
/// Artboards, each a vertical auto-layout frame of rows; each row a horizontal frame
/// of ``textsPerRow`` text nodes. Every level is a real layout container with a gap
/// and padding, and every leaf is fit-content text, so the layout engine and the text
/// measurer both do work proportionate to the node count — which a flat list of
/// fixed-size rectangles would not exercise at all.
///
/// The last artboard is truncated so the document has *exactly* `nodeCount` nodes
/// rather than the nearest multiple of an artboard.
///
/// ```swift
/// let document = SyntheticPenDocument.make(nodeCount: 5000)
/// ```
enum SyntheticPenDocument {
    /// Text leaves under one row frame.
    static let textsPerRow: Int = 3

    /// Row frames under one artboard, before truncation.
    ///
    /// Large on purpose: `shot` renders **one** artboard, so a document split into
    /// many small ones would make the render budget a measurement of nothing.
    static let rowsPerArtboard: Int = 400

    /// The width every artboard is fixed at, in points.
    static let artboardWidth: Double = 400

    /// The horizontal gap between artboards, in points.
    static let artboardStride: Double = 480

    /// Builds a document with exactly `nodeCount` nodes.
    ///
    /// - Parameter nodeCount: How many nodes the document should contain, counting
    ///   artboards, rows and text leaves alike. Zero produces an empty document.
    /// - Returns: The document, ready to hand to ``PenParser/encodeForFile(_:)``.
    static func make(nodeCount: Int) -> PenDocument {
        var identifier = 0
        var remaining = max(0, nodeCount)
        var artboards: [PenNode] = []
        while remaining > 0 {
            artboards.append(
                artboard(number: artboards.count + 1, identifier: &identifier, remaining: &remaining)
            )
        }
        return PenDocument(children: artboards)
    }

    /// The name of the artboard `shot` and `tree` address in the budget tests.
    ///
    /// Always present for any `nodeCount` above zero, because the first artboard is
    /// the first thing ``make(nodeCount:)`` emits.
    static let firstArtboardName: String = "Screen 1"

    // MARK: - Nodes

    /// One top-level frame: a vertical stack of rows, laid out beside its neighbors.
    ///
    /// - Parameters:
    ///   - number: Which artboard this is, 1-based; it sets the name and the x offset.
    ///   - identifier: The running id counter, advanced once per node emitted.
    ///   - remaining: How many nodes are left to emit; decremented per node.
    /// - Returns: The artboard node.
    private static func artboard(
        number: Int,
        identifier: inout Int,
        remaining: inout Int
    ) -> PenNode {
        let id = nextID(&identifier)
        remaining -= 1
        var rows: [PenNode] = []
        while rows.count < rowsPerArtboard, remaining > 0 {
            rows.append(row(number: rows.count + 1, identifier: &identifier, remaining: &remaining))
        }
        return PenNode(
            id: id,
            common: PenNodeCommon(
                name: "Screen \(number)",
                x: .literal(Double(number - 1) * artboardStride),
                y: .literal(0)
            ),
            kind: .frame(PenNode.FrameData(
                width: .fixed(artboardWidth),
                height: .fitContent(fallback: nil),
                fills: .single(.shorthand("#ffffff")),
                layout: .vertical,
                gap: .literal(8),
                padding: .uniform(.literal(16))
            ))
        )
        .replacingChildren(rows)
    }

    /// One row: a horizontal frame of text leaves.
    ///
    /// - Parameters:
    ///   - number: Which row this is within its artboard, 1-based.
    ///   - identifier: The running id counter.
    ///   - remaining: How many nodes are left to emit.
    /// - Returns: The row node.
    private static func row(
        number: Int,
        identifier: inout Int,
        remaining: inout Int
    ) -> PenNode {
        let id = nextID(&identifier)
        remaining -= 1
        var texts: [PenNode] = []
        while texts.count < textsPerRow, remaining > 0 {
            texts.append(text(row: number, column: texts.count + 1, identifier: &identifier))
            remaining -= 1
        }
        return PenNode(
            id: id,
            common: PenNodeCommon(name: "Row \(number)"),
            kind: .frame(PenNode.FrameData(
                width: .fillContainer(fallback: nil),
                height: .fitContent(fallback: nil),
                cornerRadius: .uniform(.literal(6)),
                fills: .single(.shorthand(number.isMultiple(of: 2) ? "#f4f4f5" : "#fafafa")),
                layout: .horizontal,
                gap: .literal(12),
                padding: .symmetric(h: .literal(12), v: .literal(8))
            ))
        )
        .replacingChildren(texts)
    }

    /// One text leaf.
    ///
    /// The family is a system font on every platform the tests run on, so nothing here
    /// reaches ``GoogleFontResolver`` and no measurement waits on the network.
    ///
    /// - Parameters:
    ///   - row: The row this text sits in, for its content.
    ///   - column: The position within the row, 1-based.
    ///   - identifier: The running id counter.
    /// - Returns: The text node.
    private static func text(row: Int, column: Int, identifier: inout Int) -> PenNode {
        PenNode(
            id: nextID(&identifier),
            common: PenNodeCommon(name: "Label \(row)-\(column)"),
            kind: .text(PenNode.TextData(
                width: .fitContent(fallback: nil),
                height: .fitContent(fallback: nil),
                content: .literal("Row \(row) cell \(column)"),
                textGrowth: .auto,
                fontFamily: .literal("Helvetica"),
                fontSize: .literal(column == 1 ? 15 : 13),
                fontWeight: .literal(column == 1 ? "600" : "400"),
                lineHeight: .literal(1.4),
                fills: .single(.shorthand(column == 1 ? "#18181b" : "#71717a"))
            ))
        )
    }

    // MARK: - Ids

    /// The next id in sequence: `n00001`, `n00002`, …
    ///
    /// Five characters after the prefix keeps ids the same shape as Pen's own compact
    /// ids and unique to a hundred thousand nodes, well past anything measured here.
    ///
    /// - Parameter identifier: The counter to advance.
    /// - Returns: The id.
    private static func nextID(_ identifier: inout Int) -> String {
        identifier += 1
        return String(format: "n%05d", identifier)
    }
}

// MARK: - Children

private extension PenNode {
    /// A copy of a frame node carrying `children`.
    ///
    /// ``PenNode/FrameData`` takes its children in its initializer, and building them
    /// before the frame that owns them would mean threading the id counter through in
    /// the wrong order; this keeps the generator reading parent-first.
    ///
    /// - Parameter children: The children to attach. Ignored for a non-frame node,
    ///   which the generator never produces.
    /// - Returns: The node with its children set.
    func replacingChildren(_ children: [PenNode]) -> PenNode {
        guard case var .frame(data) = kind else { return self }
        data.children = children
        return PenNode(id: id, common: common, kind: .frame(data))
    }
}
