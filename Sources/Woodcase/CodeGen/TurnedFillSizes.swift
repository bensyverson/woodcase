//
//  TurnedFillSizes.swift
//  Woodcase
//

import Foundation

/// The boxes Pen gives a flex container's turned `fill_container` children, worked out when
/// code is generated, so an emitter can write them as fixed sizes.
///
/// Pen fills a turned child's **unturned** box — the main-axis share, taken before any
/// child is turned, or the container's inner cross size — and allocates the bounds of the
/// turned result (`PenLayoutEngine+FlexFill.swift`). Neither flexbox nor a SwiftUI stack can
/// say "fill as if unturned, then take the turned room": a CSS flex item's margins come out
/// of the free space it shares, and a stack gives a flexible frame what is left after the
/// others. But when every input to that arithmetic is a number in the document — the
/// container's size on the filled axis, its padding and gap, and each sibling's extent on
/// the main axis — the filled box is a constant, and an emitter writes it as one, turned
/// into its slot as any fixed-size turned child is. The main-axis share is then pinned for
/// the container's unturned main-axis fills too, which Pen gives the same share.
///
/// A turned fill child whose box depends on something only the running layout knows — a
/// container sized by its content or its parent, a sibling sized by its content, a
/// variable — is listed in ``unresolved`` for the emitter to warn about; it keeps the
/// unturned slot of an ordinary fill.
struct TurnedFillSizes: Friendly {
    /// A child's filled box, on the axes the container fills, in points.
    struct Box: Friendly {
        /// The width, when the container fills it.
        var width: Double?
        /// The height, when the container fills it.
        var height: Double?
    }

    /// What kept a turned fill child's box from being worked out.
    enum Unresolved: String, Friendly {
        /// The main-axis share: the container's main size is not a number, or a sibling's
        /// main extent is not.
        case share
        /// The container's inner cross size is not a number.
        case crossSize
        /// The child's own size on an axis the container does not fill is not a number, or
        /// its turn is a variable.
        case ownSize

        /// The generate-time warning for a child this kept from its turned slot.
        func warning(label: String, emitter: String) -> String {
            let cause = switch self {
            case .share: "its share of the container depends on a size only the layout knows"
            case .crossSize: "its container's cross size depends on a size only the layout knows"
            case .ownSize: "its turn or its size on the other axis is not a number"
            }
            return "\(emitter) gives the turned fill_container \"\(label)\" the slot of its unturned box: \(cause)"
        }
    }

    /// The filled boxes, keyed by child id: each turned fill child that could be worked out,
    /// and each unturned main-axis fill sharing a container with a turned one.
    var boxes: [String: Box] = [:]

    /// The turned fill children that could not be worked out, keyed by id, with the reason.
    var unresolved: [String: Unresolved] = [:]

    /// No sizes: what a container without turned fill children has.
    init() {}

    /// The sizes for `container`'s flow children.
    ///
    /// - Parameter container: A frame; one with `layout: none` places no child in a flow
    ///   and has none.
    init(container: PenNode.FrameData) {
        let layout = container.layout ?? .horizontal
        guard layout != .none else { return }
        let flow = (container.children ?? []).filter {
            $0.common.enabled?.literalValue != false && $0.common.layoutPosition != .absolute
        }
        let axes = Axes(horizontal: layout == .horizontal)
        let turned = flow.filter { child in
            Self.turn(of: child) != .straight && (axes.main(child).isFill || axes.cross(child).isFill)
        }
        guard !turned.isEmpty else { return }

        let padding: PenPadding.Edges? = if let declared = container.padding { declared.resolve() } else { .zero }
        let gap: Double? = if let declared = container.gap { declared.literalValue } else { 0 }
        let crossInner: Double? = if let padding, case let .fixed(size) = axes.cross(container) {
            max(0, size - (axes.horizontal ? padding.vertical : padding.horizontal))
        } else { nil }
        let share = Self.share(of: flow, axes: axes, container: container, padding: padding, gap: gap, crossInner: crossInner)

        var sharesPinned = false
        for child in turned {
            var box = Box()
            var reason: Unresolved?
            for isMain in [true, false] {
                let sizing = isMain ? axes.main(child) : axes.cross(child)
                guard sizing.isFill else { continue }
                guard let value = isMain ? share : crossInner else {
                    reason = reason ?? (isMain ? .share : .crossSize)
                    continue
                }
                if axes.horizontal == isMain { box.width = value } else { box.height = value }
            }
            if reason == nil, Self.turn(of: child) == nil || !axes.otherAxesFixed(child) {
                reason = .ownSize
            }
            if let reason {
                unresolved[child.id] = reason
            } else {
                boxes[child.id] = box
                sharesPinned = sharesPinned || axes.main(child).isFill
            }
        }
        guard sharesPinned, let share else { return }
        for child in flow where axes.main(child).isFill && boxes[child.id] == nil && unresolved[child.id] == nil {
            boxes[child.id] = axes.horizontal ? Box(width: share) : Box(height: share)
        }
    }

    /// `node` with its filled box written as fixed sizes, or `node` itself when it has none.
    func sized(_ node: PenNode) -> PenNode {
        guard let box = boxes[node.id] else { return node }
        var properties: [String: AnyCodable] = [:]
        if let width = box.width { properties["width"] = .double(width) }
        if let height = box.height { properties["height"] = .double(height) }
        return PenNodePatcher.patchNode(node, with: properties)
    }

    // MARK: - Arithmetic

    /// The main-axis share each fill child takes, as Pen's layout takes it: the container's
    /// inner main size less its gaps and its other children's main extents, split evenly,
    /// and never under Pen's 1 pt floor (``PenLayoutEngine/FlexLayout/minimumFillMain``).
    private static func share(
        of flow: [PenNode], axes: Axes, container: PenNode.FrameData,
        padding: PenPadding.Edges?, gap: Double?, crossInner: Double?
    ) -> Double? {
        guard let padding, let gap, case let .fixed(size) = axes.main(container) else { return nil }
        var taken = gap * Double(max(0, flow.count - 1))
        var fills = 0
        for child in flow {
            if axes.main(child).isFill {
                fills += 1
                continue
            }
            guard let extent = mainExtent(of: child, axes: axes, crossInner: crossInner) else { return nil }
            taken += extent
        }
        let inner = size - (axes.horizontal ? padding.horizontal : padding.vertical)
        return max(PenLayoutEngine.FlexLayout.minimumFillMain, (inner - taken) / Double(max(1, fills)))
    }

    /// A child's extent on the main axis: its size there, or the bounds of its turned box.
    private static func mainExtent(of child: PenNode, axes: Axes, crossInner: Double?) -> Double? {
        guard let turn = turn(of: child) else { return nil }
        let main = axes.main(child).fixedValue
        if turn == .straight { return main }
        let cross = axes.cross(child).isFill ? crossInner : axes.cross(child).fixedValue
        guard let main, let cross else { return nil }
        let width = axes.horizontal ? main : cross
        let height = axes.horizontal ? cross : main
        let bounds = PenLayoutEngine.rotatedBoundingBox(width: width, height: height, rotationDegrees: turn.degrees)
        return axes.horizontal ? bounds.width : bounds.height
    }

    /// A node's turn: ``Turn/straight`` when it has none or a half turn's multiple, which
    /// leaves its bounds its box; `nil` when it is a variable.
    private static func turn(of node: PenNode) -> Turn? {
        guard let rotation = node.common.rotation else { return .straight }
        guard let degrees = rotation.literalValue else { return nil }
        return abs(sin(degrees * .pi / 180)) < 1e-9 ? .straight : .degrees(degrees)
    }

    /// A node's turn, as the arithmetic reads it.
    private enum Turn: Equatable {
        /// No turn, or one that leaves the bounds the box.
        case straight
        /// A turn by this many degrees.
        case degrees(Double)

        /// The angle, zero for none.
        var degrees: Double {
            if case let .degrees(value) = self { return value }
            return 0
        }
    }

    /// Reads a node's sizing along the container's main and cross axes.
    private struct Axes {
        /// Whether the main axis is horizontal: a row.
        let horizontal: Bool

        /// The node's sizing along the main axis.
        func main(_ node: PenNode) -> PenSizing {
            horizontal ? PenLayoutEngine.widthSizing(of: node) : PenLayoutEngine.heightSizing(of: node)
        }

        /// The node's sizing along the cross axis.
        func cross(_ node: PenNode) -> PenSizing {
            horizontal ? PenLayoutEngine.heightSizing(of: node) : PenLayoutEngine.widthSizing(of: node)
        }

        /// The container's sizing along the main axis.
        func main(_ container: PenNode.FrameData) -> PenSizing {
            (horizontal ? container.width : container.height) ?? .fitContent(fallback: nil)
        }

        /// The container's sizing along the cross axis.
        func cross(_ container: PenNode.FrameData) -> PenSizing {
            (horizontal ? container.height : container.width) ?? .fitContent(fallback: nil)
        }

        /// Whether every axis the container does not fill is a fixed number.
        func otherAxesFixed(_ node: PenNode) -> Bool {
            [main(node), cross(node)].allSatisfy { $0.isFill || $0.fixedValue != nil }
        }
    }
}

private extension PenSizing {
    /// Whether this is `fill_container`.
    var isFill: Bool {
        if case .fillContainer = self { return true }
        return false
    }
}
