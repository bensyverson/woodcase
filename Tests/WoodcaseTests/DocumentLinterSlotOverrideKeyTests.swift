//
//  DocumentLinterSlotOverrideKeyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `override-target-not-found` judges a key by the rule Pen applies it by.
///
/// Every key in `slot-override-keys.pen` that Pen keeps on re-save names a node Pen
/// draws the override on, so lint must accept it; every key Pen drops names nothing,
/// so lint must report it — the same answer ``PenRefExpander`` acts on.
@MainActor
struct DocumentLinterSlotOverrideKeyTests {
    @Test("Lint reports exactly the instances whose keys Pen drops")
    func findingsAreThePenDroppedKeys() throws {
        let url = SlotOverrideKeysSnapshotTests.fixturesDir
            .appendingPathComponent("\(SlotOverrideKeysSnapshotTests.fixture).pen")
        let parsed = try PenParser.parse(Data(contentsOf: url))
        var instanceOf: [String: String] = [:]
        for artboard in parsed.children {
            if let name = artboard.common.name, let instance = artboard.kind.inlineChildren.first {
                instanceOf[name] = instance.id
            }
        }
        let dropped = try PenOverrideKeyResolverTests.cases().filter(\.saved.isEmpty)
        let expected = Set(dropped.compactMap { instanceOf[$0.artboard] })

        let findings = try DocumentLinter.findings(in: EditableDocument(from: parsed))
        let reported = findings.filter { $0.check == .overrideTargetNotFound }

        #expect(expected.count == 4)
        #expect(Set(reported.compactMap(\.nodeID)) == expected, "\(LintFormatter.text(reported))")
        #expect(reported.count == expected.count)
    }
}
