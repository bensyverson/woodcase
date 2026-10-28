//
//  SwiftUINodeEmitter+Inking.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// `node` as it stands in a shadow's silhouette: every paint that casts drawn in opaque
    /// black, every other paint left out, and its effects, opacity and blend mode dropped, on
    /// it and on everything under it.
    ///
    /// This is the renderer's `PenShadowSilhouette` rule for each node: a shape's fill covers
    /// it when it paints (``castsPaint(_:)``), however translucent, and its stroke covers its
    /// band when it paints; a line casts its stroke; text and icons cast their glyphs, whatever
    /// their paint; a frame keeps its clip, so its children are cut to it. A kind the renderer
    /// casts nothing of is kept, transparent, so it still takes its place in a layout; an
    /// instance is kept as it is drawn, since its call cannot be repainted.
    ///
    /// The tree is rebuilt bottom-up from a work list rather than by recursion, so nesting
    /// costs no stack (issue `g5SACU`).
    static func inked(_ node: PenNode) -> PenNode {
        var open = [Inking(node: inkedOwnPaint(node), children: containerChildren(node))]
        while var top = open.popLast() {
            if let children = top.children, top.next < children.count {
                let child = children[top.next]
                top.next += 1
                open.append(top)
                if let grandchildren = containerChildren(child) {
                    open.append(Inking(node: inkedOwnPaint(child), children: grandchildren))
                } else {
                    open[open.count - 1].inked.append(inkedOwnPaint(child))
                }
                continue
            }
            var finished = top.node
            if top.children != nil {
                finished.kind = finished.kind.replacingInlineChildren(with: top.inked)
            }
            guard !open.isEmpty else { return finished }
            open[open.count - 1].inked.append(finished)
        }
        return node
    }

    /// A container being inked: the container, its own paint inked, its children, how many
    /// are done, and the inked ones so far.
    private struct Inking {
        /// The container, its own paint inked.
        var node: PenNode

        /// Its children, or `nil` for a node with none to walk.
        var children: [PenNode]?

        /// The index of the next child to ink.
        var next = 0

        /// The children inked so far.
        var inked: [PenNode] = []
    }

    /// A frame's or a group's children, or `nil` for any other node, or one with none.
    private static func containerChildren(_ node: PenNode) -> [PenNode]? {
        switch node.kind {
        case let .frame(data): data.children
        case let .group(data): data.children
        default: nil
        }
    }

    /// `node`'s own paint inked, its children untouched.
    private static func inkedOwnPaint(_ node: PenNode) -> PenNode {
        var node = node
        node.common.opacity = nil
        node.blendMode = nil
        switch node.kind {
        case var .frame(data):
            data.fills = inked(fills: data.fills)
            data.stroke = inked(fills: data.stroke)
            data.effects = nil
            node.kind = .frame(data)
        case var .group(data):
            data.effects = nil
            node.kind = .group(data)
        case var .rectangle(data):
            data.fills = inked(fills: data.fills)
            data.stroke = inked(fills: data.stroke)
            data.effects = nil
            node.kind = .rectangle(data)
        case var .ellipse(data):
            data.fills = inked(fills: data.fills)
            data.stroke = inked(fills: data.stroke)
            data.effects = nil
            node.kind = .ellipse(data)
        case var .polygon(data):
            data.fills = inked(fills: data.fills)
            data.stroke = inked(fills: data.stroke)
            data.effects = nil
            node.kind = .polygon(data)
        case var .path(data):
            data.fills = inked(fills: data.fills)
            data.stroke = inked(fills: data.stroke)
            data.effects = nil
            node.kind = .path(data)
        case var .line(data):
            data.stroke = inked(fills: data.stroke)
            data.effects = nil
            node.kind = .line(data)
        case var .text(data):
            data.fills = ink
            data.stroke = nil
            data.effects = nil
            node.kind = .text(data)
        case var .icon(data):
            data.fills = ink
            data.effects = nil
            node.kind = .icon(data)
        case .ref:
            break
        default:
            node.common.opacity = .literal(0)
        }
        return node
    }

    /// `fills` in a silhouette: opaque black where they paint, nothing where they do not.
    private static func inked(fills: PenFills?) -> PenFills? {
        castsPaint(fills) ? ink : nil
    }

    /// The paint a silhouette is drawn in: opaque black. Only its coverage matters.
    private static let ink = PenFills.single(.shorthand("#000000"))
}
