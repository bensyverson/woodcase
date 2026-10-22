//
//  SwiftUINodeEmitter+Frame.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// A frame: a stack of its children — `HStack`, `VStack`, or a top-leading `ZStack`
    /// for `layout: none` — padded, framed to its size, clipped, then painted and stroked
    /// under them, its outer shadows cast by its box and its stroke band (``Silhouette``).
    ///
    /// A frame with nothing in it is drawn as its own outline, like a rectangle. An
    /// absolutely positioned child of a stack rides in an `.overlay`, placed by its
    /// `x`/`y` in the frame's box. A component's slot frame stacks its slot's content
    /// (``SwiftUISlot``) instead of its children.
    func frame(_ node: PenNode, data: PenNode.FrameData, in container: Container) -> SwiftUIPendingView<SwiftUIViewCode> {
        var outlineUnemitted: [String] = []
        let shape = outline(data.cornerRadius, unemitted: &outlineUnemitted)
        let layout = data.layout ?? .horizontal
        let children = data.children ?? []
        let inFlow = layout == .none ? children : children.filter { $0.common.layoutPosition != .absolute }
        let childContainer: Container = switch layout {
        case .horizontal: .horizontal
        case .vertical: .vertical
        case .none: .absolute
        }
        // A slot's stack draws the content a caller passes in place of the frame's children.
        let slot = scope.slots[node.id]
        let flowNodes = slot == nil ? turnedFillsSized(inFlow, of: data) : []
        let overlaidNodes = layout == .none || slot != nil ? [] : children.filter { $0.common.layoutPosition == .absolute }
        let requests = flowNodes.map { request(for: $0, in: childContainer) } + overlaidNodes.map { request(for: $0, in: .absolute) }
        return views(requests).map { (views: [SwiftUIViewCode?]) -> SwiftUIViewCode in
            let flowViews = slot.map { [SwiftUIViewCode(head: $0.name)] } ?? views.prefix(flowNodes.count).compactMap(\.self)
            let overlaid = views.dropFirst(flowNodes.count).compactMap(\.self)
            var unemitted = outlineUnemitted
            // A frame with nothing in it is drawn as a shape: its outline, painted and stroked.
            if flowViews.isEmpty, overlaid.isEmpty {
                return filledShape(node, shape: shape, fills: data.fills, stroke: data, effects: data.effects, in: container, unemitted: unemitted)
            }
            // A `layout: none` frame's children do not size it: Pen settles its `fit_content`
            // at the fallback, 0 by default, and they overhang it (see `PenEngine.md`).
            let sizedByContent = layout != .none
            let width = dimension(declaredSizing(node, axis: .width), in: container, empty: !sizedByContent)
            let height = dimension(declaredSizing(node, axis: .height), in: container, empty: !sizedByContent)
            let box = fillBox(width: width, height: height)
            let layers = paintLayers(data.fills, box: box, of: node.id, unemitted: &unemitted)
            // A frame under a point on an axis — a sizeless `layout: none` one — is stroked in a
            // box grown by the stroke's reach, as a flat shape is: SwiftUI draws nothing there.
            let outset = FlatOutset(width: width, height: height, stroke: data)
            var stroke = strokeView(
                data, shape: outset.map { shape.outset($0) } ?? shape, box: box, dash: node.strokeDash,
                miterLimit: Self.writtenMiterLimit(of: node), overFills: !layers.isEmpty, unemitted: &unemitted
            )
            if let outset {
                stroke = stroke?.modified(outset.padding)
            }

            let justify = data.justifyContent ?? .start
            let align = data.alignItems ?? .start
            let gap = spacing(data.gap, unemitted: &unemitted)
            var view = stack(layout, children: flowViews, justify: justify, align: align, gap: gap)
            view.modifiers += padding(data.padding, unemitted: &unemitted)
            let main = layout == .vertical ? height : width
            if main == .fit, justify == .spaceBetween || justify == .spaceAround {
                // Spacers would stretch a content-sized stack to whatever its parent offers.
                let axis = layout == .vertical ? "horizontal: false, vertical: true" : "horizontal: true, vertical: false"
                view = view.modified(".fixedSize(\(axis))")
            }
            view.modifiers += frameModifiers(
                width: width, height: height,
                alignment: frameAlignment(layout, justify: justify, align: align)
            )
            if !overlaid.isEmpty {
                view.modifiers.append(.init(".overlay(alignment: .topLeading)", content: overlaid))
            }
            // The clip is the children's alone: Pen draws the frame's own paint before it.
            if data.clip?.literalValue == true {
                view = clip(view, to: shape)
            }
            // Pen's order under the children: fills, inner shadows, stroke.
            view.modifiers += ownPaint(
                layers: layers, innerShadows: innerShadows(data.effects, in: shape, underContent: true), stroke: stroke,
                in: shape, isolated: isolatesPaints(fills: layers, stroke: stroke == nil ? nil : data)
            )
            warnUnemitted(node, unemitted)
            // Cast by its box and its stroke band, not its children.
            let silhouette = silhouette(of: node, shape: shape, stroke: data, box: box, outset: outset)
            return withEffects(view, of: node, effects: data.effects, fills: data.fills, silhouette: silhouette)
        }
    }

    /// The backgrounds that draw a frame's own paint under its children: its fills, its
    /// inner shadows (`.background` modifiers) and its stroke, bottom to top.
    ///
    /// Each is a background of its own, a later one drawn under an earlier, unless the
    /// paints blend (``isolatesPaints(fills:stroke:)``): then they are one background, a
    /// `ZStack` composited as a group, so a blended paint stays within the frame's paints
    /// while the children above it — and their own blend modes — are not grouped with them.
    private func ownPaint(
        layers: [SwiftUIPaintLayer], innerShadows: [SwiftUIViewCode.Modifier], stroke: SwiftUIViewCode?,
        in shape: Outline, isolated: Bool
    ) -> [SwiftUIViewCode.Modifier] {
        guard isolated else {
            let strokeBackground = stroke.map { [SwiftUIViewCode.Modifier(".background", content: [$0])] } ?? []
            return strokeBackground + innerShadows + backgrounds(layers, in: shape)
        }
        var paints: [SwiftUIViewCode] = []
        if !layers.isEmpty {
            let fill = paintedShape(shape, layers: layers)
            paints.append(needsClip(layers) ? clip(fill, to: shape) : fill)
        }
        paints += innerShadows.flatMap { $0.content ?? [] }
        paints += [stroke].compactMap(\.self)
        let group = SwiftUIViewCode(head: "ZStack", body: paints).modified(".compositingGroup()")
        return [SwiftUIViewCode.Modifier(".background", content: [group])]
    }

    /// The stack for `layout`, its children interleaved with `Spacer`s for the two
    /// `space_*` distributions: between each pair for `space_between`; a unit at each end
    /// and two between each pair for `space_around`, which is the half-and-whole spacing
    /// that distribution means. There the gap becomes the spacers' minimum.
    private func stack(
        _ layout: PenLayoutDirection, children: [SwiftUIViewCode],
        justify: PenJustifyContent, align: PenAlignItems, gap: SwiftUINumber
    ) -> SwiftUIViewCode {
        if layout == .none {
            return SwiftUIViewCode(head: "ZStack(alignment: .topLeading)", body: children)
        }
        var body = children
        var spacing = gap
        switch justify {
        case .spaceBetween where children.count > 1:
            let spacer = SwiftUIViewCode(head: "Spacer(minLength: \(gap.code))")
            body = Array(children.map { [$0] }.joined(separator: [spacer]))
            spacing = SwiftUINumber(0)
        case .spaceAround:
            let spacer = SwiftUIViewCode(head: "Spacer(minLength: \(gap.halved.code))")
            body = [spacer] + Array(children.map { [$0] }.joined(separator: [spacer, spacer])) + [spacer]
            spacing = SwiftUINumber(0)
        default:
            break
        }
        let head: String
        var arguments: [String] = []
        if layout == .horizontal {
            head = "HStack"
            let vertical = SwiftUIAlignment.vertical(align)
            if vertical != .center { arguments.append("alignment: .\(vertical.rawValue)") }
        } else {
            head = "VStack"
            let horizontal = SwiftUIAlignment.horizontal(align)
            if horizontal != .center { arguments.append("alignment: .\(horizontal.rawValue)") }
        }
        arguments.append("spacing: \(spacing.code)")
        return SwiftUIViewCode(head: "\(head)(\(arguments.joined(separator: ", ")))", body: body)
    }

    /// Where the stack sits in the frame's box: the main axis from `justifyContent`, the
    /// cross axis from `alignItems`.
    private func frameAlignment(_ layout: PenLayoutDirection, justify: PenJustifyContent, align: PenAlignItems) -> SwiftUIAlignment {
        let main: PenAlignItems = switch justify {
        case .start, .spaceBetween, .spaceAround: .start
        case .center: .center
        case .end: .end
        }
        return switch layout {
        case .horizontal: SwiftUIAlignment(horizontal: SwiftUIAlignment.horizontal(main), vertical: SwiftUIAlignment.vertical(align))
        case .vertical: SwiftUIAlignment(horizontal: SwiftUIAlignment.horizontal(align), vertical: SwiftUIAlignment.vertical(main))
        case .none: SwiftUIAlignment(horizontal: .leading, vertical: .top)
        }
    }

    /// The gap in points, or the theme's; a variable the theme has no number for is
    /// reported and reads as none.
    private func spacing(_ gap: PenValue<Double>?, unemitted: inout [String]) -> SwiftUINumber {
        guard let gap else { return SwiftUINumber(0) }
        return number(gap, unemitted: &unemitted) ?? SwiftUINumber(0)
    }

    /// The padding modifiers: one number when uniform, `.horizontal` and `.vertical` when
    /// symmetric, `EdgeInsets` otherwise.
    ///
    /// An edge that names a variable reads the theme's number; one the theme lacks is
    /// reported and drops the padding.
    private func padding(_ padding: PenPadding?, unemitted: inout [String]) -> [SwiftUIViewCode.Modifier] {
        guard let padding else { return [] }
        let values: [PenValue<Double>] = switch padding {
        case let .uniform(value): [value, value, value, value]
        case let .symmetric(h, v): [v, h, v, h]
        case let .individual(top, right, bottom, left): [top, right, bottom, left]
        }
        let edges = values.compactMap { number($0, unemitted: &unemitted) }
        guard edges.count == 4 else { return [] }
        let (top, right, bottom, left) = (edges[0], edges[1], edges[2], edges[3])
        if top.code == bottom.code, left.code == right.code {
            if top.code == left.code {
                return top.isZero ? [] : [.init(".padding(\(top.code))")]
            }
            var modifiers: [SwiftUIViewCode.Modifier] = []
            if !left.isZero { modifiers.append(.init(".padding(.horizontal, \(left.code))")) }
            if !top.isZero { modifiers.append(.init(".padding(.vertical, \(top.code))")) }
            return modifiers
        }
        return [.init(
            ".padding(EdgeInsets(top: \(top.code), leading: \(left.code), bottom: \(bottom.code), trailing: \(right.code)))"
        )]
    }
}
