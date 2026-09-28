//
//  PenImportedExpansionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// An instance of an imported component expands, and the imported definition never
/// becomes one of the document's roots.
///
/// `Fixtures/imports/app.pen` imports `K` from the `kit.lib.pen` beside it. Pen draws
/// its three instances with their overrides applied — `Hello`, `Nested` through the
/// kit's own nested instance, and `Wrapped` through a host component holding a kit
/// instance — in the kit's `$accent`, and shows no kit component on the canvas.
struct PenImportedExpansionTests {
    /// The host and its library, parsed.
    static func fixture() throws -> (app: PenDocument, kit: PenDocument) {
        let directory = try #require(
            Bundle.module.url(forResource: "imports", withExtension: nil, subdirectory: "Fixtures")
        )
        return try (
            PenParser.parse(contentsOf: directory.appendingPathComponent("app.pen")),
            PenParser.parse(contentsOf: directory.appendingPathComponent("kit.lib.pen"))
        )
    }

    /// The definitions `app.pen`'s imports contribute.
    static func definitions() throws -> (app: PenDocument, definitions: PenImportedDefinitions) {
        let (app, kit) = try fixture()
        return (app, PenImportResolver.definitions(for: app.imports, libraries: ["kit.lib.pen": kit]))
    }

    /// Every node in a forest, keyed by id.
    static func index(_ nodes: [PenNode], into index: inout [String: PenNode]) {
        for node in nodes {
            index[node.id] = node
            Self.index(node.kind.inlineChildren, into: &index)
        }
    }

    @Test("The registry holds each imported reusable and those nested in one")
    func registryHoldsImportedReusables() throws {
        let (_, definitions) = try Self.definitions()

        #expect(Set(definitions.registry.keys) == ["K:Chip1", "K:Card1"])
    }

    @Test("An instance of an imported component expands; the definition is no root")
    func importedInstanceExpands() throws {
        let (app, definitions) = try Self.definitions()

        let expanded = definitions.expand(app, for: .canvas)

        #expect(expanded.children.map(\.id) == ["Art01", "Wrap1"])
        var nodes: [String: PenNode] = [:]
        Self.index(expanded.children, into: &nodes)
        #expect(nodes["Ins01/K:Chip1"] != nil)
    }

    @Test("Overrides reach an imported component, through a slash path in either namespace")
    func overridesApplyThroughImports() throws {
        let (app, definitions) = try Self.definitions()

        let expanded = definitions.expand(app, for: .canvas)

        var nodes: [String: PenNode] = [:]
        Self.index(expanded.children, into: &nodes)
        func content(_ id: String) -> String? {
            guard case let .text(data) = nodes[id]?.kind, case let .literal(text) = data.content else { return nil }
            return text
        }
        #expect(content("Ins01/K:Txt01") == "Hello")
        #expect(content("Ins02/K:Cc001/K:Txt01") == "Nested")
        #expect(content("Ins03/Kin01/K:Txt01") == "Wrapped")
    }

    @Test("An imported variable resolves once the definitions are merged")
    func importedVariableResolves() throws {
        let (app, definitions) = try Self.definitions()

        let resolved = PenVariableResolver.resolve(definitions.expand(app, for: .canvas))

        var nodes: [String: PenNode] = [:]
        Self.index(resolved.children, into: &nodes)
        guard case let .frame(chip) = nodes["Ins01/K:Chip1"]?.kind else {
            Issue.record("the instance did not expand to the kit's frame")
            return
        }
        #expect(chip.fills?.all.first == .shorthand("#FF6600"))
    }

    @Test("Expansion for export expands imported instances and adds no imported root")
    func exportAddsNoImportedRoots() throws {
        let (app, definitions) = try Self.definitions()

        let expanded = definitions.expand(app, for: .export)

        #expect(expanded.children.map(\.id) == ["Art01"])
        var nodes: [String: PenNode] = [:]
        Self.index(expanded.children, into: &nodes)
        #expect(nodes["Ins02/K:Card1"] != nil)
    }
}
