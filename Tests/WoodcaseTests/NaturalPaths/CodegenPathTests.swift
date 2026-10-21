//
//  CodegenPathTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The code-generation keys read and write through `codegen.*` paths (leaf tRzkPS; Ben's
/// ruling, 2026-10-20, `project/2026-10-20-natural-paths-for-woodcase-properties.md`, rule 4
/// widened): `codegen.role=button` is stored in `metadata.woodcase.role`, where
/// ``ComponentAnalyzer`` reads it, and a write at the storage path is refused naming the
/// `codegen.*` path.
@MainActor
struct CodegenPathTests {
    private typealias Fixture = NaturalPathFixture

    private static let keys: [PenMetadata.WoodcaseKey] = [.props, .role, .states, .action, .scroll]

    private func set(_ properties: [String: AnyCodable], on id: String, in document: EditableDocument) throws {
        try Fixture.apply(EditPlanner.plan(.set(properties), routedAt: .node(id: id), in: document), to: document)
    }

    // MARK: - The table

    @Test("Each code-generation key's natural path is codegen.<key>, on every node type")
    func table() {
        for key in Self.keys {
            #expect(key.naturalPath == "codegen.\(key.rawValue)")
            #expect(key.naturalPathTypes == Set(PenNode.NodeType.allCases))
            #expect(PenMetadata.WoodcaseKey(naturalPath: "codegen.\(key.rawValue)") == key)
        }
        #expect(NodePropertyCodec.naturalCodegenPaths == Set(Self.keys.map { "codegen.\($0.rawValue)" }))
    }

    @Test("paths(for:) lists the codegen paths every node takes")
    func pathsListThem() throws {
        let paths = try NodePropertyCodec.paths(for: Fixture.node("Pln01"))
        #expect(paths.contains("codegen.role"))
        #expect(paths.contains("codegen.props"))
        #expect(paths == paths.sorted())
    }

    // MARK: - Writing

    @Test("A planned codegen.role=button stores the role where ComponentAnalyzer reads it")
    func roleReachesAnalyzer() throws {
        let document = try Fixture.document()
        try set(["codegen.role": "button"], on: "Bdg01", in: document)
        let badge = try #require(document.node(id: "Bdg01"))
        #expect(badge.common.metadata?[woodcase: .role] == "button")
        #expect(badge.common.metadata?[woodcase: .strokeDash] == [2, 2])
        let component = ComponentAnalyzer.analyze(document.materialize()).first { $0.id == "Bdg01" }
        #expect(component?.role == .button)
    }

    @Test("A deep codegen key writes one entry and keeps the others; null drops one")
    func deepKeys() throws {
        let document = try Fixture.document()
        try set(["codegen.props.label": "Box", "codegen.props.tint": "Box"], on: "Bdg01", in: document)
        try set(["codegen.props.tint": .null, "codegen.states.hover": "Box01"], on: "Bdg01", in: document)
        let metadata = try #require(document.node(id: "Bdg01")?.common.metadata)
        #expect(metadata[woodcase: .props] == ["label": "Box"])
        #expect(metadata[woodcase: .states] == ["hover": "Box01"])
        #expect(metadata[woodcase: .role] == "badge")
    }

    @Test("The codec's own write of a codegen path stores it in metadata.woodcase")
    func codecSetting() throws {
        let node = try NodePropertyCodec.setting("submit", at: "codegen.action", on: Fixture.node("Pln01"))
        #expect(node.common.metadata?[woodcase: .action] == "submit")
        let deep = try NodePropertyCodec.setting("Box", at: "codegen.props.label", on: node)
        #expect(deep.common.metadata?[woodcase: .props] == ["label": "Box"])
        #expect(deep.common.metadata?[woodcase: .action] == "submit")
    }

    // MARK: - Reading

    @Test("A codegen path, and a deep key below one, read what is stored")
    func reads() throws {
        let badge = try Fixture.node("Bdg01")
        #expect(try NodePropertyCodec.value(at: "codegen.role", of: badge) == "badge")
        #expect(try NodePropertyCodec.value(at: "codegen.scroll", of: badge) == .null)
        let document = try Fixture.document()
        try set(["codegen.props.label": "Box"], on: "Bdg01", in: document)
        let written = try #require(document.node(id: "Bdg01"))
        #expect(try NodePropertyCodec.value(at: "codegen.props.label", of: written) == "Box")
    }

    @Test("get and tree --props print codegen.role, never its storage path")
    func getAndTree() throws {
        let document = try Fixture.document()
        let report = try NodeLookup.find("Board/Badge", in: document, expanding: false).report
        #expect(report.properties?["codegen.role"] == "badge")
        #expect(report.properties?.keys.contains { $0.hasPrefix("common.metadata") } == false)
        let rows = try TreeView.rows(of: document, root: "Board/Badge", depth: 0, properties: ["codegen.role"])
        #expect(rows.first?.properties?["codegen.role"] == "badge")
    }

    // MARK: - Refusing the storage path

    @Test("A write at a code-generation key's storage path is refused, naming codegen.<key>", arguments: [
        ("common.metadata.woodcase.role", "codegen.role", AnyCodable.string("button")),
        ("common.metadata.woodcase.props", "codegen.props", AnyCodable.dictionary(["label": "Box"])),
        ("common.metadata.woodcase.states", "codegen.states", AnyCodable.dictionary([:])),
        ("common.metadata.woodcase.action", "codegen.action", AnyCodable.string("submit")),
        ("common.metadata.woodcase.scroll", "codegen.scroll", AnyCodable.string("vertical")),
    ])
    func storagePathRefused(storage: String, natural: String, value: AnyCodable) throws {
        let refusal = try #require(PlannerFixture.refusal(.set([storage: value]), at: "Board/Badge", in: Fixture.document()))
        #expect(refusal.code == .storedAtNaturalPath)
        #expect(refusal.message.contains("write \(natural)"), "\(refusal.message)")
    }

    @Test("A deep key below a storage path is refused naming the deep codegen path")
    func deepStoragePathRefused() throws {
        let refusal = try #require(PlannerFixture.refusal(
            .set(["common.metadata.woodcase.props.label": "Box"]), at: "Board/Badge", in: Fixture.document()
        ))
        #expect(refusal.code == .storedAtNaturalPath)
        #expect(refusal.message.contains("write codegen.props.label"), "\(refusal.message)")
    }

    // MARK: - Instances

    @Test("An instance override of codegen.action is stored in the override's own metadata.woodcase")
    func overrideStoredInMetadata() throws {
        let document = try Fixture.document()
        let box = ResolvedNodeAddress.instanceDescendant(refID: "Ins01", descendantKey: "Box01")
        try Fixture.apply(EditPlanner.plan(.override(["codegen.action": "cancel"], unset: []), at: box, in: document), to: document)
        #expect(Fixture.expanded("Ins01/Box01", in: document)?.common.metadata?[woodcase: .action] == "cancel")
        #expect(document.node(id: "Box01")?.common.metadata?[woodcase: .action] == nil)
    }

    // MARK: - Schema

    @Test("The schema lists each codegen path with the metadata key it is stored under")
    func schemaRows() {
        for key in Self.keys {
            let path = "codegen.\(key.rawValue)"
            let row = PenSchema.common.properties.first { $0.path == path }
            #expect(row?.key == .key("metadata.woodcase.\(key.rawValue)"), "\(path)")
            #expect(PenSchema.field(path, for: .frame) != nil, "\(path)")
        }
    }
}
