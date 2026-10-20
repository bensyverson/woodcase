//
//  NaturalPathCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// Woodcase-owned properties at their natural paths on the command line: `set` writes
/// `kind.strokeDash` into `metadata.woodcase`, `get`, `tree --props` and `schema` print the
/// natural paths, a write at the storage path is refused naming the natural one, and the
/// `doc` API in `woodcase js` reads and writes the same paths (leaf 9Sw8C0).
@Suite("woodcase natural paths")
struct NaturalPathCommandTests {
    private static let fixtureName = "natural-paths.pen"

    /// The JSON object the file stores for one node, found by id anywhere in the tree.
    private static func rawObject(id: String, in file: URL) throws -> [String: Any]? {
        func find(_ value: Any) -> [String: Any]? {
            if let object = value as? [String: Any] {
                if object["id"] as? String == id { return object }
                return object.values.lazy.compactMap(find).first
            }
            if let array = value as? [Any] { return array.lazy.compactMap(find).first }
            return nil
        }
        return try find(JSONSerialization.jsonObject(with: Data(contentsOf: file)))
    }

    @Test("set kind.strokeDash stores the dash under metadata.woodcase")
    func setStoresInMetadata() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        let run = try fixture.run("set", fixture.file.path, "Board/Plain", "kind.strokeDash=[4,2]", "--as", "ana")
        #expect(run.status == 0, "\(run.stderr)")
        let plain = try #require(try Self.rawObject(id: "Pln01", in: fixture.file))
        #expect(plain["strokeDash"] == nil)
        let node = try #require(PenFileProbe(fixture.file).node("Board/Plain"))
        #expect(node.common.metadata?[woodcase: .strokeDash] == [4, 2])
        #expect(node.strokeDash?.lengths == [4, 2])
        #expect(node.extras.isEmpty)
    }

    @Test("A write at the storage path is refused, naming the natural path")
    func storagePathRefused() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        let run = try fixture.run("set", fixture.file.path, "Board/Plain", "common.metadata.woodcase.strokeDash=[4,2]")
        #expect(run.status != 0)
        #expect(run.stderr.contains("common.metadata.woodcase.strokeDash is stored for you; write kind.strokeDash"), "\(run.stderr)")
        #expect(try PenFileProbe(fixture.file).node("Board/Plain")?.strokeDash == nil)
    }

    @Test("get prints the Woodcase-owned values at their natural paths")
    func getPrintsNaturalPaths() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        let run = try fixture.run("get", fixture.file.path, "Board/Card")
        #expect(run.status == 0, "\(run.stderr)")
        let lines = run.stdoutLines
        #expect(lines.contains { $0.hasPrefix("  kind.strokeDash") && $0.contains("[8,4]") }, "\(run.stdout)")
        #expect(lines.contains { $0.hasPrefix("  common.locked") && $0.hasSuffix("true") }, "\(run.stdout)")
        #expect(lines.contains { $0.hasPrefix("  kind.blendMode") && $0.contains("multiply") }, "\(run.stdout)")
        #expect(!run.stdout.contains("common.metadata.woodcase.strokeDash"))
    }

    @Test("get --json carries the natural paths beside the node")
    func getJSONCarriesNaturalPaths() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        let run = try fixture.run("get", fixture.file.path, "Board/Card", "--json")
        #expect(run.status == 0, "\(run.stderr)")
        let report = try JSONDecoder().decode(NodeReport.self, from: Data(run.stdout.utf8))
        #expect(report.properties?["kind.strokeDash"] == [8, 4])
        #expect(report.properties?["common.locked"] == true)
        #expect(report.properties?["kind.strokeDashOffset"] == 2)
    }

    @Test("get leaves the properties out of a node that sets none")
    func getOmitsWhenNone() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        let run = try fixture.run("get", fixture.file.path, "Board/Plain", "--json")
        #expect(run.status == 0, "\(run.stderr)")
        let report = try JSONDecoder().decode(NodeReport.self, from: Data(run.stdout.utf8))
        #expect(report.properties == nil)
    }

    @Test("tree --props reads natural paths")
    func treeReadsNaturalPaths() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        let run = try fixture.run(
            "tree", fixture.file.path, "Board/Card", "--props", "kind.strokeDash,common.locked,kind.strokeMiterLimit"
        )
        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stdout.contains("kind.strokeDash"), "\(run.stdout)")
        #expect(run.stdout.contains("common.locked"))
        let row = try #require(run.stdoutLines.first { $0.contains("Crd01") })
        #expect(row.contains("[8,4]") || row.contains("8,4"), "\(row)")
        #expect(row.contains("true"))
        #expect(row.contains("10"))
    }

    @Test("schema lists each natural path with the key the file stores it under")
    func schemaListsNaturalPaths() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        let frame = try fixture.run("schema", "frame")
        #expect(frame.status == 0)
        #expect(frame.stdoutLines.contains { $0.contains("kind.strokeDash ") && $0.contains("metadata.woodcase.strokeDash") },
                "\(frame.stdout)")
        #expect(frame.stdout.contains("kind.strokeMiterLimit"))
        let text = try fixture.run("schema", "text")
        #expect(text.stdout.contains("kind.spans"))
        #expect(text.stdout.contains("kind.defaultTextStyle"))
        let overview = try fixture.run("schema")
        #expect(overview.stdoutLines.contains { $0.contains("common.locked") && $0.contains("metadata.woodcase.locked") },
                "\(overview.stdout)")
    }

    @Test("The doc API in woodcase js reads and writes natural paths")
    func docAPI() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        let script = fixture.root.appendingPathComponent("natural.js")
        try """
        doc.set('Board/Plain', { 'kind.strokeDash': [3, 3], 'common.locked': true });
        const read = doc.get('Board/Plain').properties;
        const row = doc.tree('Board/Plain', { props: ['kind.strokeDash'] })[0].properties;
        `${JSON.stringify(read['kind.strokeDash'])} ${read['common.locked']} ${JSON.stringify(row['kind.strokeDash'])}`
        """.write(to: script, atomically: true, encoding: .utf8)
        let run = try fixture.run("js", fixture.file.path, "-F", script.path)
        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stdout.contains("[3,3] true [3,3]"), "\(run.stdout)")
        #expect(try PenFileProbe(fixture.file).node("Board/Plain")?.isLocked == true)
    }

    @Test("The doc API refuses a storage path with the same teaching error")
    func docAPIRefusesStoragePath() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        let script = fixture.root.appendingPathComponent("raw.js")
        try """
        try { doc.set('Board/Plain', { 'common.metadata.woodcase.locked': true }); 'wrote' }
        catch (e) { `${e.code}: ${e.message}` }
        """.write(to: script, atomically: true, encoding: .utf8)
        let run = try fixture.run("js", fixture.file.path, "-F", script.path)
        #expect(run.stdout.contains("write common.locked"), "\(run.stdout) \(run.stderr)")
    }
}
