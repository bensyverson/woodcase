//
//  InspectionFixture.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The documents the inspector queries are tested against.
///
/// `addressing-nested-instance.pen` holds `Card1`, an instance of `CardC` whose `Row`
/// group nests `Btn02`, an instance of `BtnC`; `Card1` overrides `Ttl03` and
/// `Btn02/Lbl02`. `slot-fill.pen` holds `Inst0`, which writes `Note0` and `Tag00` into
/// its card's slot. `planner.pen` is the planner's own fixture, with a variable of
/// every type and the themed color `ink`.
enum InspectionFixture {
    /// The fixture with a nested instance below a container.
    static let nested = "addressing-nested-instance.pen"

    /// The fixture whose instance fills a slot.
    static let slotFill = "slot-fill.pen"

    /// Every fixture whose expanded ids must all map back.
    static let roundTrip = [
        "addressing.pen", nested, "addressing-ref-chain.pen", slotFill, "planner.pen", "instances.pen",
    ]

    /// A fresh copy of a fixture from `Fixtures/`.
    static func document(_ name: String) throws -> EditableDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    /// `imports/app.pen` with `kit.lib.pen` read as its library.
    static func libraryDocument() throws -> EditableDocument {
        let (app, kit) = try PenImportedExpansionTests.fixture()
        let document = EditableDocument(from: app)
        document.readContext = PenReadContext(libraries: PenLibraries(documents: ["kit.lib.pen": kit]))
        return document
    }

    /// Every node id in a forest, depth first.
    static func ids(in nodes: [PenNode]) -> [String] {
        nodes.flatMap { [$0.id] + ids(in: $0.kind.inlineChildrenIfPresent ?? []) }
    }

    /// Plans an intent and applies what it plans.
    static func write(_ intent: EditIntent, at target: ResolvedNodeAddress, in document: EditableDocument) throws {
        for operation in try EditPlanner.plan(intent, at: target, in: document).operations {
            try document.apply(operation)
        }
    }
}
