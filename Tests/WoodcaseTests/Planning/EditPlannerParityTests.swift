//
//  EditPlannerParityTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The batch grammar's `set` and `override` lines plan through the public planner, so an
/// editor and the CLI produce the same edits for the same intent.
@MainActor
struct EditPlannerParityTests {
    private func batchOperations(_ operation: BatchOperation) throws -> [EditOperation] {
        try BatchApplier.plan(operation, in: PlannerFixture.document(), tags: [:]).operations
    }

    private func plannerOperations(_ intent: EditIntent, at raw: String) throws -> [EditOperation] {
        try EditPlanner.plan(intent, at: PlannerFixture.address(raw), in: PlannerFixture.document()).operations
    }

    @Test("A set line and the planner's set give the same edits on a plain node")
    func setOnNode() throws {
        let props: [String: AnyCodable] = ["common.opacity": 0.5, "codegen.role": "card"]
        let target = PlannerFixture.address("Board/Free")

        #expect(try batchOperations(.set(BatchOperation.SetOp(target: target, props: props)))
            == plannerOperations(.set(props), at: "Board/Free"))
    }

    @Test("A set line inside an instance fails with the planner's refusal")
    func setInsideInstance() throws {
        let document = try PlannerFixture.document()
        let target = PlannerFixture.address("Board/Chip/Label")
        let report = BatchApplier.apply(
            [.set(BatchOperation.SetOp(target: target, props: ["kind.content": "Go"]))], to: document
        )

        #expect(report.lines[0].status == .failed)
        #expect(report.lines[0].error
            == PlannerFixture.refusal(.set(["kind.content": "Go"]), at: "Board/Chip/Label", in: document)?.message)
    }

    @Test("An override line with unset gives the planner's override")
    func overrideWithUnset() throws {
        let target = PlannerFixture.address("Board/Chip/Label")
        let line = BatchOperation.OverrideOp(target: target, props: ["fill": "#FFFFFF"], unset: ["content"])

        #expect(try batchOperations(.override(line))
            == plannerOperations(.override(["fill": "#FFFFFF"], unset: ["content"]), at: "Board/Chip/Label"))
    }

    @Test("A batch line refuses what the planner refuses")
    func refusalsAgree() throws {
        let document = try PlannerFixture.document()
        let report = BatchApplier.apply(
            [.set(BatchOperation.SetOp(target: PlannerFixture.address("Board/Free"), props: ["common.opacity": 3]))],
            to: document
        )

        #expect(report.lines[0].status == .failed)
        #expect(report.lines[0].error
            == PlannerFixture.refusal(.set(["common.opacity": 3]), at: "Board/Free", in: document)?.message)
    }
}
