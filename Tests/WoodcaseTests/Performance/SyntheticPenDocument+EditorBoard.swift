//
//  SyntheticPenDocument+EditorBoard.swift
//  WoodcaseTests
//

import Foundation
import Woodcase

extension SyntheticPenDocument {
    /// The rows in the board's long list — the container a reorder or a removal is
    /// measured in.
    static let editorBoardListRows: Int = 400

    /// The name of the board's long list.
    static let editorBoardListName: String = "Task list"

    /// The fewest nodes a board can have: one component, the board frame, a header and
    /// the two section frames. A smaller request is raised to this.
    static let editorBoardMinimumNodeCount: Int = 13

    /// Builds an editor-shaped board with exactly `nodeCount` nodes.
    ///
    /// ``make(nodeCount:)`` is a uniform grid of fit-content labels; a real board is
    /// not. This one mixes the things an editor drag meets: stacks nested in stacks,
    /// fill sizing on both axes' containers, wrapping text, instances of a reusable
    /// component (one overriding its title), and a ``editorBoardListRows``-row list.
    /// Nothing is random, so the same `nodeCount` always encodes to the same bytes.
    ///
    /// ```
    /// Card                       reusable component, 6 nodes, right of the board
    /// Board                      vertical, fixed 1200 wide, at the origin
    ///   Header                   horizontal, 3 texts
    ///   Cards                    vertical rows of 3 Card instances
    ///   Task list                vertical, 400 rows of (title, wrapping text, meta)
    /// ```
    ///
    /// The list takes up to 400 rows (a small board keeps 100 nodes back for the
    /// cards); the cards take every node left over, the last row truncated.
    ///
    /// The layout-edit budgets (`PerformanceBudgets.LayoutEditTests`) are measured on
    /// it, and Penumbra's drag bench opens the file `EditorBoardTests` writes.
    ///
    /// - Parameter nodeCount: Total nodes, counting every authored node. Raised to
    ///   ``editorBoardMinimumNodeCount`` when smaller.
    /// - Returns: The document, ready for ``PenParser/encodeForFile(_:)``.
    static func makeEditorBoard(nodeCount: Int) -> PenDocument {
        var builder = EditorBoardBuilder()
        let total = max(nodeCount, editorBoardMinimumNodeCount)
        let available = total - editorBoardMinimumNodeCount
        let listRows = max(0, min(editorBoardListRows, (available - EditorBoardBuilder.cardReserve) / EditorBoardBuilder.nodesPerListRow))
        let cardNodes = available - listRows * EditorBoardBuilder.nodesPerListRow

        let component = builder.component()
        let board = builder.board(component: component, cardNodes: cardNodes, listRows: listRows)
        return PenDocument(children: [component.node, board])
    }
}

/// The ids and parts of the reusable component the board's instances point at.
private struct EditorBoardComponent {
    /// The definition itself.
    var node: PenNode
    /// The definition's id, which every instance refs.
    var id: String
    /// The title text's id, which every instance overrides.
    var titleID: String
}

/// Emits the board's nodes parent-first with sequential ids.
private struct EditorBoardBuilder {
    /// Nodes in one list row: the row frame and its three texts.
    static let nodesPerListRow: Int = 4

    /// Nodes held back for the cards before the list takes its share of a small board.
    static let cardReserve: Int = 100
    static let instancesPerCardRow: Int = 3

    /// The board's fixed width, in points.
    static let boardWidth: Double = 1200

    /// The space between the board's right edge and the component definition.
    static let componentGap: Double = 80

    /// The last id handed out.
    private var identifier = 0

    /// The next sequential id, `n00001` onward.
    private mutating func nextID() -> String {
        identifier += 1
        return String(format: "n%05d", identifier)
    }

    // MARK: - Component

    /// The reusable card: a title, a wrapping body and a footer of two labels.
    mutating func component() -> EditorBoardComponent {
        let id = nextID()
        let titleID = nextID()
        let title = text(id: titleID, "Card title", size: 15, weight: "600", color: "#18181b")
        let body = text(
            id: nextID(),
            "A card body long enough to wrap across several lines once the card is a third of the board's width.",
            size: 13,
            weight: "400",
            color: "#52525b",
            wraps: true
        )
        let footer = frame(
            id: nextID(),
            name: "Footer",
            layout: .horizontal,
            gap: 8,
            children: [
                text(id: nextID(), "Updated", size: 11, weight: "400", color: "#a1a1aa"),
                text(id: nextID(), "2 comments", size: 11, weight: "400", color: "#a1a1aa"),
            ]
        )
        var card = frame(
            id: id,
            name: "Card",
            layout: .vertical,
            gap: 8,
            padding: .uniform(.literal(12)),
            fill: "#ffffff",
            radius: 8,
            children: [title, body, footer],
            width: .fixed(360),
            reusable: true
        )
        // Beside the board rather than at the origin, where it would sit over the
        // board's corner and catch the presses a drag bench aims at the board.
        card.common.x = .literal(Self.boardWidth + Self.componentGap)
        card.common.y = .literal(0)
        return EditorBoardComponent(node: card, id: id, titleID: titleID)
    }

    // MARK: - Board

    /// The board root: a header, `cardNodes` nodes of card rows and a `listRows`-row list.
    mutating func board(component: EditorBoardComponent, cardNodes: Int, listRows: Int) -> PenNode {
        let id = nextID()
        let header = frame(
            id: nextID(),
            name: "Header",
            layout: .horizontal,
            gap: 12,
            children: [
                text(id: nextID(), "Sprint board", size: 22, weight: "700", color: "#18181b"),
                text(id: nextID(), "12 open", size: 13, weight: "400", color: "#71717a"),
                text(id: nextID(), "Updated just now", size: 13, weight: "400", color: "#71717a"),
            ]
        )
        let cards = cardSection(component: component, nodes: cardNodes + 1)
        let list = taskList(rows: listRows)
        return PenNode(
            id: id,
            common: PenNodeCommon(name: "Board", x: .literal(0), y: .literal(0)),
            kind: .frame(PenNode.FrameData(
                width: .fixed(Self.boardWidth),
                height: .fitContent(fallback: nil),
                fills: .single(.shorthand("#f4f4f5")),
                layout: .vertical,
                gap: .literal(16),
                padding: .uniform(.literal(24)),
                children: [header, cards, list]
            ))
        )
    }

    /// The card section: rows of instances, using exactly `nodes` nodes including the
    /// section frame itself.
    private mutating func cardSection(component: EditorBoardComponent, nodes: Int) -> PenNode {
        let section = nextID()
        var remaining = nodes - 1
        var rows: [PenNode] = []
        var number = 0
        while remaining > 0 {
            number += 1
            let row = nextID()
            remaining -= 1
            var instances: [PenNode] = []
            while instances.count < Self.instancesPerCardRow, remaining > 0 {
                instances.append(instance(of: component, number: number * 10 + instances.count))
                remaining -= 1
            }
            rows.append(frame(
                id: row,
                name: "Card row \(number)",
                layout: .horizontal,
                gap: 12,
                children: instances
            ))
        }
        return frame(id: section, name: "Cards", layout: .vertical, gap: 12, children: rows)
    }

    /// One instance of the card, overriding its title so no two instances read alike.
    private mutating func instance(of component: EditorBoardComponent, number: Int) -> PenNode {
        PenNode(
            id: nextID(),
            common: PenNodeCommon(name: "Card \(number)"),
            kind: .ref(PenNode.RefData(
                ref: component.id,
                descendants: [
                    component.titleID: PenDescendantOverride(properties: [
                        "content": .string("Card \(number): a title that varies"),
                    ]),
                ]
            ))
        )
    }

    /// The long list a reorder and a resize are measured in.
    private mutating func taskList(rows: Int) -> PenNode {
        let id = nextID()
        var children: [PenNode] = []
        for number in 0 ..< rows {
            children.append(listRow(number: number + 1))
        }
        return frame(id: id, name: SyntheticPenDocument.editorBoardListName, layout: .vertical, gap: 4, children: children)
    }

    /// One list row: a title, a fill-width wrapping detail whose length cycles, and a label.
    private mutating func listRow(number: Int) -> PenNode {
        let id = nextID()
        let title = text(id: nextID(), "Task \(number)", size: 14, weight: "600", color: "#18181b")
        let detail = text(
            id: nextID(),
            "Task \(number) details: " + String(repeating: "wraps over a line or two ", count: 1 + number % 3),
            size: 13,
            weight: "400",
            color: "#52525b",
            wraps: true
        )
        let meta = text(id: nextID(), "P\(number % 4)", size: 12, weight: "400", color: "#a1a1aa")
        return frame(
            id: id,
            name: "Task row \(number)",
            layout: .horizontal,
            gap: 12,
            padding: .symmetric(h: .literal(12), v: .literal(8)),
            fill: number.isMultiple(of: 2) ? "#fafafa" : "#ffffff",
            radius: 6,
            children: [title, detail, meta]
        )
    }

    // MARK: - Parts

    /// A fit-content-height flex frame, fill-width unless `width` says otherwise.
    private func frame(
        id: String,
        name: String,
        layout: PenLayoutDirection,
        gap: Double,
        padding: PenPadding? = nil,
        fill: String? = nil,
        radius: Double? = nil,
        children: [PenNode],
        width: PenSizing = .fillContainer(fallback: nil),
        reusable: Bool? = nil
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: name, reusable: reusable),
            kind: .frame(PenNode.FrameData(
                width: width,
                height: .fitContent(fallback: nil),
                cornerRadius: radius.map { .uniform(.literal($0)) },
                fills: fill.map { .single(.shorthand($0)) },
                layout: layout,
                gap: .literal(gap),
                padding: padding,
                children: children
            ))
        )
    }

    /// A Helvetica text: fit-content, or fill-width and wrapping when `wraps`.
    private func text(
        id: String,
        _ content: String,
        size: Double,
        weight: String,
        color: String,
        wraps: Bool = false
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(),
            kind: .text(PenNode.TextData(
                width: wraps ? .fillContainer(fallback: nil) : .fitContent(fallback: nil),
                height: .fitContent(fallback: nil),
                content: .literal(content),
                textGrowth: wraps ? .fixedWidth : .auto,
                fontFamily: .literal("Helvetica"),
                fontSize: .literal(size),
                fontWeight: .literal(weight),
                lineHeight: .literal(1.4),
                fills: .single(.shorthand(color))
            ))
        )
    }
}
