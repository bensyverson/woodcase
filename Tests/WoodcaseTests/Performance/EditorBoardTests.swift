//
//  EditorBoardTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Holds the editor-board generator to what a benchmark needs of a fixture: the same
/// bytes every time, an exact node count, and a file the loader accepts.
struct EditorBoardTests {
    /// The environment variable naming where ``writesALoadableFile()`` leaves the board,
    /// so Penumbra's drag-bench can open it.
    static let outputEnvironmentVariable = "WOODCASE_EDITOR_BOARD_OUT"

    @Test("The same node count always encodes to identical bytes")
    func isDeterministic() throws {
        let first = try PenParser.encodeForFile(SyntheticPenDocument.makeEditorBoard(nodeCount: 2000))
        let second = try PenParser.encodeForFile(SyntheticPenDocument.makeEditorBoard(nodeCount: 2000))
        #expect(first == second)
    }

    @Test("The board has exactly the requested number of nodes", arguments: [200, 2000])
    func hasExactNodeCount(nodeCount: Int) {
        let document = SyntheticPenDocument.makeEditorBoard(nodeCount: nodeCount)
        #expect(Self.count(document.children) == nodeCount)
    }

    @Test("The board carries the shapes the layout budgets need")
    func hasEveryShape() {
        let document = SyntheticPenDocument.makeEditorBoard(nodeCount: 2000)
        let all = Self.flatten(document.children)
        #expect(all.contains { $0.common.reusable == true })
        #expect(all.contains { if case .ref = $0.kind { true } else { false } })
        #expect(all.contains { if case let .text(data) = $0.kind { data.textGrowth == .fixedWidth } else { false } })
        let list = all.first { $0.common.name == SyntheticPenDocument.editorBoardListName }
        #expect(list?.kind.inlineChildren.count == SyntheticPenDocument.editorBoardListRows)
    }

    /// A drag bench that presses on the board must hit the board, not the component
    /// definition drawn over its corner.
    @Test("The component sits beside the board, not under it")
    func rootsDoNotOverlap() throws {
        let document = SyntheticPenDocument.makeEditorBoard(nodeCount: 200)
        let rects = PenLayoutEngine.layout(document)
        let roots = try document.children.map { try #require(rects[$0.id]) }
        try #require(roots.count == 2)
        let (first, second) = (roots[0], roots[1])
        let overlaps = first.x < second.x + second.width && second.x < first.x + first.width
            && first.y < second.y + second.height && second.y < first.y + first.height
        #expect(!overlaps)
    }

    @Test("The board writes a file the loader opens")
    func writesALoadableFile() throws {
        let environment = ProcessInfo.processInfo.environment[Self.outputEnvironmentVariable]
        let url = try environment.map { URL(fileURLWithPath: $0) }
            ?? PerformanceFixture.scratchFile(named: "editor-board-2000.pen")
        defer { if environment == nil { PerformanceFixture.discard(url) } }
        try PenParser.encodeForFile(SyntheticPenDocument.makeEditorBoard(nodeCount: 2000)).write(to: url)

        let loaded = try PenParser.parse(contentsOf: url)
        #expect(Self.count(loaded.children) == 2000)
    }

    // MARK: - Counting

    private static func flatten(_ nodes: [PenNode]) -> [PenNode] {
        nodes.flatMap { [$0] + flatten($0.kind.inlineChildren) }
    }

    private static func count(_ nodes: [PenNode]) -> Int {
        flatten(nodes).count
    }
}
