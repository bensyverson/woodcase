//
//  SwiftUINodeEmitter+Ref.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// An instance (a `ref` node): a call to its component's view struct —
    /// `Card(label: "Revenue")`, with trailing closures for the slots it fills
    /// (``slotCall(_:arguments:fills:)``) — when that call draws what Pen draws, and otherwise the
    /// component inlined, its overrides applied, under a comment naming it, with a warning.
    ///
    /// The call draws what Pen does when the component is one the module declares, every
    /// override is carried by a prop or changes nothing (``InstanceOverrides``), each
    /// argument can be written, the instance is not turned or flipped (its turn is framed
    /// to the component's box, which the call site does not know), and the component's root
    /// sizes the same where the instance sits as in its own body — a `fill_container` root
    /// in a `ZStack` or at a page's root takes its fallback there, which only a copy can say.
    ///
    /// The inlined copy is the one ``PenRefExpander`` prepares, so every override Pen
    /// applies is applied — paths into nested instances, slot content, alias chains — and
    /// the instances inside it are calls or copies in turn. `nil` when the copy's root is
    /// switched off.
    func instance(_ node: PenNode, data: PenNode.RefData, in container: Container) -> SwiftUIViewCode? {
        let label = node.common.name ?? node.id
        let component = scope.components[data.ref]
        var unmapped: [String] = []
        if let component, !scope.chain.contains(data.ref) {
            let mark = themeReads.count
            if let call = call(node, to: component, data: data, in: container, unmapped: &unmapped) {
                return themed(placed(call, node, in: container), node, since: mark)
            }
            // The copy drawn instead reads the theme again.
            themeReads.rollBack(to: mark)
        }
        guard let prepared = PenRefExpander.prepareInstance(
            refNode: node, refData: data, registry: scope.reusable, visited: scope.chain, cache: .init()
        ) else {
            return missing(node, data: data, in: container)
        }
        let name = component?.typeName ?? scope.reusable[data.ref]?.common.name ?? data.ref
        let why = if component == nil {
            "\(SwiftUILiteral.string(name)) is no component the module declares"
        } else if unmapped.isEmpty {
            "a call cannot draw its placement"
        } else {
            "no prop carries its overrides of \(unmapped.joined(separator: ", "))"
        }
        diagnostics?.warn(
            "SwiftUI inlined the instance \"\(label)\" of \(name): \(why)",
            stage: .codeGen, nodeID: node.id
        )
        var emitter = self
        emitter.scope = scope.inlining(chain: prepared.chainVisited)
        guard var view = emitter.view(for: prepared.node, in: container) else { return nil }
        view.comments.insert("woodcase: inlined from \(name)", at: 0)
        return view
    }

    /// The call to `component` that draws the instance, or `nil` when only an inlined copy
    /// can; what no prop carries is named in `unmapped`.
    private func call(
        _ node: PenNode, to component: SwiftUIComponent, data: PenNode.RefData,
        in container: Container, unmapped: inout [String]
    ) -> SwiftUIViewCode? {
        let rotation = node.common.rotation?.literalValue ?? 0
        guard rotation == 0, node.common.flipX?.literalValue != true, node.common.flipY?.literalValue != true,
              sizesAgree(component.definition.sourceNode, in: container)
        else { return nil }
        let overrides = InstanceOverrides(of: data, against: component.bindable, slots: Set(component.slots.map(\.frame.id)))
        unmapped = overrides.unmapped
        if let slot = component.slots.first(where: { !$0.holds(overrides.slotFills[$0.frame.id] ?? []) }) {
            unmapped = [slot.frame.id]
        }
        guard unmapped.isEmpty else { return nil }
        var arguments: [String] = []
        for argument in overrides.arguments {
            guard let prop = component.props.first(where: { $0.definition.name == argument.name }),
                  let value = self.argument(argument.value, to: prop)
            else {
                unmapped = [argument.name]
                return nil
            }
            arguments.append("\(prop.name): \(value)")
        }
        guard overrides.slotFills.isEmpty else {
            return slotCall(component, arguments: arguments, fills: overrides.slotFills)
        }
        return SwiftUIViewCode(head: "\(component.typeName)(\(arguments.joined(separator: ", ")))")
    }

    /// Whether `root` sizes the same in `container` as in its component's own body.
    private func sizesAgree(_ root: PenNode, in container: Container) -> Bool {
        [Axis.width, .height].allSatisfy { axis in
            let sizing = declaredSizing(root, axis: axis)
            return dimension(sizing, in: container) == dimension(sizing, in: .component)
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
