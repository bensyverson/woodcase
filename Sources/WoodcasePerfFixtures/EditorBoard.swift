//
//  EditorBoard.swift
//  WoodcasePerfFixtures
//

import Foundation
import Woodcase

/// ``SyntheticPenDocument/makeEditorBoard(nodeCount:)`` as an editable document, and the
/// ids the layout budgets' gestures act on.
///
/// Nothing is laid out yet: the first layout is the cold one every editor pays once, and
/// each budget primes it its own way before timing the gestures after it.
@MainActor
public final class EditorBoard {
    /// The board, editable.
    public let document: EditableDocument

    /// The 400-row list.
    public let listID: String

    /// The list's rows, in order.
    public let rows: [String]

    /// Each row's title text, in row order.
    public let titles: [String]

    /// A text inside the component definition that no instance overrides.
    public let definitionText: String

    /// Generates the board.
    ///
    /// - Parameter nodeCount: How many nodes the board has.
    /// - Throws: A ``PerformanceFixture/SetupError`` if the generated board lacks its list
    ///   or its component text.
    public init(nodeCount: Int) throws {
        let source = SyntheticPenDocument.makeEditorBoard(nodeCount: nodeCount)
        guard let list = Self.find(SyntheticPenDocument.editorBoardListName, in: source.children) else {
            throw PerformanceFixture.SetupError("The editor board has no \(SyntheticPenDocument.editorBoardListName).")
        }
        guard let first = source.children.first, let definitionText = Self.texts(in: first).last else {
            throw PerformanceFixture.SetupError("The editor board's component has no text.")
        }
        listID = list.id
        rows = list.kind.inlineChildren.map(\.id)
        titles = list.kind.inlineChildren.compactMap { $0.kind.inlineChildren.first?.id }
        self.definitionText = definitionText
        document = EditableDocument(from: source)
    }

    /// Every text node's id under `node`, depth first, `node` included.
    private static func texts(in node: PenNode) -> [String] {
        let own: [String] = if case .text = node.kind { [node.id] } else { [] }
        return own + node.kind.inlineChildren.flatMap(texts(in:))
    }

    /// The first node named `name`, depth first.
    private static func find(_ name: String, in nodes: [PenNode]) -> PenNode? {
        for node in nodes {
            if node.common.name == name { return node }
            if let found = find(name, in: node.kind.inlineChildren) { return found }
        }
        return nil
    }
}
