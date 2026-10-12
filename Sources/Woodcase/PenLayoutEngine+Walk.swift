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
/// caller's map, store `1` (``discardStore``) takes what calls that are not final write
/// below their node, and each flex container owns a scratch store for its measuring
/// passes, freed when it finishes — frames finish in the reverse of the order they start,
/// so the scratch stores do too.
///
/// Every call consults the ``Memo``: a remembered size skips the subtree, under the rules
/// set out there.
extension PenLayoutEngine {
    /// The store that calls that are not final write below their node: never merged into
    /// the caller's map.
    static let discardStore = 1

    /// Sizes a node and writes the rects of all its descendants — not its own.
    ///
    /// - Parameters:
    ///   - node: The node to size.
    ///   - availableWidth: The width its parent offers it, or `nil`.
    ///   - availableHeight: The height its parent offers it, or `nil`.
    ///   - textMeasurer: A function that measures text bounding boxes.
    ///   - rects: The map the descendants' rects are written to. A subtree skipped on a
    ///     remembered size keeps the rects the map already holds for it.
    ///   - memo: The sizes remembered so far, read and filled.
    /// - Returns: The node's size.
    static func layoutNode(
        _ node: PenNode,
        availableWidth: Double?,
        availableHeight: Double?,
        textMeasurer: TextMeasurer,
        into rects: inout [String: PenRect],
        memo: inout Memo
    ) -> (width: Double, height: Double) {
        // The caller's map is moved in and back out rather than copied.
        var stores: [[String: PenRect]] = [[:], [:]]
        swap(&stores[0], &rects)
        defer { swap(&stores[0], &rects) }

        let root = LayoutFrame.Call(
            node: node, availableWidth: availableWidth, availableHeight: availableHeight,
            target: 0, isFinal: true
        )
        var stack: [LayoutFrame] = []
        switch begin(root, textMeasurer: textMeasurer, stores: &stores, memo: &memo) {
        case let .finished(width, height): return (width, height)
        case let .pending(frame): stack.append(frame)
        }

        var resumed: (width: Double, height: Double)?
        while let last = stack.indices.last {
            switch stack[last].advance(resuming: resumed, stores: &stores) {
            case let .call(child):
                switch begin(child, textMeasurer: textMeasurer, stores: &stores, memo: &memo) {
                case let .finished(width, height):
                    resumed = (width, height)
                case let .pending(frame):
                    resumed = nil
                    stack.append(frame)
                }
            case let .done(width, height):
                let finished = stack.removeLast()
                memo.remember((width, height), for: finished.call)
                memo.log(finished)
                if finished.scratch != nil {
                    stores.removeLast()
                }
                guard !stack.isEmpty else { return (width, height) }
                resumed = (width, height)
            }
        }
        preconditionFailure("the layout walk ended without sizing its root")
    }

    /// Starts one call: answers it from the memo or, for a leaf, at once; otherwise
    /// opens a frame for the container, with a scratch store if it is a flex one.
    private static func begin(
        _ call: LayoutFrame.Call,
        textMeasurer: TextMeasurer,
        stores: inout [[String: PenRect]],
        memo: inout Memo
    ) -> LayoutFrame.Start {
        if let size = memo.size(for: call) {
            memo.stats.hits += 1
            restoreGroupChildren(of: call, in: &stores)
            return .finished(width: size.width, height: size.height)
        }

        let props = extractLayoutProperties(call.node)
        guard props.isContainer else {
            let size = layoutLeafNode(
                props, availableWidth: call.availableWidth, availableHeight: call.availableHeight,
                textMeasurer: textMeasurer
            )
            memo.remember(size, for: call)
            memo.stats.leavesSized += 1
            return .finished(width: size.width, height: size.height)
        }

        guard props.layout != PenLayoutDirection.none else {
            return .pending(LayoutFrame(call: call, absolute: AbsoluteLayout(call: call, props: props)))
        }
        stores.append([:])
        return .pending(LayoutFrame(call: call, flex: FlexLayout(call: call, props: props, scratch: stores.count - 1)))
    }

    /// Copies a skipped group's children's rects from the caller's map into the store the
    /// call writes to.
    ///
    /// A group's parent places it by the union of its children's rects
    /// (``freeRect(of:x:y:size:placedIn:)``), read from that store. A group is skipped only
    /// on its last final call's offer, so the caller's map holds the rects that call wrote,
    /// and a group lays its children out at their own x/y whatever it is offered.
    private static func restoreGroupChildren(of call: LayoutFrame.Call, in stores: inout [[String: PenRect]]) {
        guard call.target != 0, case let .group(data) = call.node.kind else { return }
        for child in data.children ?? [] {
            if let rect = stores[0][child.id] {
                stores[call.target][child.id] = rect
            }
        }
    }
}
