//
//  NaturalPathFixture.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `natural-paths.pen`: a card whose stroke is dashed, mitered, locked and blended, a styled
/// default text, a line, a plain rectangle, and a `Badge` component (dashed, with a dashed
/// `Box` child) drawn once by the instance `Inst`.
enum NaturalPathFixture {
    /// The fixture is missing from the test bundle.
    struct Missing: Error {}

    /// A fresh copy of the fixture.
    static func document() throws -> EditableDocument {
        guard let url = Bundle.module.url(forResource: "natural-paths", withExtension: "pen", subdirectory: "Fixtures") else {
            throw Missing()
        }
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    /// One node of a fresh copy.
    static func node(_ id: String) throws -> PenNode {
        try #require(document().node(id: id))
    }

    /// Applies a plan's operations in order.
    static func apply(_ plan: EditPlan, to document: EditableDocument) throws {
        for operation in plan.operations {
            try document.apply(operation)
        }
    }

    /// The node an expansion of the document draws under an id.
    static func expanded(_ id: String, in document: EditableDocument) -> PenNode? {
        find(id, in: PenRefExpander.expand(document.materialize()).children)
    }

    private static func find(_ id: String, in nodes: [PenNode]) -> PenNode? {
        for node in nodes {
            if node.id == id { return node }
            let children: [PenNode] = switch node.kind {
            case let .frame(data): data.children ?? []
            case let .group(data): data.children ?? []
            default: []
            }
            if let found = find(id, in: children) { return found }
        }
        return nil
    }
}
