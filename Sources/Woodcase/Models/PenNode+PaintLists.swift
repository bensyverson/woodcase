//
//  PenNode+PaintLists.swift
//  Woodcase
//

import Foundation

extension PenNode.Kind {
    /// The paint lists a node of this kind carries: its fills and its stroke's paint.
    ///
    /// Either is `nil` for a kind that has none (a line has no fill, an icon no stroke) or a
    /// node that writes none. A walk that asks what a node paints with — a lint check, a
    /// warning about paint a target drops — reads both from here rather than restating
    /// which kinds carry which.
    var paintLists: (fills: PenFills?, stroke: PenFills?) {
        switch self {
        case let .frame(data): (data.fills, data.stroke)
        case let .text(data): (data.fills, data.stroke)
        case let .rectangle(data): (data.fills, data.stroke)
        case let .ellipse(data): (data.fills, data.stroke)
        case let .path(data): (data.fills, data.stroke)
        case let .polygon(data): (data.fills, data.stroke)
        case let .line(data): (nil, data.stroke)
        case let .icon(data): (data.fills, nil)
        case let .browser(data): (nil, data.stroke)
        default: (nil, nil)
        }
    }
}
