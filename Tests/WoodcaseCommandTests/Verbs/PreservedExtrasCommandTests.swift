//
//  PreservedExtrasCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// A file carrying keys and types this build does not model — at the root, on nodes,
/// on fills, on a stroke's paint and on effects, plus an unknown effect type, an unknown
/// fill type and an unknown node type — keeps every one of them through each write verb
/// and through undo. Authoring input with an unknown key is still refused.
@Suite("Preserved unknown keys")
struct PreservedExtrasCommandTests {
    // MARK: - Helpers

    private typealias Object = [String: Any]

    private func fixture() throws -> CommandFixture {
        try CommandFixture(fixture: "preserved-extras.pen")
    }

    private func json(_ url: URL) throws -> Object {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? Object)
    }

    /// Every node object in the file, depth first.
    private func nodes(in object: Object) -> [Object] {
        let children = (object["children"] as? [Object]) ?? []
        return children.flatMap { [$0] + nodes(in: $0) }
    }

    private func nodes(named name: String, in object: Object) -> [Object] {
        nodes(in: object).filter { $0["name"] as? String == name }
    }

    /// Checks every preserved value the fixture carries is still in `url`.
    ///
    /// - Parameter boards: How many copies of `Board` the file should hold, each with
    ///   every extra of the original.
    private func expectEverythingPreserved(in url: URL, boards: Int = 1, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let root = try json(url)
        #expect(root["futureRootKey"] as? NSDictionary == ["a": 1], sourceLocation: sourceLocation)
        let font = (root["fonts"] as? [Object])?.first
        #expect(font?["name"] as? String == "Inter", sourceLocation: sourceLocation)
        #expect(font?["futureFontKey"] as? Int == 1, sourceLocation: sourceLocation)

        let copies = nodes(named: "Board", in: root)
        #expect(copies.count == boards, sourceLocation: sourceLocation)
        for board in copies {
            #expect(board["futureNodeKey"] as? NSDictionary == ["nested": [1, 2]], sourceLocation: sourceLocation)
            let fills = board["fill"] as? [Object] ?? []
            #expect(fills.first?["futureFillKey"] as? Bool == true, sourceLocation: sourceLocation)
            #expect(fills.last?["type"] as? String == "hologram", sourceLocation: sourceLocation)
            #expect(fills.last?["shimmer"] as? Double == 0.5, sourceLocation: sourceLocation)
            #expect((board["stroke"] as? Object)?["futureStrokeKey"] as? String == "s", sourceLocation: sourceLocation)
            let effects = board["effect"] as? [Object] ?? []
            #expect(effects.map { $0["type"] as? String } == ["shadow", "blur", "background_blur", "glow"], sourceLocation: sourceLocation)
            #expect(effects.first?["futureShadowKey"] as? Int == 7, sourceLocation: sourceLocation)
            #expect(effects.dropFirst().first?["futureBlurKey"] as? Int == 1, sourceLocation: sourceLocation)
            #expect(effects.dropFirst(2).first?["futureBackdropKey"] as? Int == 2, sourceLocation: sourceLocation)
            #expect(effects.last?["spreadColor"] as? String == "#FF00FF", sourceLocation: sourceLocation)
        }
        let cards = nodes(named: "Card", in: root)
        #expect(cards.count == boards, sourceLocation: sourceLocation)
        #expect(cards.allSatisfy { $0["futureChildKey"] as? String == "kept" }, sourceLocation: sourceLocation)
        let gizmos = nodes(named: "Gizmo", in: root)
        #expect(gizmos.count == boards, sourceLocation: sourceLocation)
        #expect(gizmos.allSatisfy { $0["type"] as? String == "gizmo" && $0["knob"] as? Int == 3 }, sourceLocation: sourceLocation)

        let instance = try #require(nodes(named: "Inst", in: root).first, sourceLocation: sourceLocation)
        let label = (instance["descendants"] as? Object)?["Label"] as? Object
        #expect(label?["futureOverrideKey"] as? String == "o", sourceLocation: sourceLocation)
    }

    // MARK: - Criterion: unknowns survive every write and undo

    @Test("set on another property keeps every unknown")
    func setKeeps() throws {
        let fixture = try fixture()
        let run = try fixture.run("set", fixture.file.path, "Board", "kind.width=410", "common.name=Board", "--as", "ana")
        #expect(run.status == 0, "\(run.stderr)")
        try expectEverythingPreserved(in: fixture.file)
    }

    @Test("cp copies every unknown with the node")
    func copyKeeps() throws {
        let fixture = try fixture()
        let run = try fixture.run("cp", fixture.file.path, "Board", "document", "--as", "ana")
        #expect(run.status == 0, "\(run.stderr)")
        try expectEverythingPreserved(in: fixture.file, boards: 2)
    }

    @Test("mv keeps every unknown on the moved node")
    func moveKeeps() throws {
        let fixture = try fixture()
        let run = try fixture.run("mv", fixture.file.path, "Board/Card", "Spare", "--as", "ana")
        #expect(run.status == 0, "\(run.stderr)")
        try expectEverythingPreserved(in: fixture.file)
        let spare = try #require(nodes(named: "Spare", in: json(fixture.file)).first)
        #expect((spare["children"] as? [Object])?.first?["futureChildKey"] as? String == "kept")
    }

    @Test("override keeps the unknown key Pen wrote into the same override")
    func overrideKeeps() throws {
        let fixture = try fixture()
        let run = try fixture.run("override", fixture.file.path, "Inst/Label", "content=Changed", "--as", "ana")
        #expect(run.status == 0, "\(run.stderr)")
        try expectEverythingPreserved(in: fixture.file)
    }

    @Test("rm then undo restores the node with every unknown")
    func removeUndoRestores() throws {
        let fixture = try fixture()
        #expect(try fixture.run("rm", fixture.file.path, "Board", "--as", "ana").status == 0)
        #expect(try nodes(named: "Board", in: json(fixture.file)).isEmpty)

        let run = try fixture.run("undo", fixture.file.path, "--as", "ana")

        #expect(run.status == 0, "\(run.stderr)")
        try expectEverythingPreserved(in: fixture.file)
    }

    @Test("Overwriting the fills then undoing restores the unknown fill keys and types")
    func setFillsUndoRestores() throws {
        let fixture = try fixture()
        #expect(try fixture.run("set", fixture.file.path, "Board", "kind.fills=#000000", "--as", "ana").status == 0)

        let run = try fixture.run("undo", fixture.file.path, "--as", "ana")

        #expect(run.status == 0, "\(run.stderr)")
        try expectEverythingPreserved(in: fixture.file)
    }

    // MARK: - Criterion: authoring stays strict

    @Test("add refuses a subtree with an unknown key, and leaves the file untouched")
    func addRefusesUnknownKey() throws {
        let fixture = try fixture()
        let before = try Data(contentsOf: fixture.file)
        let body = fixture.root.appendingPathComponent("subtree.json")
        try Data(##"{"type":"frame","name":"Hero","width":10,"height":10,"fil":"#FF0000"}"##.utf8).write(to: body)

        let run = try fixture.run("add", fixture.file.path, "document", "-F", body.path, "--as", "ana")

        #expect(run.status != 0)
        #expect(run.stderr.contains(#""fil" is not a key"#), "\(run.stderr)")
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test("add refuses a node of an unknown type, names it, and leaves the file untouched")
    func addRefusesUnknownNodeType() throws {
        let fixture = try fixture()
        let before = try Data(contentsOf: fixture.file)
        let body = fixture.root.appendingPathComponent("subtree.json")
        try Data(#"{"type":"video_clip","name":"Clip"}"#.utf8).write(to: body)

        let run = try fixture.run("add", fixture.file.path, "document", "-F", body.path, "--as", "ana")

        #expect(run.status != 0)
        #expect(run.stderr.contains("video_clip"), "\(run.stderr)")
        #expect(run.stderr.contains("connection"), "the refusal lists the real types: \(run.stderr)")
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test("A file's unknown node type still survives an unrelated write")
    func fileUnknownNodeTypeSurvivesWrite() throws {
        let fixture = try fixture()
        let run = try fixture.run("set", fixture.file.path, "Spare", "common.name=Spare2", "--as", "ana")
        #expect(run.status == 0, "\(run.stderr)")
        let gizmos = try nodes(named: "Gizmo", in: json(fixture.file))
        #expect(gizmos.first?["type"] as? String == "gizmo")
    }

    @Test("replace refuses a subtree with an unknown key on a fill")
    func replaceRefusesUnknownFillKey() throws {
        let fixture = try fixture()
        let body = fixture.root.appendingPathComponent("subtree.json")
        try Data(##"{"type":"rectangle","name":"Card","fill":{"type":"color","color":"#FFF","colour":"#000"}}"##.utf8).write(to: body)

        let run = try fixture.run("replace", fixture.file.path, "Board/Card", "-F", body.path, "--as", "ana")

        #expect(run.status != 0)
        #expect(run.stderr.contains("colour"), "\(run.stderr)")
    }

    @Test("set refuses a fill value with an unknown key")
    func setRefusesUnknownFillKey() throws {
        let fixture = try fixture()
        let run = try fixture.run(
            "set", fixture.file.path, "Spare", ##"kind.fills=[{"type":"color","color":"#FFFFFF","glossy":true}]"##, "--as", "ana"
        )
        #expect(run.status != 0)
        #expect(run.stderr.contains("glossy"), "\(run.stderr)")
    }

    @Test("apply refuses an effect value with an unknown key")
    func applyRefusesUnknownEffectKey() throws {
        let fixture = try fixture()
        let ops = fixture.root.appendingPathComponent("ops.jsonl")
        try Data(#"{"op":"set","target":"Spare","props":{"kind.effects":{"type":"blur","radius":2,"soft":1}}}"#.utf8).write(to: ops)

        let run = try fixture.run("apply", fixture.file.path, "-F", ops.path, "--as", "ana")

        #expect(run.status != 0)
        #expect((run.stdout + run.stderr).contains("soft"), "\(run.stdout)\(run.stderr)")
    }

    @Test("set on a preserved key is refused, and says the key is preserved")
    func setOnPreservedKeyIsRefused() throws {
        let fixture = try fixture()
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run("set", fixture.file.path, "Board", "kind.futureNodeKey=1", "--as", "ana")

        #expect(run.status != 0)
        #expect(run.stderr.contains("kept as the file wrote it"), "\(run.stderr)")
        #expect(try Data(contentsOf: fixture.file) == before)
    }
}
