//
//  RandomEditGenerator+Refs.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// The CRDT set's component-instance operations: descendant overrides and detaches.
extension RandomEditGenerator {
    /// Overrides the name, opacity or both of one descendant of a random `ref` — an
    /// already-overridden one, or the base component's `btnL` or `btnI`.
    mutating func overrideDescendant(in doc: EditableDocument, nodeIDs: [String], label: String, index: Int) -> EditOperation? {
        guard let refID = refs(in: doc, among: nodeIDs).randomElement(using: &rng) else { return nil }
        guard case let .ref(refData) = doc.nodes[refID]?.kind else { return nil }

        let descendantCandidates = ((refData.descendants?.keys).map { $0.sorted() } ?? []) + ["btnL", "btnI"]
        let descendantID = descendantCandidates.randomElement(using: &rng) ?? "btnL"

        // Name and opacity, to contend over the same ref's keys.
        var properties: [String: AnyCodable] = [:]
        switch Int.random(in: 0 ..< 3, using: &rng) {
        case 0:
            properties["name"] = .string("Fuzz_\(label)_\(index)")
        case 1:
            properties["opacity"] = .double(Double.random(in: 0 ... 1, using: &rng))
        default:
            properties["name"] = .string("Fuzz_\(label)_\(index)")
            properties["opacity"] = .double(Double.random(in: 0 ... 1, using: &rng))
        }
        return .overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: refID,
            descendantID: descendantID,
            properties: properties
        ))
    }

    /// Detaches a random `ref` into independent nodes.
    mutating func detachRef(in doc: EditableDocument, nodeIDs: [String]) -> EditOperation? {
        guard let refID = refs(in: doc, among: nodeIDs).randomElement(using: &rng) else { return nil }
        return .detachRef(EditOperation.DetachRef(refNodeID: refID))
    }
}
