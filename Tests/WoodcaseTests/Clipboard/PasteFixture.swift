//
//  PasteFixture.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// What the paste suites share: target documents, applying a plan, and drawing a node
/// with the reference renderer.
enum PasteFixture {
    /// A document with nothing in it.
    static func empty() -> EditableDocument {
        EditableDocument(from: PenDocument(version: "2.17", children: []))
    }

    /// A document parsed from .pen JSON.
    static func document(_ json: String) throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(Data(json.utf8)))
    }

    /// Applies a plan's operations in order, as a session would.
    static func apply(_ plan: PastePlan, to document: EditableDocument) throws {
        for operation in plan.operations {
            try document.apply(operation)
        }
    }

    /// The nodes a plan inserts, as written, keyed by id — the inline children of every
    /// inserted subtree included.
    static func inserted(_ plan: PastePlan) -> [String: PenNode] {
        PenClipFixture.index(plan.operations.compactMap { operation in
            guard case let .insertNode(insert) = operation else { return nil }
            return insert.node
        })
    }

    /// The insert operations of a plan, in order.
    static func inserts(_ plan: PastePlan) -> [EditOperation.InsertNode] {
        plan.operations.compactMap { operation in
            guard case let .insertNode(insert) = operation else { return nil }
            return insert
        }
    }

    /// The variables a plan adds, by name.
    static func addedVariables(_ plan: PastePlan) -> [String: PenVariable] {
        var added: [String: PenVariable] = [:]
        for operation in plan.operations {
            if case let .addVariable(add) = operation {
                added[add.name] = add.variable
            }
        }
        return added
    }

    /// The ids of a stored node's children, in order.
    static func childIDs(of id: String, in document: EditableDocument) throws -> [String] {
        try document.materializeSubtree(rootID: id).kind.inlineChildren.map(\.id)
    }

    /// Draws one stored node of a document at 2×, cropped to its rect.
    static func render(_ document: EditableDocument, nodeID: String) -> CGImage? {
        let resolved = PenVariableResolver.resolve(document.expanded(for: .canvas))
        let rects = PenLayoutEngine.layout(resolved)
        let expandedID = document.expandedID(of: .node(id: nodeID))
        guard let rect = rects[expandedID] else { return nil }
        return PenRenderer.render(
            resolved, layoutRects: rects, size: CGSize(width: rect.width, height: rect.height),
            scale: 2, rootNodeID: expandedID
        )
    }

    /// A transparent image the size of another, to show a render is not blank.
    static func blank(like image: CGImage) -> CGImage? {
        PenRenderer.render(
            PenDocument(version: "2.17", children: []), layoutRects: [:],
            size: CGSize(width: image.width / 2, height: image.height / 2), scale: 2
        )
    }
}
