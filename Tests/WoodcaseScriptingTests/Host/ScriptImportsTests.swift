//
//  ScriptImportsTests.swift
//  WoodcaseScriptingTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseScripting

/// A script reads the same resolved document `tree` does: an instance of an imported
/// component has its component's size.
@Suite("scripts over imported libraries")
struct ScriptImportsTests {
    @Test("doc.tree() settles an imported instance")
    func treeSeesImportedInstance() throws {
        let directory = ScriptFixture.directory.appendingPathComponent("imports")
        let document = try EditableDocument(from: PenParser.parse(contentsOf: directory.appendingPathComponent("app.pen")))
        document.readContext = try PenReadContext(libraries: PenLibraries(documents: [
            "kit.lib.pen": PenParser.parse(contentsOf: directory.appendingPathComponent("kit.lib.pen")),
        ]))
        let runner = ScriptRunner(
            document: document, remedy: .batch, diagnostics: [], recorder: nil, deadline: nil, sink: nil
        )

        let run = runner.run([.text("doc.tree().find(r => r.id === 'Ins01').rect.width", name: "<argv>")])

        #expect(run.error == nil, "\(String(describing: run.error))")
        #expect(run.result == .int(80) || run.result == .double(80))
    }
}
