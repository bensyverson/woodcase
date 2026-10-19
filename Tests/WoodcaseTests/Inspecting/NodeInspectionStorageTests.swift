//
//  NodeInspectionStorageTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``NodeInspection/storage(of:)``: where a write of a property of the inspected node is
/// stored, so an inspector reads an override where one would be written — and the answer
/// agrees with where ``EditPlanner/plan(_:routedAt:in:)`` stores the write.
@MainActor
struct NodeInspectionStorageTests {
    private func inspection(_ target: ResolvedNodeAddress, in document: EditableDocument) throws -> NodeInspection {
        try #require(document.inspect(target))
    }

    @Test("A node with storage of its own stores every property itself")
    func ownStorage() throws {
        let document = try IntentRoutingTests.document()
        let plain = try inspection(.node(id: "Plain"), in: document)
        #expect(plain.storage(of: "kind.fills") == .node)
        #expect(plain.storage(of: "common.x") == .node)
    }

    @Test("An instance root stores its common properties on the ref node and the component root's as overrides")
    func instanceRoot() throws {
        let document = try IntentRoutingTests.document()
        let chip = try inspection(.node(id: "Chip"), in: document)
        #expect(chip.storage(of: "common.x") == .node)
        #expect(chip.storage(of: "common.metadata.woodcase.role") == .node)
        #expect(chip.storage(of: "kind.fills") == .instanceOverride)
    }

    @Test("A node inside an instance, and content the instance wrote into a slot, store everything as overrides")
    func insideInstance() throws {
        let document = try IntentRoutingTests.document()
        let label = try inspection(.instanceDescendant(refID: "Chip", descendantKey: "Label"), in: document)
        #expect(label.storage(of: "common.x") == .instanceOverride)
        #expect(label.storage(of: "kind.content") == .instanceOverride)
        let note = try inspection(.instanceDescendant(refID: "Filled", descendantKey: "Note"), in: document)
        #expect(note.storage(of: "kind.content") == .instanceOverride)
    }

    @Test("The storage an inspection reports is the storage the routed plan writes")
    func agreesWithThePlanner() throws {
        let document = try IntentRoutingTests.document()
        let targets: [ResolvedNodeAddress] = [
            .node(id: "Plain"), .node(id: "Chip"),
            .instanceDescendant(refID: "Chip", descendantKey: "Label"),
            .instanceDescendant(refID: "Filled", descendantKey: "Note"),
        ]
        let writes: [String: AnyCodable] = ["common.opacity": 0.5, "kind.fills": "#00FF00"]
        for target in targets {
            let inspection = try inspection(target, in: document)
            for (path, value) in writes {
                let plan = try EditPlanner.plan(.set([path: value]), routedAt: target, in: document)
                #expect(inspection.storage(of: path) == plan.storage, "\(target) \(path)")
            }
        }
    }
}
