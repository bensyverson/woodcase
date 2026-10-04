//
//  BatchApplierDetachRollbackTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A batch line that fails after it has detached an instance rolls back through the
/// inverses captured before each edit, so those inverses have to undo the detach
/// completely — the expanded subtree out, the ref back in.
@MainActor
struct BatchApplierDetachRollbackTests {
    /// A component holding a nested component, an instance of the outer one, and an
    /// instance of the inner one outside both.
    ///
    /// `rm Outer --detach` detaches only Outer's instances, so the delete that follows
    /// still strands the inner component's instance and is refused — after the detach
    /// has already run.
    private func document() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(#"""
        {"version": "2.17", "children": [
          {"id": "Outer", "name": "Outer", "type": "frame", "reusable": true, "children": [
            {"id": "Inner", "name": "Inner", "type": "frame", "reusable": true, "children": [
              {"id": "Lbl", "name": "Label", "type": "text", "content": "hi"}
            ]}
          ]},
          {"id": "Board", "name": "Board", "type": "frame", "children": [
            {"id": "OutI", "name": "OuterUse", "type": "ref", "ref": "Outer"},
            {"id": "InnI", "name": "InnerUse", "type": "ref", "ref": "Inner"}
          ]}
        ]}
        """#))
    }

    private let removeOuter = #"{"op":"rm","target":"Outer","detach":true}"#

    @Test("A line that fails after its detach leaves the document exactly as it was")
    func failedLineRollsBackTheDetach() throws {
        let editable = try document()
        let before = editable.materialize()

        let report = try BatchApplier.apply(BatchOperation.decodeJSONL(removeOuter), to: editable)

        #expect(report.lines.map(\.status) == [.failed])
        #expect(editable.materialize() == before)
    }
}
