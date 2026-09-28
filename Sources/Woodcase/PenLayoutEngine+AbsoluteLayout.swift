//
//  PenLayoutEngine+AbsoluteLayout.swift
//  Woodcase
//

import Foundation

extension PenLayoutEngine {
    /// A container that places its children at their own `x`/`y` — a frame with no
    /// layout, or a group — part-way through being laid out.
    ///
    /// A frame has no flow for `fit_content` to measure: Pen settles that axis at its
    /// fallback, 0 by default, whatever its children reach, and they overhang it — see
    /// `PenEngine.md`, "Absolute containers and `fit_content`". A group has no size of its
    /// own: it is its children's true union (``PenLayoutEngine/groupBox(of:in:)``),
    /// wherever that starts.
    struct AbsoluteLayout {
        /// The call this container answers.
        let call: LayoutFrame.Call

        /// The container's layout properties.
        let props: NodeLayoutProperties

        /// The index of the next child to place.
        var next = 0

        /// The right edge of the enabled children placed so far, from the frame's origin.
        var contentWidth = 0.0

        /// The bottom edge of the enabled children placed so far.
        var contentHeight = 0.0

        /// Places children until one needs sizing, or all are placed.
        ///
        /// - Parameters:
        ///   - size: The size of the child the last step asked for, or `nil`.
        ///   - stores: The walk's rect maps.
        /// - Returns: The next child to size, or the container's own size.
        mutating func advance(
            resuming size: (width: Double, height: Double)?,
            stores: inout [[String: PenRect]]
        ) -> LayoutFrame.Step {
            if let size {
                let child = props.children[next]
                let rect = PenLayoutEngine.freeRect(
                    of: child, x: Self.x(of: child), y: Self.y(of: child), size: size, placedIn: stores[call.target]
                )
                stores[call.target][child.id] = rect
                include(child, rect)
                next += 1
            }

            while next < props.children.count {
                let child = props.children[next]
                if let rect = PenLayoutEngine.tryShortCircuitFixedLeaf(
                    child, x: Self.x(of: child), y: Self.y(of: child), into: &stores[call.target]
                ) {
                    include(child, rect)
                    next += 1
                    continue
                }
                return .call(LayoutFrame.Call(
                    node: child, availableWidth: nil, availableHeight: nil,
                    target: call.target, usesCache: call.usesCache
                ))
            }

            if case .group = call.node.kind {
                let box = PenLayoutEngine.groupBox(of: call.node, in: stores[call.target])
                return .done(width: box.width, height: box.height)
            }
            return .done(
                width: Self.size(props.widthSizing, extent: contentWidth, available: call.availableWidth),
                height: Self.size(props.heightSizing, extent: contentHeight, available: call.availableHeight)
            )
        }

        /// A frame's size on one axis.
        ///
        /// `fit_content` is its fallback, never the children's extent (leaf Jg0BOv's Pen
        /// probe). Every other sizing resolves as a container's does; `fill_container`
        /// with no room and no fallback still reads the extent, where Pen is unmeasured.
        private static func size(_ sizing: PenSizing, extent: Double, available: Double?) -> Double {
            if case let .fitContent(fallback) = sizing { return fallback ?? 0 }
            return PenLayoutEngine.resolveContainerSize(sizing, contentSize: extent, available: available).size
        }

        /// Grows the content box to a placed child. Disabled nodes take no space,
        /// matching the flex path.
        private mutating func include(_ child: PenNode, _ rect: PenRect) {
            guard child.common.enabled?.literalValue != false else { return }
            contentWidth = max(contentWidth, rect.x + rect.width)
            contentHeight = max(contentHeight, rect.y + rect.height)
        }

        /// A child's own `x`, or `0`.
        private static func x(of child: PenNode) -> Double {
            child.common.x?.literalValue ?? 0
        }

        /// A child's own `y`, or `0`.
        private static func y(of child: PenNode) -> Double {
            child.common.y?.literalValue ?? 0
        }
    }
}
