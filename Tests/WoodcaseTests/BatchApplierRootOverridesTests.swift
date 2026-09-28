//
//  BatchApplierRootOverridesTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A `ref` writes its root overrides as top-level keys, so the decoder sweeps every
/// non-reserved key into `rootOverrides`. A caller who writes a literal
/// `"rootOverrides"` key therefore gets an override *named* `rootOverrides`, patching a
/// property no node has: it applies, it reads back, and it does nothing. Refused
/// instead, with the two forms that work.
@MainActor
@Suite("a literal rootOverrides key in a ref subtree")
struct BatchApplierRootOverridesTests {
    /// A document holding one reusable component, `cmp01`.
    private func document() -> EditableDocument {
        var common = PenNodeCommon(name: "Chip")
        common.reusable = true
        return EditableDocument(from: PenDocument(children: [
            PenNode(id: "cmp01", common: common, kind: .frame(PenNode.FrameData())),
        ]))
    }

    /// A ref node whose root overrides carry the given keys.
    private func instance(id: String, overrides: [String: AnyCodable]) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: "Chip \(id)"),
            kind: .ref(PenNode.RefData(ref: "cmp01", rootOverrides: overrides))
        )
    }

    // MARK: - add

    @Test("An add carrying a literal rootOverrides key is refused")
    func addIsRefused() {
        let node = instance(id: "ref01", overrides: ["rootOverrides": AnyCodable.dictionary(["width": .int(80)])])
        let report = BatchApplier.apply(
            [.add(BatchOperation.AddOp(node: node))], to: document()
        )

        #expect(report.lines[0].status == .failed)
        let error = report.lines[0].error ?? ""
        #expect(error.contains("rootOverrides"))
        #expect(error.contains("kind.rootOverrides"))
    }

    @Test("The refusal names the node it found the key on")
    func refusalNamesTheNode() {
        let node = PenNode(
            id: "out01",
            common: PenNodeCommon(name: "Outer"),
            kind: .frame(PenNode.FrameData(children: [
                instance(id: "ref01", overrides: ["rootOverrides": AnyCodable.dictionary(["width": .int(80)])]),
            ]))
        )
        let report = BatchApplier.apply(
            [.add(BatchOperation.AddOp(node: node))], to: document()
        )

        #expect(report.lines[0].status == .failed)
        #expect(report.lines[0].error?.contains("Outer/Chip ref01") == true)
    }

    @Test("An add whose overrides are ordinary inlined keys still applies")
    func ordinaryOverridesApply() {
        let document = document()
        let node = instance(id: "ref01", overrides: ["width": AnyCodable.int(80)])
        let report = BatchApplier.apply([.add(BatchOperation.AddOp(node: node))], to: document)

        #expect(report.lines[0].status == .applied)
        guard case let .ref(data)? = document.nodes["ref01"]?.kind else {
            Issue.record("no ref node")
            return
        }
        #expect(data.rootOverrides?["width"] == AnyCodable.int(80))
    }

    // MARK: - replace

    @Test("A replace carrying a literal rootOverrides key is refused")
    func replaceIsRefused() throws {
        let document = document()
        let clean = instance(id: "ref01", overrides: ["width": AnyCodable.int(80)])
        try document.apply(.insertNode(EditOperation.InsertNode(node: clean)))

        let report = try BatchApplier.apply([
            .replace(BatchOperation.ReplaceOp(
                target: #require(NodeAddress("ref01")),
                node: instance(id: "ref01", overrides: ["rootOverrides": AnyCodable.dictionary(["width": .int(80)])])
            )),
        ], to: document)

        #expect(report.lines[0].status == .failed)
        #expect(report.lines[0].error?.contains("rootOverrides") == true)
    }
}
