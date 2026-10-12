//
//  PenNode+LayoutEdit.swift
//  Woodcase
//

import Foundation

extension PenNode {
    /// Changes a container's inline children in place, without copying the list.
    ///
    /// The list is taken out of the node before `body` runs, so it is uniquely referenced
    /// and edits to it do not copy every sibling. A node that cannot hold children is left
    /// alone and `body` does not run.
    ///
    /// - Parameter body: The change to make to the children.
    mutating func modifyInlineChildren(_ body: (inout [PenNode]) -> Void) {
        switch kind {
        case var .frame(data):
            var children = data.children ?? []
            data.children = nil
            kind = .frame(data)
            body(&children)
            data.children = children
            kind = .frame(data)
        case var .group(data):
            var children = data.children ?? []
            data.children = nil
            kind = .group(data)
            body(&children)
            data.children = children
            kind = .group(data)
        default:
            return
        }
    }
}

extension PenNode.Kind {
    /// Sets the sizing a node is laid out by on each axis given; `nil` leaves an axis as
    /// it is.
    ///
    /// A group has no sizing of its own — it is always its children's union — and a
    /// `ref`, a connection or an unknown type has none the layout reads, so those are left
    /// alone.
    ///
    /// - Parameters:
    ///   - width: The width sizing, or `nil`.
    ///   - height: The height sizing, or `nil`.
    mutating func setLayoutSizing(width: PenSizing?, height: PenSizing?) {
        switch self {
        case var .frame(data): Self.set(&data, width, height); self = .frame(data)
        case var .text(data): Self.set(&data, width, height); self = .text(data)
        case var .rectangle(data): Self.set(&data, width, height); self = .rectangle(data)
        case var .ellipse(data): Self.set(&data, width, height); self = .ellipse(data)
        case var .path(data): Self.set(&data, width, height); self = .path(data)
        case var .line(data): Self.set(&data, width, height); self = .line(data)
        case var .polygon(data): Self.set(&data, width, height); self = .polygon(data)
        case var .note(data): Self.set(&data, width, height); self = .note(data)
        case var .prompt(data): Self.set(&data, width, height); self = .prompt(data)
        case var .context(data): Self.set(&data, width, height); self = .context(data)
        case var .icon(data): Self.set(&data, width, height); self = .icon(data)
        case var .script(data): Self.set(&data, width, height); self = .script(data)
        case var .browser(data): Self.set(&data, width, height); self = .browser(data)
        case .group, .ref, .connection, .unknown: return
        }
    }

    /// Sets the sizings given on one payload.
    private static func set(_ payload: inout some PenLayoutSized, _ width: PenSizing?, _ height: PenSizing?) {
        if let width { payload.width = width }
        if let height { payload.height = height }
    }
}
