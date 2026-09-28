//
//  PenLayoutEngine+Walk.swift
//  Woodcase
//

import Foundation

/// The layout walk: sizing a node and writing the rects of everything below it,
/// without recursion.
///
/// Layout is recursive by nature — a container's size depends on its children's, and a
/// flex container sizes some children more than once — and it used to be written that
/// way. A debug build reserved about 13 KB of stack for every level of flex containers,
/// so a frame tree some thirty-five deep overflowed a Swift task's 512 KiB
/// (`project/2026-09-26-debug-stack-depth.md`). Each container is now a
/// ``LayoutFrame`` — the state its call used to keep in a stack frame — held in an
/// array on the heap. The walk asks the top frame for its next step: a child to size
/// (a leaf is sized at once; a container becomes a new frame) or its own size, which
/// resumes the frame below. The order of every measurement and every rect write is the
/// recursive algorithm's.
///
/// Rect maps are **stores** indexed by ``LayoutFrame/Call/target``: store `0` is the
/// caller's map, and each flex container owns a scratch store for its measuring passes,
/// freed when it finishes — frames finish in the reverse of the order they start, so
/// the scratch stores do too.
extension PenLayoutEngine {
    /// Sizes a node and writes the rects of all its descendants — not its own.
    ///
    /// - Parameters:
    ///   - node: The node to size.
    ///   - availableWidth: The width its parent offers it, or `nil`.
    ///   - availableHeight: The height its parent offers it, or `nil`.
    ///   - textMeasurer: A function that measures text bounding boxes.
    ///   - rects: The map the descendants' rects are written to.
    ///   - cache: A measurement cache to read and fill, or `nil` for none.
    /// - Returns: The node's size.
    static func layoutNode(
        _ node: PenNode,
        availableWidth: Double?,
        availableHeight: Double?,
        textMeasurer: TextMeasurer,
        into rects: inout [String: PenRect],
        cache: inout [String: MeasurementCacheEntry]?
    ) -> (width: Double, height: Double) {
        // The caller's map is moved in and back out rather than copied.
        var stores: [[String: PenRect]] = [[:]]
        swap(&stores[0], &rects)
        defer { swap(&stores[0], &rects) }

        let root = LayoutFrame.Call(
            node: node, availableWidth: availableWidth, availableHeight: availableHeight,
            target: 0, usesCache: true
        )
        var stack: [LayoutFrame] = []
        switch begin(root, textMeasurer: textMeasurer, stores: &stores, cache: &cache) {
        case let .finished(width, height): return (width, height)
        case let .pending(frame): stack.append(frame)
        }

        var resumed: (width: Double, height: Double)?
        while let last = stack.indices.last {
            switch stack[last].advance(resuming: resumed, stores: &stores) {
            case let .call(child):
                switch begin(child, textMeasurer: textMeasurer, stores: &stores, cache: &cache) {
                case let .finished(width, height):
                    resumed = (width, height)
                case let .pending(frame):
                    resumed = nil
                    stack.append(frame)
                }
            case let .done(width, height):
                let finished = stack.removeLast()
                remember((width, height), for: finished.call, in: &cache)
                if finished.scratch != nil {
                    stores.removeLast()
                }
                guard !stack.isEmpty else { return (width, height) }
                resumed = (width, height)
            }
        }
        preconditionFailure("the layout walk ended without sizing its root")
    }

    /// Starts one call: answers it from the cache or, for a leaf, at once; otherwise
    /// opens a frame for the container, with a scratch store if it is a flex one.
    private static func begin(
        _ call: LayoutFrame.Call,
        textMeasurer: TextMeasurer,
        stores: inout [[String: PenRect]],
        cache: inout [String: MeasurementCacheEntry]?
    ) -> LayoutFrame.Start {
        // A cache hit skips the whole subtree. That is safe for incremental layout
        // because the caller's map is pre-populated from the previous rects.
        if call.usesCache, let entry = cache?[call.node.id],
           entry.availableWidth == call.availableWidth,
           entry.availableHeight == call.availableHeight
        {
            return .finished(width: entry.width, height: entry.height)
        }

        let props = extractLayoutProperties(call.node)
        guard props.isContainer else {
            let size = layoutLeafNode(
                props, availableWidth: call.availableWidth, availableHeight: call.availableHeight,
                textMeasurer: textMeasurer
            )
            remember(size, for: call, in: &cache)
            return .finished(width: size.width, height: size.height)
        }

        guard props.layout != PenLayoutDirection.none else {
            return .pending(LayoutFrame(call: call, absolute: AbsoluteLayout(call: call, props: props)))
        }
        stores.append([:])
        return .pending(LayoutFrame(call: call, flex: FlexLayout(call: call, props: props, scratch: stores.count - 1)))
    }

    /// Records a call's size in the measurement cache, when it uses one.
    private static func remember(
        _ size: (width: Double, height: Double),
        for call: LayoutFrame.Call,
        in cache: inout [String: MeasurementCacheEntry]?
    ) {
        guard call.usesCache, cache != nil else { return }
        cache?[call.node.id] = MeasurementCacheEntry(
            availableWidth: call.availableWidth,
            availableHeight: call.availableHeight,
            width: size.width,
            height: size.height
        )
    }
}
