//
//  FigmaImportComponentTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// C1 and R1: components, instances, styles and variables.
struct FigmaImportComponentTests {
    private typealias Fixtures = FigmaImportFixtures

    @Test("A main component is a reusable frame with its children")
    func mainComponent() throws {
        let node = try Fixtures.node("C1a main", in: Fixtures.imported("C1").clip.document)
        #expect(node.common.reusable == true)
        guard case .frame = node.kind else {
            Issue.record("\(node.kind)")
            return
        }
        #expect(Fixtures.children(of: node).map(\.common.name) == ["C1a label", "C1a swatch"])
    }

    @Test("An instance of a pasted component is a ref to it, its overrides carried")
    func instance() throws {
        let result = try Fixtures.imported("C1")
        let node = try Fixtures.node("C1c instance", in: result.clip.document)
        guard case let .ref(data) = node.kind else {
            Issue.record("\(node.kind)")
            return
        }
        #expect(data.ref == "figma-1-356")
        #expect(node.common.x == .literal(40) && node.common.y == .literal(980))
        #expect(data.rootOverrides?["fill"] == .array([.dictionary(["type": .string("color"), "color": .string("#FFF3BFFF")])]))
        #expect(data.descendants?["figma-1-358"]?.properties == ["enabled": .bool(false)])
        #expect(data.descendants?["figma-1-357"]?.properties == ["content": .string("Override text")])
        #expect(Fixtures.losses("C1c instance", in: result).isEmpty)
    }

    @Test("A swapped nested instance is reported")
    func swap() throws {
        let result = try Fixtures.imported("C1")
        let node = try Fixtures.node("C1d nested", in: result.clip.document)
        guard case let .ref(data) = node.kind else {
            Issue.record("\(node.kind)")
            return
        }
        #expect(data.ref == "figma-1-365")
        #expect(Fixtures.losses("C1d nested", in: result).map(\.feature) == [.instanceSwap])
    }

    @Test("Variants and component properties are reported on the component that defines them")
    func variants() throws {
        let result = try Fixtures.imported("C1")
        #expect(Fixtures.losses("C1b variants", in: result).map(\.feature) == [.variants])
        #expect(Fixtures.losses("C1a main", in: result).map(\.feature) == [.componentProperties])
        let small = try Fixtures.node("Size=Small", in: result.clip.document)
        #expect(small.common.reusable == true)
    }

    @Test("Paint and effect styles are resolved to their values and reported", arguments: ["C1e style-paint", "C1g style-effect"])
    func styles(name: String) throws {
        let losses = try Fixtures.losses(name, in: Fixtures.imported("C1"))
        #expect(losses.map(\.feature) == [.styleReference])
        #expect(losses.first?.treatment == .resolved)
    }

    /// An instance of a component the clipboard does not carry.
    private static let orphan = Fixtures.nodeChange("INSTANCE", name: "orphan", id: 50, width: 40, height: 20, extra: [
        "fillPaints": .array([Fixtures.solid(1, 0, 0)]),
        "symbolData": .message(KiwiRecord(typeName: "SymbolData", fields: ["symbolID": Fixtures.guid(9, 9)])),
    ])

    @Test("An instance whose component is not in the clipboard is a placeholder frame of its size, reported")
    func missingComponent() throws {
        let result = try FigmaImporter().clip(from: Fixtures.message([Self.orphan]))
        let node = try #require(result.clip.document.children.first)
        guard case let .frame(data) = node.kind else {
            Issue.record("\(node.kind)")
            return
        }
        #expect(data.width == .fixed(40) && data.height == .fixed(20))
        #expect(data.fills?.all == [.color(PenFill.PenColorFill(color: .literal("#FF0000FF")))])
        #expect(result.losses.map(\.feature) == [.missingComponent])
        #expect(result.losses.map(\.treatment) == [.placeholder])
    }

    @Test("Asked to, the importer refuses an instance whose component is not in the clipboard")
    func missingComponentRefused() throws {
        let importer = FigmaImporter(options: FigmaImportOptions(missingComponents: .refuse))
        #expect(throws: FigmaImportError.missingComponent(
            FigmaImportError.UnsupportedNode(type: "INSTANCE", name: "orphan", nodeID: "figma-1-50")
        )) {
            try importer.clip(from: Fixtures.message([Self.orphan]))
        }
    }

    @Test("A bound variable is resolved to its value and reported, once per node", arguments: [
        "R1 fill bound", "R1 radius bound", "R1 visibility bound", "R1 alias bound", "R1 dark fill bound",
    ])
    func variables(name: String) throws {
        let losses = try Fixtures.losses(name, in: Fixtures.imported("R1"))
        #expect(losses.map(\.feature) == [.variableBinding])
        #expect(losses.first?.treatment == .resolved)
    }

    @Test("A frame pinned to a variable mode is reported, and its children keep the mode's values")
    func variableMode() throws {
        let result = try Fixtures.imported("R1")
        #expect(Fixtures.losses("R1 dark mode", in: result).map(\.feature) == [.variableMode])
        let node = try Fixtures.node("R1 dark fill bound", in: result.clip.document)
        #expect(node.kind.paintLists.fills?.all == [.color(PenFill.PenColorFill(color: .literal("#91A7FFFF")))])
    }

    @Test("A bound corner radius keeps its resolved value")
    func boundRadius() throws {
        let node = try Fixtures.node("R1 radius bound", in: Fixtures.imported("R1").clip.document)
        guard case let .rectangle(data) = node.kind else {
            Issue.record("\(node.kind)")
            return
        }
        #expect(data.cornerRadius == .uniform(.literal(8)))
    }
}
