//
//  PlannerFixture.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// A small document for the edit planner's tests.
///
/// `Board` is a free frame (`layout: none`) holding `Free`, an instance `Chip` of
/// `Component`, and `Row`, a horizontal stack holding `Flow` (in flow) and `Pinned`
/// (absolutely positioned). `Component` is a horizontal stack whose `Label` is in flow.
/// The variables cover each type, and one is themed.
enum PlannerFixture {
    /// The fixture file, `Fixtures/planner.pen`, which the CLI's parity tests copy too.
    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/planner.pen")
    }

    /// A fresh copy of the fixture.
    static func document() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    /// Parses an address the test knows is well formed.
    static func address(_ raw: String) -> NodeAddress {
        NodeAddress(raw)!
    }

    /// The refusal a plan throws, or `nil` if it plans.
    static func refusal(
        _ intent: EditIntent,
        at raw: String,
        in document: EditableDocument
    ) -> EditRefusal? {
        do {
            _ = try EditPlanner.plan(intent, at: address(raw), in: document)
            return nil
        } catch {
            return error
        }
    }
}
