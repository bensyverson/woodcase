//
//  FixtureFlatStore.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Reads an ``EditableDocument``'s flat store the way the fixture-wide equivalence tests
/// pick what to edit: document order, subtrees, roots and what kind a node is.
@MainActor
enum FixtureFlatStore {
    /// Every node, in document order, from a work list.
    static func documentOrder(of document: EditableDocument) -> [String] {
        subtrees(of: document.rootOrder, in: document)
    }

    /// A node and everything under it, in pre-order.
    static func subtree(of id: String, in document: EditableDocument) -> [String] {
        subtrees(of: [id], in: document)
    }

    /// Several subtrees, one after another, in pre-order.
    static func subtrees(of roots: [String], in document: EditableDocument) -> [String] {
        var order: [String] = []
        var pending = Array(roots.reversed())
        while let id = pending.popLast() {
            guard document.nodes[id] != nil else { continue }
            order.append(id)
            pending.append(contentsOf: (document.children[id] ?? []).reversed())
        }
        return order
    }

    /// The top-level node holding a node, or `nil` when it is not in the document.
    static func root(of id: String, in document: EditableDocument) -> String? {
        var current = id
        while let parent = document.parents[current] {
            current = parent
        }
        return document.nodes[current] == nil ? nil : current
    }

    /// Whether a node is a text.
    static func isText(_ id: String, in document: EditableDocument) -> Bool {
        if case .text = document.nodes[id]?.kind { return true }
        return false
    }

    /// Whether a node is a frame.
    static func isFrame(_ id: String, in document: EditableDocument) -> Bool {
        if case .frame = document.nodes[id]?.kind { return true }
        return false
    }

    /// Whether a node is a reusable component or sits inside one.
    static func isInsideDefinition(_ id: String, in document: EditableDocument) -> Bool {
        var current: String? = id
        while let node = current {
            if document.nodes[node]?.common.reusable == true { return true }
            current = document.parents[node]
        }
        return false
    }

    /// Every `.pen` file under the bundled fixtures, in a stable order.
    static func fixtureURLs() throws -> [URL] {
        let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        let urls = (walk?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "pen" }
        return urls.sorted { $0.path < $1.path }
    }
}
