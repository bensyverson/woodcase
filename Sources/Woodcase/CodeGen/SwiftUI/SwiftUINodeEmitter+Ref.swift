//
//  SwiftUINodeEmitter+Ref.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// An instance (a `ref` node): a call to its component's view struct —
    /// `Card(label: "Revenue")`, with trailing closures for the slots it fills
    /// (``slotCall(_:arguments:fills:)``), framed to the size the instance sits at — when
    /// that call draws what Pen draws, and otherwise the component inlined, its overrides
    /// applied, under a comment naming it, with a warning. A ref to a state variant (a tab
    /// bar's `TabBar:home`) is a call pinning that state: `TabBar(selected: .home)`.
    ///
    /// The call draws what Pen does when the component is one the module declares, every
    /// override is carried by a prop or changes nothing (``InstanceOverrides``), each
    /// argument can be written, the instance is not turned or flipped (its turn is framed
    /// to the component's box, which the call site does not know), and a frame at the call
    /// can size the root as the instance does (``callSize(_:resized:axis:in:)``).
    ///
    /// The inlined copy is the one ``PenRefExpander`` prepares, so every override Pen
    /// applies is applied — paths into nested instances, slot content, alias chains — and
    /// the instances inside it are calls or copies in turn. `nil` when the copy's root is
    /// switched off.
    func instance(_ node: PenNode, data: PenNode.RefData, in container: Container) -> SwiftUIPendingView<SwiftUIViewCode?> {
        let variant = scope.variants[data.ref]
        let component = scope.components[variant?.componentID ?? data.ref]
        let name = component?.typeName ?? scope.reusable[data.ref]?.common.name ?? data.ref
        guard let component, !scope.chain.contains(data.ref), !scope.chain.contains(component.definition.id) else {
            return inlined(node, data: data, name: name, refusal: .undeclared(name), in: container)
        }
        let mark = themeReads.count
        return call(node, to: component, pinned: variant?.state, data: data, in: container).flatMap { result in
            switch result {
            case let .success(call):
                return .done(themed(placed(call, node, in: container), node, since: mark))
            case let .failure(why):
                // The copy drawn instead reads the theme again.
                themeReads.rollBack(to: mark)
                return inlined(node, data: data, name: name, refusal: why, in: container)
            }
        }
    }

    /// The instance drawn as the component inlined, its overrides applied, under a comment
    /// naming it, with a warning saying why (`refusal`); a placeholder when the component
    /// is missing or places itself.
    private func inlined(
        _ node: PenNode, data: PenNode.RefData, name: String, refusal: Refusal, in container: Container
    ) -> SwiftUIPendingView<SwiftUIViewCode?> {
        let label = node.common.name ?? node.id
        guard let prepared = PenRefExpander.prepareInstance(
            refNode: node, refData: data, registry: scope.reusable, visited: scope.chain, cache: .init(loops: scope.loops)
        ) else {
            return .done(missing(node, data: data, in: container))
        }
        diagnostics?.warn(
            "SwiftUI inlined the instance \"\(label)\" of \(name): \(refusal)",
            stage: .codeGen, nodeID: node.id
        )
        var emitter = self
        emitter.scope = scope.inlining(chain: prepared.chainVisited)
        return .awaiting([emitter.request(for: prepared.node, in: container)]) { views in
            guard var view = views.first ?? nil else { return .done(nil) }
            view.comments.insert("woodcase: inlined from \(name)", at: 0)
            return .done(view)
        }
    }

    /// Why an instance is a copy rather than a call.
    enum Refusal: Error, Friendly, CustomStringConvertible {
        /// The ref names no component the module declares, only this reusable node.
        case undeclared(String)
        /// The instance is turned or flipped.
        case placement
        /// No prop carries these overrides: descendant ids or root properties.
        case unmapped([String])
        /// No frame at the call sizes the root on this axis as the instance does.
        case size(Axis)
        /// No call argument pins this state of the component.
        case state(String)

        /// The reason as the inlining warning words it.
        var description: String {
            switch self {
            case let .undeclared(name): "\(SwiftUILiteral.string(name)) is no component the module declares"
            case .placement: "a call cannot draw its placement"
            case let .unmapped(names): "no prop carries its overrides of \(names.joined(separator: ", "))"
            case let .size(axis): "no frame at the call can size its root's \(axis == .width ? "width" : "height")"
            case let .state(name): "no call pins its state \(SwiftUILiteral.string(name))"
            }
        }
    }

    /// The call to `component`, pinned in the state `pinned` when the ref names a variant,
    /// that draws the instance, or why only an inlined copy can.
    private func call(
        _ node: PenNode, to component: SwiftUIComponent, pinned: StateDefinition?, data: PenNode.RefData,
        in container: Container
    ) -> SwiftUIPendingView<Result<SwiftUIViewCode, Refusal>> {
        let rotation = node.common.rotation?.literalValue ?? 0
        guard rotation == 0, node.common.flipX?.literalValue != true, node.common.flipY?.literalValue != true else {
            return .done(.failure(.placement))
        }
        // A variant's overrides name its own tree, which no prop of the component reads.
        var measured = component.bindable
        if let variant = pinned?.variantNode {
            measured.sourceNode = variant
            measured.props = []
        }
        let slots = pinned == nil ? Set(component.slots.map(\.frame.id)) : []
        let overrides = InstanceOverrides(of: data, against: measured, slots: slots)
        guard overrides.unmapped.isEmpty else { return .done(.failure(.unmapped(overrides.unmapped))) }
        if let slot = component.slots.first(where: { !$0.holds(overrides.slotFills[$0.frame.id] ?? []) }) {
            return .done(.failure(.unmapped([slot.frame.id])))
        }
        let root = measured.sourceNode
        guard let width = callSize(root, resized: overrides.rootWidth, axis: .width, in: container) else {
            return .done(.failure(.size(.width)))
        }
        guard let height = callSize(root, resized: overrides.rootHeight, axis: .height, in: container) else {
            return .done(.failure(.size(.height)))
        }
        var arguments: [String] = []
        for argument in overrides.arguments {
            guard let prop = component.props.first(where: { $0.definition.name == argument.name }),
                  let value = self.argument(argument.value, to: prop)
            else {
                return .done(.failure(.unmapped([argument.name])))
            }
            arguments.append("\(prop.name): \(value)")
        }
        let view: SwiftUIPendingView<SwiftUIViewCode>
        if let pinned {
            guard let control = SwiftUIControl(component.definition),
                  let lines = SwiftUIEmitter.pinnedCall(pinned, control: control, type: component.typeName)
            else {
                return .done(.failure(.state(pinned.name)))
            }
            var pinnedCall = SwiftUIViewCode(head: lines[0])
            pinnedCall.modifiers += lines.dropFirst().map { SwiftUIViewCode.Modifier(String($0.drop { $0 == " " })) }
            view = .done(pinnedCall)
        } else if !overrides.slotFills.isEmpty {
            view = slotCall(component, arguments: arguments, fills: overrides.slotFills)
        } else {
            view = .done(SwiftUIViewCode(head: "\(component.typeName)(\(arguments.joined(separator: ", ")))"))
        }
        return view.map { call in
            var framed = call
            framed.modifiers += frameModifiers(width: width, height: height, alignment: .center)
            return .success(framed)
        }
    }

    /// The size a call frames the component's `root` to on `axis`, where the instance sits
    /// in `container` and sizes the root as `resized` (`nil`: as the root is sized), or `nil`
    /// when no frame at the call can say it.
    ///
    /// A fixed root is only the body's ideal size (``Dimension/ideal(_:)``), so the call
    /// frames it to a fixed size and leaves a filling one unframed. Any other root keeps
    /// its own sizing, and only where it reads as it does in the body: a frame outside a
    /// content-sized or filling view would not carry its paint with it.
    func callSize(_ root: PenNode, resized: PenSizing?, axis: Axis, in container: Container) -> Dimension? {
        let own = declaredSizing(root, axis: axis)
        guard case .fixed = own else {
            let agrees = resized == nil && dimension(own, in: container) == dimension(own, in: .component)
            return agrees ? .fit : nil
        }
        switch dimension(resized ?? own, in: container) {
        case let .fixed(value): return .fixed(value)
        case .fill: return .fit
        case .minimum, .fit, .ideal: return nil
        }
    }

    /// An instance of a component the document does not hold, or of one inside itself: an
    /// empty view of the instance's size, plus a warning.
    private func missing(_ node: PenNode, data: PenNode.RefData, in container: Container) -> SwiftUIViewCode {
        let label = node.common.name ?? node.id
        let why = scope.chain.contains(data.ref) ? "places itself" : "is not in the document"
        diagnostics?.warn(
            "The component \(SwiftUILiteral.string(data.ref)) the instance \"\(label)\" places \(why); it is a placeholder",
            stage: .codeGen, nodeID: node.id
        )
        var view = SwiftUIViewCode(
            comments: ["woodcase: the component \(SwiftUILiteral.string(data.ref)) \(why)"],
            head: "Color.clear"
        )
        view.modifiers += frameModifiers(
            width: dimension(declaredSizing(node, axis: .width), in: container, empty: true),
            height: dimension(declaredSizing(node, axis: .height), in: container, empty: true),
            alignment: .center
        )
        return placed(view, node, in: container)
    }
}
