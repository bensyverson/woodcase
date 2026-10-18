//
//  ReactEmitter+Nodes.swift
//  Woodcase
//

extension ReactEmitter {
    // MARK: - Node Emission

    /// Emits `node` and everything under it into `ctx`.
    ///
    /// The tree is walked from a work list of ``ReactEmitStep``s, not by recursion: each
    /// node's own emitter writes what comes before its children and hands back the rest
    /// (``nodeSteps(_:component:indent:ctx:isRoot:parentLayout:)``), so a deep tree costs
    /// no more stack than a shallow one.
    static func emitNode(
        _ node: PenNode,
        component: ComponentDefinition,
        indent: Int,
        ctx: EmitContext,
        isRoot: Bool = true,
        parentLayout: PenLayoutDirection? = nil
    ) {
        var pending: [ReactEmitStep] = [.node(node, component: component, indent: indent, isRoot: isRoot, parentLayout: parentLayout)]
        while let step = pending.popLast() {
            switch step {
            case let .node(node, component, indent, isRoot, parentLayout):
                let steps = nodeSteps(node, component: component, indent: indent, ctx: ctx, isRoot: isRoot, parentLayout: parentLayout)
                pending.append(contentsOf: steps.reversed())
            case let .then(work):
                work()
            }
        }
    }

    /// Writes what comes before `node`'s children and returns the steps that remain: its
    /// children and whatever follows them, ending with restoring the turned-fill sizes
    /// it read.
    static func nodeSteps(
        _ node: PenNode,
        component: ComponentDefinition,
        indent: Int,
        ctx: EmitContext,
        isRoot: Bool,
        parentLayout: PenLayoutDirection?
    ) -> [ReactEmitStep] {
        // A turned fill child's box, when its container's numbers fix it, is written as a
        // fixed size, which ``turnedSlotStyles(_:width:height:isRoot:ctx:)`` then grows to
        // its turned slot. The sizes are its container's alone: its own children see none.
        let turnedFillSizes = ctx.turnedFillSizes
        ctx.turnedFillSizes = TurnedFillSizes()
        if let reason = turnedFillSizes.unresolved[node.id] {
            ctx.warnOnce(reason.warning(label: node.common.name ?? node.id, emitter: "React"), nodeID: node.id)
        }
        let node = turnedFillSizes.sized(node)
        warnDroppedShaders(node, ctx: ctx)
        warnUnblendedShadows(node, ctx: ctx)
        warnDroppedInnerShadows(node, ctx: ctx)
        warnTextImageCrops(node, ctx: ctx)
        var steps: [ReactEmitStep] = []
        switch node.kind {
        case let .frame(data):
            steps = emitFrame(node, data: data, component: component, indent: indent, ctx: ctx, isRoot: isRoot, parentLayout: parentLayout)
        case let .text(data):
            emitText(node, data: data, component: component, indent: indent, ctx: ctx, isRoot: isRoot, parentLayout: parentLayout)
        case let .group(data):
            steps = emitGroup(node, data: data, component: component, indent: indent, ctx: ctx, isRoot: isRoot)
        case let .rectangle(data):
            emitRectangle(node, data: data, indent: indent, ctx: ctx, isRoot: isRoot, parentLayout: parentLayout)
        case let .ellipse(data):
            emitEllipse(node, data: data, indent: indent, ctx: ctx, isRoot: isRoot, parentLayout: parentLayout)
        case let .polygon(data):
            emitPolygon(node, data: data, indent: indent, ctx: ctx, isRoot: isRoot, parentLayout: parentLayout)
        case let .path(data):
            emitPath(node, data: data, indent: indent, ctx: ctx, isRoot: isRoot, parentLayout: parentLayout)
        case let .line(data):
            emitLine(node, data: data, indent: indent, ctx: ctx, isRoot: isRoot, parentLayout: parentLayout)
        case let .icon(data):
            emitIcon(node, data: data, indent: indent, ctx: ctx, isRoot: isRoot, parentLayout: parentLayout)
        case let .script(data):
            emitScript(node, data: data, indent: indent, ctx: ctx, isRoot: isRoot, parentLayout: parentLayout)
        case let .browser(data):
            emitBrowser(node, data: data, indent: indent, ctx: ctx, isRoot: isRoot, parentLayout: parentLayout)
        case let .ref(data):
            steps = emitRef(node, data: data, indent: indent, ctx: ctx, isRoot: isRoot)
        case .connection:
            // A connector between two nodes on the canvas — Pen allows it only between
            // artboards — has no place in a component's markup.
            break
        default:
            let pad = String(repeating: " ", count: indent)
            ctx.lines.append("\(pad){/* unsupported node type */}")
        }
        steps.append(.then { ctx.turnedFillSizes = turnedFillSizes })
        return steps
    }

    /// Returns `flexShrink: 0` for non-root, non-absolute children that have
    /// fixed dimensions along the parent's flex axis.
    ///
    /// In a horizontal layout, only a fixed width triggers `flexShrink: 0`.
    /// In a vertical layout, only a fixed height triggers it.
    /// When the parent layout is unknown, either fixed dimension triggers it
    /// (conservative fallback).
    static func emitFlexShrink(
        _ node: PenNode,
        isRoot: Bool,
        hasFixedWidth: Bool,
        hasFixedHeight: Bool,
        parentLayout: PenLayoutDirection? = nil
    ) -> [(String, String)] {
        guard !isRoot, node.common.layoutPosition != .absolute else { return [] }

        let shouldPreventShrink: Bool = switch parentLayout {
        case .horizontal, .some(.none), nil:
            // Row layout (or no layout / layout:none = default horizontal): only fixed width matters
            hasFixedWidth
        case .vertical:
            // Column layout: only fixed height matters
            hasFixedHeight
        }

        guard shouldPreventShrink else { return [] }
        return [("flexShrink", "0")]
    }
}
