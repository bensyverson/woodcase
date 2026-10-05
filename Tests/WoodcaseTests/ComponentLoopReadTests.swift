//
//  ComponentLoopReadTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A document that arrives with component loops reads, reports each loop, and expands
/// none of the nesting among a loop's members — in the expander and in every walk that
/// mirrors it.
@MainActor
struct ComponentLoopReadTests {
    // MARK: - Helpers

    /// `CmpA` and `CmpB` hold an instance of each other; `CmpS` holds one of itself;
    /// `CmpD` holds an instance of `CmpB` from outside the loop; `Page` holds an
    /// instance of `CmpA` and of `CmpD`.
    static func loopy() throws -> PenDocument {
        try PenParser.parse(#"""
        {"version": "2.17", "children": [
          {"id": "CmpA", "name": "Card", "type": "frame", "reusable": true, "children": [
            {"id": "TA", "type": "text", "content": "a"},
            {"id": "AinB", "type": "ref", "ref": "CmpB"}
          ]},
          {"id": "CmpB", "name": "Badge", "type": "frame", "reusable": true, "children": [
            {"id": "TB", "type": "text", "content": "b"},
            {"id": "BinA", "type": "ref", "ref": "CmpA"}
          ]},
          {"id": "CmpS", "name": "Row", "type": "frame", "reusable": true, "children": [
            {"id": "TS", "type": "text", "content": "s"},
            {"id": "SS", "type": "ref", "ref": "CmpS"}
          ]},
          {"id": "CmpD", "name": "Dock", "type": "frame", "reusable": true, "children": [
            {"id": "DB", "type": "ref", "ref": "CmpB"}
          ]},
          {"id": "Page", "type": "frame", "children": [
            {"id": "IA", "type": "ref", "ref": "CmpA"},
            {"id": "ID", "type": "ref", "ref": "CmpD"}
          ]}
        ]}
        """#)
    }

    /// Every node of a tree by id.
    private static func index(_ nodes: [PenNode]) -> [String: PenNode] {
        var result: [String: PenNode] = [:]
        var pending = nodes
        while let node = pending.popLast() {
            result[node.id] = node
            pending += node.kind.inlineChildren
        }
        return result
    }

    /// Whether a node is a `ref` still, unexpanded.
    private static func isRef(_ node: PenNode?) -> Bool {
        if case .ref? = node?.kind { true } else { false }
    }

    // MARK: - Reporting

    @Test("The document reports each loop, its cycle in render order from the lowest id, with display names")
    func reportsLoops() throws {
        let document = try EditableDocument(from: Self.loopy())
        let loops = document.componentLoops
        #expect(loops.map(\.ids) == [["CmpA", "CmpB"], ["CmpS"]])
        #expect(loops.map(\.description) == ["Card → Badge → Card", "Row → Row"])
        #expect(loops.first?.members.map(\.name) == ["Card", "Badge"])
    }

    @Test("A file read through a transaction records its loops on the read context")
    func readerRecordsLoops() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("loops-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("looped.pen")
        let data = try JSONEncoder().encode(Self.loopy())
        try data.write(to: url)

        let loops = try await PenFileTransaction.read(at: url) { document in
            document.readContext.componentLoops
        }.value
        #expect(loops.map(\.ids) == [["CmpA", "CmpB"], ["CmpS"]])
        #expect(loops.first?.members.map(\.name) == ["Card", "Badge"])
    }

    @Test("A document without loops reports none")
    func reportsNoLoops() {
        let document = EditableDocument(from: PenDocument(children: []))
        #expect(document.componentLoops.isEmpty)
    }

    // MARK: - Expansion

    @Test("An instance of a loop member does not expand another member inside it; one from outside expands once")
    func expansionIgnoresLoopNesting() throws {
        let expanded = try Self.index(PenRefExpander.expand(Self.loopy()).children)
        #expect(expanded["IA/TA"] != nil)
        #expect(Self.isRef(expanded["IA/AinB"]), "Badge inside Card closes the loop")
        #expect(expanded["IA/AinB/TB"] == nil)
        #expect(expanded["ID/DB/TB"] != nil, "Dock is outside the loop, so its Badge expands")
        #expect(Self.isRef(expanded["ID/DB/BinA"]), "and Card inside that Badge does not")
    }

    @Test("The editing layer's expansion of one instance matches")
    func editingExpansionMatches() throws {
        let document = try EditableDocument(from: Self.loopy())
        let expanded = try Self.index([document.expandRef(nodeID: "IA").expandedNode])
        #expect(Self.isRef(expanded["IA/AinB"]))
        #expect(expanded["IA/AinB/TB"] == nil)
    }

    /// `C0 … C(n-1)` each hold instances of the next two, wrapping round: one loop full
    /// of diamonds, which the old rule expanded along every path.
    static func chain(_ count: Int) -> PenDocument {
        func frame(_ id: String, reusable: Bool, _ children: [PenNode]) -> PenNode {
            PenNode(id: id, common: PenNodeCommon(name: id, reusable: reusable ? true : nil), kind: .frame(PenNode.FrameData(children: children)))
        }
        func ref(_ id: String, to target: String) -> PenNode {
            PenNode(id: id, common: PenNodeCommon(name: id), kind: .ref(PenNode.RefData(ref: target)))
        }
        func text(_ id: String) -> PenNode {
            PenNode(id: id, common: PenNodeCommon(name: id), kind: .text(PenNode.TextData(content: .literal(id))))
        }
        var roots: [PenNode] = (0 ..< count).map { index in
            frame("C\(index)", reusable: true, [
                text("C\(index)t"),
                ref("C\(index)n1", to: "C\((index + 1) % count)"),
                ref("C\(index)n2", to: "C\((index + 2) % count)"),
            ])
        }
        roots.append(frame("Page", reusable: false, (0 ..< count).map { ref("P\($0)", to: "C\($0)") }))
        return PenDocument(children: roots)
    }

    @Test("A loop of tangled components expands each instance to its own component alone")
    func tangledLoopExpandsOnce() {
        let expanded = PenRefExpander.expand(Self.chain(26))
        let page = expanded.children.first { $0.id == "Page" }
        #expect(Self.index(page.map { [$0] } ?? []).count == 1 + 26 * 4)
    }

    // MARK: - Mirrors

    @Test("Override keys stop where the expansion does")
    func overrideKeysMirror() throws {
        let document = try EditableDocument(from: Self.loopy())
        #expect(document.overridableDescendantKeys(ofInstance: "IA") == ["CmpA", "TA", "AinB"])
        #expect(document.overridableDescendantKeys(ofInstance: "ID").contains("DB/BinA"))
        #expect(!document.overridableDescendantKeys(ofInstance: "ID").contains("DB/BinA/TA"))
    }

    @Test("Pen's key resolver stops where the expansion does")
    func keyResolverMirrors() throws {
        let registry = try PenRefExpander.buildRegistry(from: Self.loopy().children)
        let resolver = try PenOverrideKeyResolver(component: #require(registry["CmpA"]), registry: registry)
        #expect(resolver.target(of: "AinB") != nil)
        #expect(resolver.target(of: "AinB/TB") == nil)
    }

    @Test("An instance chain through a loop-closing ref places no component")
    func chainThroughLoopPlacesNothing() throws {
        let document = try EditableDocument(from: Self.loopy())
        #expect(document.componentRoot(ofInstanceChain: ["IA", "AinB"]) == nil)
        #expect(document.componentRoot(ofInstanceChain: ["ID", "DB"]) == "CmpB")
        #expect(document.componentPlacement(of: PenNode.RefData(ref: "CmpB"), onChain: ["CmpA"]) == nil)
    }

    @Test("The expanded tree's rows stop where the expansion does")
    func treeRowsMirror() throws {
        let document = try EditableDocument(from: Self.loopy())
        let rows = try TreeView.rows(of: document, root: "IA", expandInstances: true)
        #expect(rows.contains { $0.id == "IA/AinB" })
        #expect(!rows.contains { $0.id.hasPrefix("IA/AinB/") })
    }
}
