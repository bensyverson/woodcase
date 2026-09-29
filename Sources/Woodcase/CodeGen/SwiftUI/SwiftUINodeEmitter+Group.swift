//
//  SwiftUINodeEmitter+Group.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// A group, drawn as Pen draws it: no box of its own, only its children, placed at their
    /// `x`/`y` from the group's anchor (``groupStack(_:flow:)``).
    ///
    /// Placed by its own `x`/`y`, the group is a top-leading `ZStack` whose origin is the
    /// anchor: each child sits at its offset as padding, and a negative offset is an
    /// `.offset`, so the child overhangs the anchor. Nothing there reads the group's size,
    /// and its turn pivots at that origin (``transformed(_:_:in:)``), as Pen's does. In a
    /// stack the group's size is its slot, which Pen makes its children's true union, turned
    /// when it turns, so the group is a `PenGroupFlow` and turns about its center.
    ///
    /// Layer effects are the group's as a whole: its shadows are cast by its descendants'
    /// silhouette (``groupSilhouette(_:flow:)``), its blur blurs everything in it, and a group
    /// with an opacity or blend mode is composited first, so it fades and blends as one
    /// layer rather than child by child. A background blur is left out with a warning:
    /// a group has no shape to blur the backdrop through.
    ///
    /// - Parameters:
    ///   - node: The group.
    ///   - data: Its payload.
    ///   - container: What it sits in.
    func group(_ node: PenNode, data: PenNode.GroupData, in container: Container) -> SwiftUIViewCode {
        let children = data.children ?? []
        let flow = Self.isFlow(container) ? GroupFlow(rotation: node.common.rotation?.literalValue ?? 0) : nil
        var view = groupStack(children, flow: flow)
        var effects = effects(data.effects)
        if !effects.outer.isEmpty || !effects.inner.isEmpty, let silhouette = groupSilhouette(children, flow: flow) {
            let style = Effects.Shadow.styles
            var arguments: [String] = []
            if !effects.outer.isEmpty { arguments.append("outer: \(style(effects.outer))") }
            if !effects.inner.isEmpty { arguments.append("inner: \(style(effects.inner))") }
            view.modifiers.append(SwiftUIViewCode.Modifier(
                ".penGroupShadows(\(arguments.joined(separator: ", ")))", content: [silhouette]
            ))
        }
        if !effects.backgroundBlurs.isEmpty {
            effects.unemitted.append("background blur on groups")
        }
        for radius in effects.blurs {
            view = view.modified(".blur(radius: \(radius.code))")
        }
        let opacity = node.common.opacity?.literalValue ?? 1
        if opacity < 1 || (data.blendMode ?? .normal) != .normal {
            view = view.modified(".compositingGroup()")
        }
        warnUnemitted(node, effects.unemitted)
        return view
    }

    /// How a group in a stack is laid out: by `PenGroupFlow`, sized to its children's union.
    struct GroupFlow: Friendly {
        /// The group's turn, in Pen's degrees, which its slot grows to.
        var rotation: Double
    }

    /// Whether a node in `container` sits in a stack's flow rather than at its own `x`/`y`.
    static func isFlow(_ container: Container) -> Bool {
        container == .horizontal || container == .vertical
    }

    /// `children`, each placed at its `x`/`y` from the group's anchor.
    ///
    /// A group placed by its own `x`/`y` is a top-leading `ZStack` whose origin is the
    /// anchor, which the group's offset puts where Pen does; a child reaching left of or above
    /// it overhangs. A group in a stack (`flow`) is a `PenGroupFlow`: Pen sizes its slot to the
    /// children's true union — turned, when the group turns — and draws the union centered in
    /// it (`render-free-groups.pen`'s `flex` and `flexrot`).
    ///
    /// - Parameters:
    ///   - children: The group's children.
    ///   - flow: How the group sits in a stack, or `nil` when it is placed by its `x`/`y`.
    func groupStack(_ children: [PenNode], flow: GroupFlow? = nil) -> SwiftUIViewCode {
        var offsets: [String] = []
        let views = children.compactMap { child -> SwiftUIViewCode? in
            var anchored = child
            anchored.common.x = nil
            anchored.common.y = nil
            guard let view = view(for: anchored, in: .absolute) else { return nil }
            let x = Self.rounded(child.common.x?.literalValue ?? 0)
            let y = Self.rounded(child.common.y?.literalValue ?? 0)
            guard flow != nil else { return placed(view, x: x, y: y) }
            offsets.append("CGPoint(x: \(SwiftUILiteral.number(x)), y: \(SwiftUILiteral.number(y)))")
            return view
        }
        guard let flow else { return SwiftUIViewCode(head: "ZStack(alignment: .topLeading)", body: views) }
        let turn = flow.rotation == 0 ? "" : ", rotation: \(SwiftUILiteral.number(flow.rotation))"
        return SwiftUIViewCode(head: "PenGroupFlow(offsets: [\(offsets.joined(separator: ", "))]\(turn))", body: views)
    }

    /// An offset rounded to a millionth of a point, which drops the float noise Pen leaves in
    /// a coordinate it has rewritten (`1.2e-14`).
    private static func rounded(_ value: Double) -> Double {
        (value * 1e6).rounded() / 1e6
    }

    /// `view` moved to `(x, y)` from its stack's origin: padding for a positive offset, so the
    /// stack grows to hold it, and `.offset` for a negative one, which overhangs.
    private func placed(_ view: SwiftUIViewCode, x: Double, y: Double) -> SwiftUIViewCode {
        let n = SwiftUILiteral.number
        var view = view
        if x > 0 { view = view.modified(".padding(.leading, \(n(x)))") }
        if y > 0 { view = view.modified(".padding(.top, \(n(y)))") }
        switch (x < 0, y < 0) {
        case (true, true): view = view.modified(".offset(x: \(n(x)), y: \(n(y)))")
        case (true, false): view = view.modified(".offset(x: \(n(x)))")
        case (false, true): view = view.modified(".offset(y: \(n(y)))")
        case (false, false): break
        }
        return view
    }
}
