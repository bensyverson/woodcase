//
//  EditableDocumentLibrariesTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A document carries the libraries it was read with as read context: every expansion
/// and every walk into a component sees them, and nothing writes them back.
struct EditableDocumentLibrariesTests {
    /// `Fixtures/imports/app.pen`, with `kit.lib.pen` attached as its only library.
    static func document() throws -> (EditableDocument, PenDocument) {
        let (app, kit) = try PenImportedExpansionTests.fixture()
        let document = EditableDocument(from: app)
        document.readContext = PenReadContext(
            libraries: PenLibraries(documents: ["kit.lib.pen": kit])
        )
        return (document, app)
    }

    /// Every node in a forest, keyed by id.
    static func index(_ document: PenDocument) -> [String: PenNode] {
        var index: [String: PenNode] = [:]
        PenImportedExpansionTests.index(document.children, into: &index)
        return index
    }

    @Test("The libraries reach every expansion and never what the document materializes")
    func librariesAreNotPersisted() throws {
        let (document, app) = try Self.document()

        #expect(Self.index(document.expanded(for: .export))["Ins01/K:Chip1"] != nil)
        #expect(document.materialize() == app)
    }

    @Test("A canvas expansion expands imported instances and adds no imported root")
    func expandedSeesImports() throws {
        let (document, _) = try Self.document()

        let expanded = document.expanded(for: .canvas)

        #expect(expanded.children.map(\.id) == ["Art01", "Wrap1"])
        #expect(Self.index(expanded)["Ins02/K:Cc001/K:Txt01"] != nil)
        #expect(expanded.variables?["K:accent"] != nil)
    }

    @Test("Attaching libraries invalidates an expansion made without them")
    func attachingLibrariesInvalidatesExpansion() throws {
        let (app, kit) = try PenImportedExpansionTests.fixture()
        let document = EditableDocument(from: app)
        let before = try document.expandRef(nodeID: "Ins01")
        #expect(before.expandedNode.id == "Ins01")

        document.readContext = PenReadContext(libraries: PenLibraries(documents: ["kit.lib.pen": kit]))

        #expect(try document.expandRef(nodeID: "Ins01").expandedNode.id == "Ins01/K:Chip1")
    }

    @Test("An instance's override keys reach into imported components")
    func overrideKeysReachImports() throws {
        let (document, _) = try Self.document()

        #expect(document.overridableDescendantKeys(ofInstance: "Ins02").contains("K:Cc001/K:Txt01"))
        #expect(document.overridableDescendantKeys(ofInstance: "Ins03").contains("Kin01/K:Txt01"))
    }

    @Test("An override on an imported descendant is accepted, and a stray one refused")
    func overrideTargetsAreJudgedThroughImports() throws {
        let (document, _) = try Self.document()

        try document.validateOverrideTarget(EditOperation.OverrideDescendant(
            refNodeID: "Ins03", descendantID: "Kin01/K:Txt01", properties: ["content": .string("x")]
        ))
        #expect(throws: EditingError.self) {
            try document.validateOverrideTarget(EditOperation.OverrideDescendant(
                refNodeID: "Ins03", descendantID: "Kin01/K:Nope1", properties: ["content": .string("x")]
            ))
        }
    }

    @Test("A name path runs through imported components, and resolves back")
    func namePathsRunThroughImports() throws {
        let (document, _) = try Self.document()

        #expect(document.namePath(ofDescendant: "K:Cc001/K:Txt01", in: "Ins02")
            == "screen/carded/badge/label")
        #expect(try document.resolve("screen/carded/badge/label")
            == .instanceDescendant(refID: "Ins02", descendantKey: "K:Cc001/K:Txt01"))
    }

    @Test("A component is imported only while the document's imports name its library")
    func repointingTheImportDropsTheComponents() throws {
        let (document, _) = try Self.document()
        #expect(Self.index(document.expanded(for: .canvas))["Ins01/K:Chip1"] != nil)

        // The read loaded kit.lib.pen and nothing else, so a repointed alias names a
        // library this document was not read with — until it is read again.
        try document.apply(.updateImport(EditOperation.UpdateImport(alias: "K", path: "other.lib.pen")))

        #expect(Self.index(document.expanded(for: .canvas))["Ins01/K:Chip1"] == nil)
    }

    @Test("The generation source is the materialized document with every imported component a root")
    func generationSourceMergesImportedComponents() throws {
        let (document, app) = try Self.document()
        let (_, kit) = try PenImportedExpansionTests.fixture()

        let source = document.materializeForGeneration()

        // One function for `generate` and the viewer's code panel, and it is exactly the
        // resolver's merge over what the file stores, with the libraries it was read with.
        #expect(source == PenImportResolver.resolve(app, libraries: ["kit.lib.pen": kit]))
        #expect(source.children.map(\.id) == ["Art01", "Wrap1", "K:Chip1", "K:Card1"])
        #expect(source.imports == nil)
        #expect(document.materialize() == app)
    }
}
