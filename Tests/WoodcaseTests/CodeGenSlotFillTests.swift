//
//  CodeGenSlotFillTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An instance's slot fill is passed as the slot's content in both code targets
/// (Penumbra spec §13.5 rule 13), over `slots-screen.pen`: `Screen` has a `List` slot whose
/// default content is two `Item A` rows and an empty `Actions` slot; the `Board` page
/// places `Default` (the default content), `Filled` (three `Item B` rows) and `Emptied`
/// (an empty fill, which shows nothing rather than the default).
struct CodeGenSlotFillTests {
    // MARK: - React

    @Test("React: each slot is an optional ReactNode prop")
    func reactSlotProps() throws {
        let screen = try Self.react("components/Screen.tsx")
        #expect(screen.contains("  list?: React.ReactNode;\n"))
        #expect(screen.contains("  actions?: React.ReactNode;\n"))
        #expect(screen.contains("  list,\n"))
        #expect(screen.contains("  actions,\n"))
    }

    @Test("React: a slot renders its prop where its children go, its default content when the prop is undefined")
    func reactSlotDefault() throws {
        let screen = try Self.react("components/Screen.tsx")
        #expect(screen.contains(/\{list === undefined \? \(\n\s+<>\n\s+<ItemA[^>]*\/>\n\s+<ItemA[^>]*\/>\n\s+<\/>\n\s+\) : list\}/))
        #expect(screen.contains(/\n\s+\{actions\}\n/))
        #expect(screen.contains("import { ItemA } from \"./ItemA\";"))
    }

    @Test("React: an instance passes its fill as the slot prop, an empty fill as null, and the default as nothing")
    func reactInstanceFills() throws {
        let board = try Self.react("pages/Board.tsx")
        #expect(!board.contains("Customized from"))
        // Default passes neither slot; Filled and Emptied pass only the list.
        #expect(board.components(separatedBy: "<Screen").count == 4)
        #expect(board.contains(/<Screen\n\s+style=/))
        #expect(!board.contains("actions="))
        #expect(board.contains(/<Screen\n\s+list=\{\n\s+<>\n\s+<ItemB[^>]*\/>\n\s+<ItemB[^>]*\/>\n\s+<ItemB[^>]*\/>\n\s+<\/>\n\s+\}/))
        #expect(board.contains(/<Screen\n\s+list=\{null\}/))
        #expect(board.contains("import { ItemB } from \"../components/ItemB\";"))
        #expect(board.contains("import { Screen } from \"../components/Screen\";"))
    }

    @Test("React: an instance that writes more than children on a slot frame is inlined")
    func reactSlotWithMoreIsInlined() throws {
        let json = """
        {"version": "2.20", "children": [
          {"id": "card", "name": "Card", "type": "frame", "reusable": true, "width": 100, "height": 60, "layout": "vertical",
           "children": [{"id": "body", "name": "Body", "type": "frame", "slot": [], "width": 80, "height": 20, "layout": "vertical"}]},
          {"id": "page", "name": "Page", "type": "frame", "width": 200, "height": 200, "layout": "vertical", "children": [
            {"id": "inst", "type": "ref", "ref": "card", "descendants": {"body": {"gap": 4, "children": []}}}]}
        ]}
        """
        let page = try Self.react("pages/Page.tsx", in: PenParser.parse(Data(json.utf8)))
        #expect(page.contains("Customized from: Card"))
    }

    // MARK: - SwiftUI

    @Test("SwiftUI: an instance passes its fill in the slot's trailing closure, an empty fill as an empty closure")
    func swiftUIInstanceFills() throws {
        let board = try #require(SwiftUIFixtures.pages("slots-screen").first?.content)
        #expect(!board.contains("inlined"))
        #expect(board.contains(/Screen\(\)\n/))
        #expect(board.contains(/Screen \{\n\s+ItemB\(\)[^\n]*\n(\s+\.[^\n]*\n)*\s+ItemB\(\)[^\n]*\n(\s+\.[^\n]*\n)*\s+ItemB\(\)[^\n]*\n(\s+\.[^\n]*\n)*\s+\} actions: \{\n\s+EmptyView\(\)\n\s+\}/))
        #expect(board.contains(/Screen \{\n\s+\} actions: \{\n\s+EmptyView\(\)\n\s+\}/))
    }

    // MARK: - Helpers

    /// A file React emits for `document` — `slots-screen.pen` by default — by its path.
    private static func react(_ path: String, in document: PenDocument? = nil) throws -> String {
        let document = try document ?? SwiftUIFixtures.document("slots-screen")
        let files = ReactEmitter.emit(
            document: document,
            components: ComponentAnalyzer.analyze(document),
            pages: PageAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document)
        ).files
        return try #require(files.first { $0.path == path }?.content, "no \(path) among \(files.map(\.path))")
    }
}
