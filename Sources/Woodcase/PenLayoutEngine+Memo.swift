//
//  PenLayoutEngine+Memo.swift
//  Woodcase
//

import Foundation

extension PenLayoutEngine {
    /// What the layout walk remembers of the sizes it computed, and what it may skip.
    ///
    /// A node's size is a function of its subtree and the space its parent offers it, so
    /// a size computed once for an offer is good for that offer until the subtree changes
    /// — the owner forgets a changed node and its ancestors (``forget(_:)``). The walk asks
    /// for a node's size in two kinds of call:
    ///
    /// - A **final** call is the last one for its node in a layout, and the rects it writes
    ///   below the node end up in the caller's map. It may skip the subtree only when the
    ///   node's last final call had the same offer (``finals``): the map already holds the
    ///   rects that call wrote.
    /// - Any other call — a flex container measuring a child it lays out again at its
    ///   resolved cross size — writes below the node into a store nobody keeps, so it may
    ///   take a size computed for its offer in any call (``sizes``). A group is the
    ///   exception: its parent places it by its children's rects, not its size, so a
    ///   group is laid out again in such a call.
    ///
    /// ``finals`` is exactly the public ``MeasurementCacheEntry`` map a host keeps between
    /// incremental layouts; ``sizes`` lives as long as its owner keeps the memo.
    struct Memo {
        /// The offer and size of each node's last final call.
        var finals: [String: MeasurementCacheEntry] = [:]

        /// Sizes computed in calls that were not final, newest last, a few per node.
        var sizes: [String: [MeasurementCacheEntry]] = [:]

        /// What the walk did, for a caller that asks.
        var stats = PenLayoutStats()

        /// The nodes whose rects the walk wrote to the caller's map since
        /// ``clearLog()``: every child of a container laid out in a final call.
        var written: [String] = []

        /// The disabled children of the flex containers laid out in a final call since
        /// ``clearLog()``: a flow gives them, and everything under them, no rect.
        var unplaced: [String] = []

        /// How many non-final sizes a node keeps: a flex parent offers a child at most
        /// three different spaces in one layout.
        static let sizesPerNode = 4

        /// A memo starting from a host's final entries.
        ///
        /// - Parameter finals: The entries of each node's last final call.
        init(finals: [String: MeasurementCacheEntry] = [:]) {
            self.finals = finals
        }

        /// The size a call may take without laying its node out, if any.
        ///
        /// - Parameter call: The call.
        /// - Returns: The remembered size.
        func size(for call: LayoutFrame.Call) -> (width: Double, height: Double)? {
            let id = call.node.id
            if let entry = finals[id], entry.answers(call) {
                return (entry.width, entry.height)
            }
            guard !call.isFinal, !Self.isGroup(call.node) else { return nil }
            guard let entry = sizes[id]?.last(where: { $0.answers(call) }) else { return nil }
            return (entry.width, entry.height)
        }

        /// Records the size a call computed.
        ///
        /// - Parameters:
        ///   - size: The node's size.
        ///   - call: The call that computed it.
        mutating func remember(_ size: (width: Double, height: Double), for call: LayoutFrame.Call) {
            let entry = MeasurementCacheEntry(
                availableWidth: call.availableWidth, availableHeight: call.availableHeight,
                width: size.width, height: size.height
            )
            if call.isFinal {
                finals[call.node.id] = entry
                return
            }
            var list = sizes[call.node.id] ?? []
            list.removeAll { $0.answers(call) }
            list.append(entry)
            if list.count > Self.sizesPerNode {
                list.removeFirst(list.count - Self.sizesPerNode)
            }
            sizes[call.node.id] = list
        }

        /// Records a container the walk finished laying out.
        ///
        /// - Parameter frame: The container's finished frame.
        mutating func log(_ frame: LayoutFrame) {
            stats.containersLaidOut.append(frame.call.node.id)
            guard frame.call.isFinal else { return }
            let children = PenLayoutEngine.nodeChildren(frame.call.node) ?? []
            written.append(contentsOf: children.map(\.id))
            if frame.flex != nil {
                unplaced.append(contentsOf: children.filter { $0.common.enabled?.literalValue == false }.map(\.id))
            }
        }

        /// Starts a new record of what a pass does: ``stats``, ``written`` and ``unplaced``.
        mutating func clearLog() {
            stats = PenLayoutStats()
            written.removeAll(keepingCapacity: true)
            unplaced.removeAll(keepingCapacity: true)
        }

        /// Forgets everything remembered of a node.
        ///
        /// - Parameter id: The node's expanded id.
        mutating func forget(_ id: String) {
            finals.removeValue(forKey: id)
            sizes.removeValue(forKey: id)
        }

        private static func isGroup(_ node: PenNode) -> Bool {
            if case .group = node.kind { return true }
            return false
        }
    }
}

extension PenLayoutEngine.MeasurementCacheEntry {
    /// Whether the entry was computed for the space a call offers.
    ///
    /// - Parameter call: The call.
    func answers(_ call: PenLayoutEngine.LayoutFrame.Call) -> Bool {
        availableWidth == call.availableWidth && availableHeight == call.availableHeight
    }
}
