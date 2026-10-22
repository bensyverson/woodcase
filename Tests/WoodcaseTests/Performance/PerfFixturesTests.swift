//
//  PerfFixturesTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase
import WoodcasePerfFixtures

/// Holds the fixtures the budgets and `WoodcaseBench` share to what both rely on: the
/// files are where ``PerfFixtureFile`` says, and the generated deep trees keep their
/// shape.
struct PerfFixturesTests {
    @Test("Every fixture file is in the source tree and parses", arguments: PerfFixtureFile.allCases)
    func fileParses(file: PerfFixtureFile) throws {
        #expect(FileManager.default.fileExists(atPath: file.url.path))
        let document = try PenParser.parse(contentsOf: file.url)
        #expect(!document.children.isEmpty)
    }

    @Test("The mockup-shaped tree is wraps + 8 deep, with every id unique")
    func mockupShapedKeepsItsShape() throws {
        let tree = try DeepDocuments.mockupShaped(wraps: 3)
        #expect(DeepDocuments.depth(of: tree) == 3 + 8)
        var ids: [String] = []
        var pending = [tree]
        while let node = pending.popLast() {
            ids.append(node.id)
            pending.append(contentsOf: node.kind.inlineChildren)
        }
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains { $0.hasPrefix("w2-") })
    }
}
