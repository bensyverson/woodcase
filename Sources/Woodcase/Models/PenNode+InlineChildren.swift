//
//  PenNode+InlineChildren.swift
//  Woodcase
//

import Foundation

/// Reading and replacing a container's inline children, for walks that rebuild a tree.
extension PenNode.Kind {
    /// The inline children of a container, or `nil` when it has none written — as
    /// distinct from an empty list.
    var inlineChildrenIfPresent: [PenNode]? {
        switch self {
        case let .frame(data): data.children
        case let .group(data): data.children
        default: nil
        }
    }

    /// The kind with its inline children replaced, for the kinds that carry any.
    ///
    /// - Parameter children: The new children.
    /// - Returns: The kind, or `self` for a kind without children.
    func replacingInlineChildren(with children: [PenNode]) -> Self {
        switch self {
        case var .frame(data):
            data.children = children
            return .frame(data)
        case var .group(data):
            data.children = children
            return .group(data)
        default:
            return self
        }
    }
}
