//
//  PenNode+IsConnection.swift
//  Woodcase
//

import Foundation

extension PenNode {
    /// Whether the node is a `connection`, which Pen keeps only at the top level.
    var isConnection: Bool {
        if case .connection = kind { return true }
        return false
    }
}
