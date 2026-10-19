//
//  PenClip+Sizes.swift
//  Woodcase
//

import Foundation

extension PenClip {
    /// The two dimensions a sizing is written on.
    enum Dimension: Friendly, CaseIterable {
        /// `width`.
        case width

        /// `height`.
        case height

        /// The dimension's property path.
        var path: String {
            switch self {
            case .width: EditPlanner.widthPath
            case .height: EditPlanner.heightPath
            }
        }

        /// The dimension of a drawn size.
        func of(_ size: PenSize) -> Double {
            switch self {
            case .width: size.width
            case .height: size.height
            }
        }

        /// The sizing an origin recorded on this dimension.
        func of(_ origin: Origin?) -> PenSizing? {
            switch self {
            case .width: origin?.width
            case .height: origin?.height
            }
        }
    }

    /// The pasted roots, each sized for the parent it lands in (Ben's ruling of
    /// 2026-10-15, Penumbra spec §4): where that parent lays it out — a stack, holding it
    /// in flow — a dimension that filled its container where it was copied
    /// (``Origin/width``, ``Origin/height``) fills again; where the parent does not — a
    /// free frame, a group, the canvas — a dimension the clip still writes as
    /// `fill_container` becomes the number it was drawn at, as a move there would
    /// (``EditPlanner/planMove(nodeID:into:at:keepingDrawnPlace:in:layout:)``). A `fit_content` dimension
    /// works anywhere, so it stays.
    ///
    /// - Parameters:
    ///   - placed: The roots, placed, in clip order.
    ///   - origins: Each root's origin, in the same order.
    ///   - drawn: Each root's size as the clip draws it, in the same order; asked for only
    ///     when some root needs it.
    ///   - document: The target document.
    /// - Returns: The roots, sized.
    static func sized(
        _ placed: [PasteSite.Placed],
        origins: [Origin?],
        drawn: () -> [PenSize?],
        in document: EditableDocument
    ) -> [PasteSite.Placed] {
        var sizes: [PenSize?]?
        return zip(placed, origins).enumerated().map { index, pair in
            var (root, origin) = pair
            let laidOut = EditPlanner.laysOut(root.parentID, in: document) && root.node.common.layoutPosition != .absolute
            for dimension in Dimension.allCases {
                if laidOut, let recorded = dimension.of(origin) {
                    root.node = setting(recorded, on: dimension, of: root.node)
                } else if !laidOut, case .fillContainer? = sizing(on: dimension, of: root.node) {
                    if sizes == nil { sizes = drawn() }
                    guard let size = sizes?[index] else { continue }
                    root.node = setting(.fixed(dimension.of(size)), on: dimension, of: root.node)
                }
            }
            return root
        }
    }

    /// A node's sizing on a dimension, or `nil` when it has none or its kind has no such
    /// dimension.
    static func sizing(on dimension: Dimension, of node: PenNode) -> PenSizing? {
        guard let value = try? NodePropertyCodec.value(at: dimension.path, of: node),
              let data = try? JSONEncoder().encode(value)
        else { return nil }
        return try? JSONDecoder().decode(PenSizing.self, from: data)
    }

    /// A node with a sizing written on a dimension; unchanged when its kind refuses it.
    static func setting(_ sizing: PenSizing, on dimension: Dimension, of node: PenNode) -> PenNode {
        let value: AnyCodable? = if case let .fixed(number) = sizing {
            EditPlanner.number(number)
        } else {
            (try? JSONEncoder().encode(sizing)).flatMap { try? JSONDecoder().decode(AnyCodable.self, from: $0) }
        }
        guard let value, let written = try? NodePropertyCodec.setting(value, at: dimension.path, on: node) else {
            return node
        }
        return written
    }
}
