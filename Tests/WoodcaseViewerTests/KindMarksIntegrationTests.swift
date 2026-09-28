//
//  KindMarksIntegrationTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// The outline shows all three role marks together, on a real file's own tree — not
/// just on synthetic rows a preview test builds by hand.
///
/// `banking.pen`'s top-level frames are definitions with placed instances (`nSNTs`,
/// `YGJ0d/nSNTs`), which is exactly the shape a real file takes; it has no slot frame of
/// its own, so this test adds one, the way an agent would with `woodcase set`, to a
/// scratch copy — the checked-in fixture is never touched.
@MainActor
struct KindMarksIntegrationTests {
    @Test("A definition, an instance and a slot each mark their row in a real file's outline")
    func realFileShowsAllThreeMarks() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFixtures.copy("banking.pen", into: scratch)
        let log = ActivityLog(home: scratch)

        // `Y7mzM` ("transactions-section") is a plain frame inside the `nSNTs`
        // definition — turning it into a slot does not disturb the definition or
        // instance marks already on `nSNTs` and `YGJ0d/nSNTs`.
        try await PenFileTransaction.run(at: file, identity: "tester", log: log, timeout: ViewerFixtures.lockBudget) { _, recorder in
            try recorder.apply(.setProperties(EditOperation.SetProperties(
                nodeID: "Y7mzM", properties: ["kind.slot": .array([.string("text"), .string("frame")])]
            )))
        }

        let document = try EditableDocument(from: PenParser.parse(contentsOf: file))
        let rows = try TreeView.rows(of: document)
        let html = OutlinePanel(
            rows: rows,
            revision: document.documentRevision,
            file: "test",
            artboard: "nSNTs",
            state: ViewState()
        ).render()

        #expect(html.contains("v-kind-component"))
        #expect(html.contains("v-kind-instance"))
        #expect(html.contains("v-kind-slot"))

        let slotRow = try #require(rows.first { $0.id == "Y7mzM" })
        #expect(slotRow.isSlot)
        let definitionRow = try #require(rows.first { $0.id == "nSNTs" })
        #expect(definitionRow.isReusable)
    }
}
