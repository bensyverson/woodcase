//
//  HypotheticalLayoutEquivalenceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Proves that a hypothetical layout equals the layout after committing the same edit,
/// over every fixture (leaf `UjnrLt`).
///
/// For each fixture and each kind of edit, a ``PenLayoutState`` is built, asked for the
/// hypothetical, and its change merged over its rects; the edit is then committed to the
/// document and the merge compared with ``LayoutOracle``'s full layout, bit for bit. The
/// state must come back unchanged, and the change must name exactly the rects that
/// differ. That is the handoff Penumbra relies on: a preview, then its commit, with no
/// flash between them.
@MainActor
struct HypotheticalLayoutEquivalenceTests {
    /// One kind of hypothetical edit.
    enum Edit: String, CaseIterable {
        case reorder, remove, resize, fill
    }

    @Test("every hypothetical edit to every fixture equals committing it", arguments: Edit.allCases)
    func everyFixture(edit: Edit) throws {
        var compared = 0
        for url in try FixtureFlatStore.fixtureURLs() {
            guard let parsed = try? PenParser.parse(Data(contentsOf: url)) else { continue }
            let document = PenFileTransaction.editableDocument(from: parsed, at: url, fonts: nil)
            if try compare(edit, in: document, label: url.lastPathComponent) { compared += 1 }
        }
        #expect(compared > 50, "\(edit) was compared on only \(compared) fixtures.")
    }

    /// Imagines one edit, commits it, and compares.
    ///
    /// - Returns: Whether the document had something the edit applies to.
    private func compare(_ edit: Edit, in document: EditableDocument, label: String) throws -> Bool {
        let measurer = SettledTreeReuseTests.measurer
        let state = PenLayoutState(
            document: PenVariableResolver.resolve(document.expandedDocument().0), textMeasurer: measurer
        )
        let placed = FixtureFlatStore.documentOrder(of: document).filter {
            !FixtureFlatStore.isInsideDefinition($0, in: document)
        }
        guard let (sourceEdit, operation) = Self.pick(edit, among: placed, in: document),
              let hypothetical = Self.expanded(sourceEdit, in: state.index)
        else { return false }

        let before = state.rects
        let change = state.hypothetical([hypothetical])
        #expect(state.rects == before, "\(label): the state changed")
        guard (try? document.apply(operation)) != nil else { return false }

        let preview = change.applied(to: before)
        let committed = LayoutOracle.fullLayout(of: document, textMeasurer: measurer)
        let differences = LayoutOracle.differences(preview, committed)
        #expect(differences.isEmpty, "\(label) \(edit): \(differences.joined(separator: "; "))")
        let differing = Set(before.keys).union(preview.keys).filter { before[$0] != preview[$0] }
        #expect(Set(change.rects.keys).union(change.removed) == differing, "\(label) \(edit): change names other ids")
        return true
    }

    /// The edit on the node's expanded id: its own, or its instance root for a `ref`.
    private static func expanded(_ edit: PenLayoutEdit, in index: PenLayoutIndex) -> PenLayoutEdit? {
        let source = edit.nodeID
        guard let id = index[source] != nil ? source : index.instanceRoots(of: source).first else { return nil }
        return switch edit {
        case .remove: .remove(id)
        case let .move(_, toIndex): .move(id, toIndex: toIndex)
        case let .size(_, width, height): .size(id, width: width, height: height)
        case let .sizing(_, width, height): .sizing(id, width: width, height: height)
        }
    }

    /// The hypothetical edit, by source id, and the operation that commits it, for the
    /// first node on the canvas it applies to.
    private static func pick(
        _ edit: Edit, among placed: [String], in document: EditableDocument
    ) -> (PenLayoutEdit, EditOperation)? {
        switch edit {
        case .reorder:
            guard let parent = placed.first(where: { (document.children[$0]?.count ?? 0) > 1 }),
                  let last = document.children[parent]?.last
            else { return nil }
            return (.move(last, toIndex: 0), .moveNode(EditOperation.MoveNode(nodeID: last, newParentID: parent, index: 0)))
        case .remove:
            guard let node = placed.last(where: { document.parents[$0] != nil }) else { return nil }
            return (.remove(node), .deleteNode(EditOperation.DeleteNode(nodeID: node)))
        case .resize:
            guard let node = placed.first(where: {
                document.parents[$0] != nil && (FixtureFlatStore.isFrame($0, in: document) || FixtureFlatStore.isText($0, in: document))
            }) else { return nil }
            return (
                .size(node, width: 173, height: 41),
                .setProperties(EditOperation.SetProperties(
                    nodeID: node, properties: ["kind.width": .int(173), "kind.height": .int(41)]
                ))
            )
        case .fill:
            guard let node = placed.first(where: {
                document.parents[$0] != nil && FixtureFlatStore.isFrame($0, in: document)
            }) else { return nil }
            return (
                .sizing(node, width: .fillContainer(fallback: nil), height: nil),
                .setProperties(EditOperation.SetProperties(nodeID: node, properties: ["kind.width": .string("fill_container")]))
            )
        }
    }
}
