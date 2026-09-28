//
//  IncrementalSettleEquivalenceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Proves that a settle which reuses an earlier one answers exactly what a settle from
/// nothing does, over every fixture and a spread of writes.
///
/// A reused root is only as good as the rule that said it could not have moved, and a
/// wrong rule shows up nowhere but here: a stale rect in a script's `doc.tree()` is the
/// one failure a script cannot see. So for each fixture and each representative write —
/// move a node to another root, nudge one, edit a text, edit a component definition,
/// override an instance, edit a variable, add a root, delete one — the document is
/// settled, written, settled again reusing the first, and compared against a whole
/// ``SettledTree`` of the written document: every parent-relative rect, every
/// document-space rect, every resolved node, and every row `doc.tree()` would return
/// with instances expanded.
/// The comparison is exact.
///
/// Text is measured by a deterministic stand-in: the question is which nodes each side
/// laid out, not what Core Text answers.
@MainActor
struct IncrementalSettleEquivalenceTests {
    /// One representative write.
    enum Write: String, CaseIterable {
        case moveToAnotherRoot, nudge, editText, editDefinition, overrideInstance
        case editVariable, addRoot, deleteRoot
    }

    /// What the comparisons covered, so a corpus that stopped exercising reuse fails
    /// rather than passing vacuously.
    struct Coverage {
        var documents = 0
        var comparisons: [Write: Int] = [:]
        /// Settles that laid out some roots and reused others.
        var partial = 0
        /// Settles that reused every root.
        var reusedAll = 0
    }

    @Test("every write to every fixture settles to exactly what a settle from nothing gives")
    func everyFixture() throws {
        var coverage = Coverage()
        for url in try Self.fixtureURLs() {
            guard let parsed = try? PenParser.parse(Data(contentsOf: url)) else { continue }
            coverage.documents += 1
            for write in Write.allCases {
                try compare(write, parsed, at: url, coverage: &coverage)
            }
        }

        #expect(coverage.documents > 100, "Only \(coverage.documents) fixtures parsed.")
        for write in Write.allCases {
            #expect(coverage.comparisons[write, default: 0] > 10, "\(write) was compared too rarely.")
        }
        #expect(coverage.partial > 100, "Too few settles reused some roots and laid out others.")
    }

    // MARK: - One comparison

    /// Settles, writes, settles again reusing the first, and compares with a fresh settle.
    private func compare(
        _ write: Write, _ parsed: PenDocument, at url: URL, coverage: inout Coverage
    ) throws {
        let document = PenFileTransaction.editableDocument(from: parsed, at: url, fonts: nil)
        let sizes = TextSizeCache(measuring: SettledTreeReuseTests.measurer, fontGeneration: { 0 })
        let before = SettledTree(document: document, theme: [:], textSizes: sizes, reusing: nil)
        guard (try? apply(write, to: document)) == true else { return }

        let after = SettledTree(document: document, theme: [:], textSizes: sizes, reusing: before)
        let fresh = SettledTree(document: document, theme: [:], textMeasurer: SettledTreeReuseTests.measurer)
        let label = "\(url.lastPathComponent) after \(write)"
        #expect(after.rects == fresh.rects, "\(label): rects differ")
        #expect(after.absoluteRects == fresh.absoluteRects, "\(label): absolute rects differ")
        #expect(after.nodes == fresh.nodes, "\(label): resolved nodes differ")
        let rows = try TreeView.rows(of: document, settled: after, expandInstances: true)
        let freshRows = try TreeView.rows(of: document, settled: fresh, expandInstances: true)
        #expect(rows == freshRows, "\(label): tree rows differ")

        coverage.comparisons[write, default: 0] += 1
        if let laidOut = after.ledger?.laidOut {
            let roots = document.rootOrder.count(where: { document.nodes[$0] != nil })
            if laidOut.isEmpty { coverage.reusedAll += 1 } else if laidOut.count < roots { coverage.partial += 1 }
        }
    }

    // MARK: - The writes

    /// Applies one write, when the document has something it applies to.
    ///
    /// - Returns: `true` when the document was written.
    private func apply(_ write: Write, to document: EditableDocument) throws -> Bool {
        let order = Self.documentOrder(of: document)
        let placed = order.filter { !Self.isInsideDefinition($0, in: document) }
        switch write {
        case .moveToAnotherRoot:
            guard let node = order.first(where: { document.parents[$0] != nil }),
                  let from = Self.root(of: node, in: document),
                  let target = document.rootOrder.first(where: { id in
                      guard id != from, case .frame = document.nodes[id]?.kind else { return false }
                      return true
                  })
            else { return false }
            try document.apply(.moveNode(EditOperation.MoveNode(nodeID: node, newParentID: target)))
        case .nudge:
            guard let node = order.first(where: { document.parents[$0] != nil }) else { return false }
            let x = document.nodes[node]?.common.x?.literalValue ?? 0
            try setProperty("common.x", .double(x + 7), on: node, in: document)
        case .editText:
            guard let text = placed.first(where: { Self.isText($0, in: document) }) else { return false }
            try setProperty("kind.content", .string("An edited text, long enough to wrap"), on: text, in: document)
        case .editDefinition:
            guard let text = order.first(where: {
                Self.isText($0, in: document) && Self.isInsideDefinition($0, in: document)
            }) else { return false }
            try setProperty("kind.content", .string("An edited definition text"), on: text, in: document)
        case .overrideInstance:
            return try overrideInstance(in: document, placed: placed)
        case .editVariable:
            return try editVariable(in: document)
        case .addRoot:
            try document.apply(.insertNode(EditOperation.InsertNode(node: PenNode(
                id: "Add01",
                common: PenNodeCommon(name: "Added", x: .literal(5000), y: .literal(0)),
                kind: .frame(PenNode.FrameData(
                    width: .fitContent(fallback: nil), height: .fitContent(fallback: nil), layout: .vertical,
                    children: [PenNode(
                        id: "AddT1",
                        common: PenNodeCommon(name: "Added text"),
                        kind: .text(PenNode.TextData(content: .literal("Added text")))
                    )]
                ))
            ))))
        case .deleteRoot:
            guard let root = document.rootOrder.last(where: { document.nodes[$0]?.common.reusable != true })
            else { return false }
            try document.apply(.deleteNode(EditOperation.DeleteNode(nodeID: root)))
        }
        return true
    }

    /// Overrides the first text an instance on the canvas draws.
    private func overrideInstance(in document: EditableDocument, placed: [String]) throws -> Bool {
        for id in placed {
            guard case let .ref(data) = document.nodes[id]?.kind else { continue }
            let drawn = Self.subtree(of: data.ref, in: document)
            guard let text = drawn.first(where: { Self.isText($0, in: document) }) else { continue }
            try document.apply(.overrideDescendant(EditOperation.OverrideDescendant(
                refNodeID: id, descendantID: text, properties: ["content": .string("Overridden text")]
            )))
            return true
        }
        return false
    }

    /// Changes the first variable's value, or adds one to a document without any.
    private func editVariable(in document: EditableDocument) throws -> Bool {
        guard let (name, variable) = document.variables?.min(by: { $0.key < $1.key }) else {
            try document.apply(.addVariable(EditOperation.AddVariable(
                name: "added", variable: PenVariable(type: .number, value: .simple(.int(4)))
            )))
            return true
        }
        var changed = variable
        switch (variable.type, variable.value) {
        case let (.number, .simple(.int(value))): changed.value = .simple(.int(value + 9))
        case let (.number, .simple(.double(value))): changed.value = .simple(.double(value + 9))
        case (.color, _): changed.value = .simple(.string("#123456"))
        case (.string, _): changed.value = .simple(.string("A changed string value"))
        default: changed.value = .simple(.int(12))
            changed.type = .number
        }
        try document.apply(.updateVariable(EditOperation.UpdateVariable(name: name, variable: changed)))
        return true
    }

    private func setProperty(
        _ path: String, _ value: AnyCodable, on node: String, in document: EditableDocument
    ) throws {
        try document.apply(.setProperties(EditOperation.SetProperties(nodeID: node, properties: [path: value])))
    }

    // MARK: - Reading the flat store

    /// Every node, in document order, from a work list.
    private static func documentOrder(of document: EditableDocument) -> [String] {
        subtrees(of: document.rootOrder, in: document)
    }

    /// A node and everything under it, in pre-order.
    private static func subtree(of id: String, in document: EditableDocument) -> [String] {
        subtrees(of: [id], in: document)
    }

    private static func subtrees(of roots: [String], in document: EditableDocument) -> [String] {
        var order: [String] = []
        var pending = Array(roots.reversed())
        while let id = pending.popLast() {
            guard document.nodes[id] != nil else { continue }
            order.append(id)
            pending.append(contentsOf: (document.children[id] ?? []).reversed())
        }
        return order
    }

    private static func root(of id: String, in document: EditableDocument) -> String? {
        var current = id
        while let parent = document.parents[current] {
            current = parent
        }
        return document.nodes[current] == nil ? nil : current
    }

    private static func isText(_ id: String, in document: EditableDocument) -> Bool {
        if case .text = document.nodes[id]?.kind { return true }
        return false
    }

    private static func isInsideDefinition(_ id: String, in document: EditableDocument) -> Bool {
        var current: String? = id
        while let node = current {
            if document.nodes[node]?.common.reusable == true { return true }
            current = document.parents[node]
        }
        return false
    }

    /// Every `.pen` file under the bundled fixtures, in a stable order.
    private static func fixtureURLs() throws -> [URL] {
        let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        let urls = (walk?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "pen" }
        return urls.sorted { $0.path < $1.path }
    }
}
