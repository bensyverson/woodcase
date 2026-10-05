//
//  ComponentRenderGraph+Edges.swift
//  Woodcase
//

import Foundation

extension ComponentRenderGraph {
    /// A graph over edges the caller already holds — every component's, rather than the
    /// part one component reaches.
    ///
    /// - Parameter edges: Each vertex's targets. A target that is no key is a sink.
    init(edges: [String: [String]]) {
        self.edges = edges.mapValues { Array(Set($0)).sorted() }
    }
}
