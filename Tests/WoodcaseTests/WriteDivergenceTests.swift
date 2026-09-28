//
//  WriteDivergenceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The divergence echo: what a write reports when what it stored is not what it was
/// handed.
@MainActor
struct WriteDivergenceTests {
    // MARK: - Documents

    private func makeDocument() throws -> EditableDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/batch.pen")
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    private func makeVariableDocument() throws -> EditableDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/content-variable.pen")
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    // MARK: - Agreement

    @Test("A write that stored what it was handed reports no divergence")
    func agreementIsQuiet() throws {
        let document = try makeDocument()
        let title = try #require(NodeAddress("Canvas/Title"))

        let result = try BatchApplier.applyOne(
            .set(BatchOperation.SetOp(target: title, props: ["kind.content": .string("Hi")])),
            to: document
        )

        #expect(result.divergences.isEmpty)
    }

    @Test("An applied line carries the id and the post-state node")
    func carriesThePostStateNode() throws {
        let document = try makeDocument()
        let title = try #require(NodeAddress("Canvas/Title"))

        let result = try BatchApplier.applyOne(
            .set(BatchOperation.SetOp(target: title, props: ["kind.content": .string("Hi")])),
            to: document
        )

        #expect(result.id == "Ttl01")
        let node = try #require(result.node)
        guard case let .text(data) = node.kind else {
            Issue.record("expected a text node")
            return
        }
        #expect(data.content == .literal("Hi"))
    }

    @Test("A removed node's line carries its id but no node — it is gone")
    func aRemovedNodeHasNoPostState() throws {
        let document = try makeDocument()
        let first = try #require(NodeAddress("Canvas/Cards/First"))

        let result = try BatchApplier.applyOne(
            .rm(BatchOperation.RemoveOp(target: first)),
            to: document
        )

        #expect(result.id == "Cd101")
        #expect(result.node == nil)
    }

    // MARK: - A value resolved

    @Test("A $name written to a text property is reported as the reference it becomes")
    func resolvedVariableReference() throws {
        let document = try makeVariableDocument()
        let title = try #require(NodeAddress("Title"))

        let result = try BatchApplier.applyOne(
            .set(BatchOperation.SetOp(target: title, props: ["kind.content": .string("$v-muted")])),
            to: document
        )

        let divergence = try #require(result.divergences.first)
        #expect(divergence.kind == .variableReference)
        #expect(divergence.target == "kind.content")
        #expect(divergence.requested == "$v-muted")
        #expect(divergence.applied == "the color variable v-muted")
        #expect(divergence.note == """
        kind.content resolved $v-muted as a reference to the color variable v-muted \
        — write \\$v-muted for the literal
        """)
    }

    @Test("An escaped $name is a literal and reports nothing")
    func escapedNameIsQuiet() throws {
        let document = try makeVariableDocument()
        let title = try #require(NodeAddress("Title"))

        let result = try BatchApplier.applyOne(
            .set(BatchOperation.SetOp(target: title, props: ["kind.content": .string("\\$v-muted")])),
            to: document
        )

        #expect(result.divergences.isEmpty)
    }

    @Test("A $name no variable defines reports nothing — there is nothing to resolve to")
    func undefinedNameIsQuiet() throws {
        let document = try makeVariableDocument()
        let title = try #require(NodeAddress("Title"))

        let result = try BatchApplier.applyOne(
            .set(BatchOperation.SetOp(target: title, props: ["kind.content": .string("$nobody")])),
            to: document
        )

        #expect(result.divergences.isEmpty)
    }

    // MARK: - A value coerced

    @Test("A number stored as the text it spells is reported as the coercion it is")
    func coercedNumber() throws {
        let document = try makeDocument()
        let title = try #require(NodeAddress("Canvas/Title"))

        let result = try BatchApplier.applyOne(
            .set(BatchOperation.SetOp(target: title, props: ["kind.content": .int(3)])),
            to: document
        )

        let divergence = try #require(result.divergences.first)
        #expect(divergence.kind == .coercion)
        #expect(divergence.target == "kind.content")
        #expect(divergence.requested == "3")
        #expect(divergence.applied == "\"3\"")
        #expect(divergence.note == """
        kind.content stored the number 3 as the text "3" — the property takes text, \
        not a number
        """)
    }

    // MARK: - An override of a property nothing sets

    @Test("An override of a property the definition sets reports nothing")
    func overrideOfASetPropertyIsQuiet() throws {
        let document = try makeDocument()
        let label = try #require(NodeAddress("Board/Chip/Label"))

        let result = try BatchApplier.applyOne(
            .override(BatchOperation.OverrideOp(target: label, props: ["content": .string("Hi")])),
            to: document
        )

        #expect(result.divergences.isEmpty)
    }

    @Test("An override of a property the definition leaves unset notes that it adds one")
    func overrideOfAnUnsetProperty() throws {
        let document = try makeDocument()
        let label = try #require(NodeAddress("Board/Chip/Label"))

        let result = try BatchApplier.applyOne(
            .override(BatchOperation.OverrideOp(target: label, props: ["fontSize": .int(18)])),
            to: document
        )

        let divergence = try #require(result.divergences.first)
        #expect(divergence.kind == .unsetOverrideProperty)
        #expect(divergence.severity == .note)
        #expect(divergence.target == "fontSize")
        #expect(divergence.note == """
        Board/Chip/Label adds fontSize rather than replacing it — Component does not \
        set fontSize, which is how an instance varies from its component
        """)
    }

    @Test("An override of a property the node type has no room for says it will not be read")
    func overrideOfAnAbsentProperty() throws {
        let document = try makeDocument()
        let label = try #require(NodeAddress("Board/Chip/Label"))

        let result = try BatchApplier.applyOne(
            .override(BatchOperation.OverrideOp(target: label, props: ["layout": .string("horizontal")])),
            to: document
        )

        let divergence = try #require(result.divergences.first)
        #expect(divergence.kind == .unsetOverrideProperty)
        #expect(divergence.note == """
        Board/Chip/Label is a text node and has no layout — the override is stored \
        but nothing will read it
        """)
    }

    @Test("An override carrying a type key replaces the whole node, and says so")
    func overrideThatReplacesTheNode() throws {
        let document = try makeDocument()
        let label = try #require(NodeAddress("Board/Chip/Label"))

        let result = try BatchApplier.applyOne(
            .override(BatchOperation.OverrideOp(
                target: label, props: ["type": .string("rectangle")]
            )),
            to: document
        )

        let divergence = try #require(
            result.divergences.first { $0.kind == .overrideReplacesNode }
        )
        #expect(divergence.note == """
        Board/Chip/Label carries a type key, so the override replaces the whole node \
        rather than patching it — every property the replacement omits is dropped
        """)
    }

    // MARK: - Structural consequences

    @Test("A root-level add the applier had to place says where it put it")
    func rootPlacementIsReported() throws {
        let document = try makeDocument()
        let node = try PenSubtreeDecoder.node(from: [
            "type": "frame", "name": "Hero", "width": 10, "height": 10,
        ])

        let result = try BatchApplier.applyOne(
            .add(BatchOperation.AddOp(node: node)),
            to: document
        )

        let divergence = try #require(result.divergences.first)
        #expect(divergence.kind == .rootPlacement)
        #expect(divergence.requested == "no coordinates")
        #expect(divergence.applied == "x 800, y 0")
        #expect(divergence.note == """
        Hero was placed at x 800, y 0, clear of the artboards already there — write \
        common.x and common.y to choose
        """)
    }

    @Test("A root-level add that wrote its own coordinates is left alone, and is quiet")
    func authoredRootCoordinatesAreQuiet() throws {
        let document = try makeDocument()
        let node = try PenSubtreeDecoder.node(from: [
            "type": "frame", "name": "Hero", "x": 900, "y": 900, "width": 10, "height": 10,
        ])

        let result = try BatchApplier.applyOne(
            .add(BatchOperation.AddOp(node: node)),
            to: document
        )

        #expect(result.divergences.isEmpty)
    }

    @Test("A delete that detached instances first names them")
    func detachedInstancesAreReported() throws {
        let document = try makeDocument()
        let component = try #require(NodeAddress("Component"))

        let result = try BatchApplier.applyOne(
            .rm(BatchOperation.RemoveOp(target: component, detach: true)),
            to: document
        )

        let divergence = try #require(result.divergences.first)
        #expect(divergence.kind == .detachedInstances)
        #expect(divergence.note == """
        removing Component detached 1 instance of it into a standalone copy first: \
        Board/Chip
        """)
    }

    @Test("A delete that stranded nothing reports no detachment")
    func aPlainDeleteIsQuiet() throws {
        let document = try makeDocument()
        let first = try #require(NodeAddress("Canvas/Cards/First"))

        let result = try BatchApplier.applyOne(
            .rm(BatchOperation.RemoveOp(target: first, detach: true)),
            to: document
        )

        #expect(result.divergences.isEmpty)
    }

    // MARK: - Batches

    @Test("A batch reports each line's divergences on that line")
    func batchLinesCarryTheirOwn() throws {
        let document = try makeDocument()
        let title = try #require(NodeAddress("Canvas/Title"))
        let label = try #require(NodeAddress("Board/Chip/Label"))

        let report = BatchApplier.apply([
            .set(BatchOperation.SetOp(target: title, props: ["kind.content": .string("Hi")])),
            .set(BatchOperation.SetOp(target: title, props: ["kind.content": .int(7)])),
            .override(BatchOperation.OverrideOp(target: label, props: ["fontSize": .int(18)])),
        ], to: document)

        #expect(report.lines[0].divergences.isEmpty)
        #expect(report.lines[1].divergences.map(\.kind) == [.coercion])
        #expect(report.lines[2].divergences.map(\.kind) == [.unsetOverrideProperty])
    }

    @Test("A line that failed carries no divergences — nothing was applied to diverge")
    func aFailedLineIsQuiet() throws {
        let document = try makeDocument()
        let title = try #require(NodeAddress("Canvas/Title"))

        let report = BatchApplier.apply([
            .set(BatchOperation.SetOp(target: title, props: ["kind.nonsense": .int(3)])),
        ], to: document)

        #expect(report.lines[0].status == .failed)
        #expect(report.lines[0].divergences.isEmpty)
        #expect(report.lines[0].node == nil)
    }
}
