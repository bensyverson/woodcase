//
//  RemoteInputState.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// Everything a refused remote operation must leave as it was: the flat store and the
/// replica's clocks and log.
struct RemoteInputState: Equatable {
    let nodes: [String: PenNode]
    let parents: [String: String]
    let children: [String: [String]]
    let rootOrder: [String]
    let variables: [String: PenVariable]?
    let imports: [String: String]?
    let themes: [String: [String]]?
    let clock: LamportClock?
    let vectorClock: VectorClock?
    let operationCount: Int?

    @MainActor
    init(_ document: EditableDocument) {
        nodes = document.nodes
        parents = document.parents
        children = document.children
        rootOrder = document.rootOrder
        variables = document.variables
        imports = document.imports
        themes = document.themes
        clock = document.crdtDocument?.operationLog.clock
        vectorClock = document.crdtDocument?.operationLog.vectorClock
        operationCount = document.crdtDocument?.operationLog.operations.count
    }

    /// A node whose parent chain returns to it, or `nil` when the flat store is a forest.
    @MainActor
    static func parentCycle(in document: EditableDocument) -> String? {
        for start in document.parents.keys {
            var seen: Set<String> = [start]
            var current = document.parents[start]
            while let node = current {
                guard seen.insert(node).inserted else { return start }
                current = document.parents[node]
            }
        }
        return nil
    }
}
