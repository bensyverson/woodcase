//
//  SwiftUINodeEmitter.swift
//  Woodcase
//

/// Turns one .pen node, and everything under it, into a ``SwiftUIViewCode`` tree.
///
/// A value holding the run's diagnostics; the per-kind decisions are its extensions
/// (`+Frame`, `+Shape`, `+Text`, `+Sizing`, `+Paint`, `+Effects`, `+Transform`, `+Ref`). It is not `Friendly`: the
/// collector it reports into is a shared reference, not a value.
struct SwiftUINodeEmitter {
    /// What a node sits in, which decides how its size and position are written.
    enum Container: Friendly {
        /// The page itself: nothing around it.
        case root

        /// An `HStack`: a horizontal Pen layout.
        case horizontal

        /// A `VStack`: a vertical Pen layout.
        case vertical

        /// A `ZStack` placing children by `x`/`y`: Pen's `layout: none`, or an absolutely
        /// positioned child's overlay.
        case absolute

        /// A component's body: sized as its instances are placed, so `fill_container`
        /// takes whatever the caller offers.
        case component
    }

    /// Receives a warning for every node or property this emitter does not write yet.
    let diagnostics: PenDiagnosticCollector?

    /// The `Shape` types the page declares for its paths, polygons, lines and arcs.
    let shapes = SwiftUIShapeDeclarations()

    /// The reads of `theme` the struct's body makes outside any `PenThemeReader`.
    let themeReads = SwiftUIThemeReads()

    /// The components an instance can call or inline, the props the body reads, and the
    /// theme it reads variables through.
    var scope = SwiftUIComponentScope()

    /// The view for `node`, or `nil` when the node is switched off (`enabled: false`); a
    /// context node's view is set in its theme (``themed(_:_:since:)``).
    func view(for node: PenNode, in container: Container) -> SwiftUIViewCode? {
        guard node.common.enabled?.literalValue != false else { return nil }
        if case let .ref(data) = node.kind {
            // An instance sets its own theme: on the call, or on the copy's root.
            return instance(node, data: data, in: container)
        }
        let mark = themeReads.count
        let view: SwiftUIViewCode = switch node.kind {
        case let .frame(data): frame(node, data: data, in: container)
        case let .rectangle(data): rectangle(node, data: data, in: container)
        case let .ellipse(data): ellipse(node, data: data, in: container)
        case let .text(data) where scope.textField == node.id: textField(node, data: data, in: container)
        case let .text(data): text(node, data: data, in: container)
        case .path, .polygon, .line: geometry(node, in: container)
        case let .icon(data): icon(node, data: data, in: container)
        case let .group(data): group(node, data: data, in: container)
        default: placeholder(node, in: container)
        }
        return themed(placed(view, node, in: container), node, since: mark)
    }

    /// `view`, drawn for `node`, with what every kind shares: its effects, its turn and
    /// flip, its offset in a `ZStack`, its opacity and its blend mode.
    func placed(_ view: SwiftUIViewCode, _ node: PenNode, in container: Container) -> SwiftUIViewCode {
        var view = view
        warnVariableSizing(node)
        view = withEffects(view, of: node)
        view = transformed(view, node, in: container)
        if container == .absolute {
            let x = node.common.x?.literalValue ?? 0
            let y = node.common.y?.literalValue ?? 0
            if x != 0 || y != 0 {
                view = view.modified(".offset(x: \(SwiftUILiteral.number(x)), y: \(SwiftUILiteral.number(y)))")
            }
        }
        var unemitted: [String] = []
        if let opacity = node.common.opacity.flatMap({ number($0, unemitted: &unemitted) }), opacity.literal.map({ $0 < 1 }) ?? true {
            view = view.modified(".opacity(\(opacity.code))")
        }
        warnUnemitted(node, unemitted)
        return blended(view, node)
    }

    /// A node this emitter does not write yet: a comment naming it and an empty view of
    /// its declared size, plus a warning.
    func placeholder(_ node: PenNode, in container: Container) -> SwiftUIViewCode {
        let kind = node.kind.typeName
        let label = node.common.name ?? node.id
        diagnostics?.warn(
            "SwiftUI does not emit \(kind) nodes yet; \"\(label)\" is a placeholder",
            stage: .codeGen, nodeID: node.id
        )
        var view = SwiftUIViewCode(
            comments: ["woodcase: \(kind) \(SwiftUILiteral.string(label)) is not emitted yet"],
            head: "Color.clear"
        )
        let width = declaredSizing(node, axis: .width)
        let height = declaredSizing(node, axis: .height)
        view.modifiers += frameModifiers(
            width: dimension(width, in: container, empty: true),
            height: dimension(height, in: container, empty: true),
            alignment: .center
        )
        return view
    }

    /// Warn once for each property on `node` this slice does not write.
    func warnUnemitted(_ node: PenNode, _ properties: [String]) {
        guard !properties.isEmpty else { return }
        let label = node.common.name ?? node.id
        diagnostics?.warn(
            "SwiftUI does not emit \(properties.joined(separator: ", ")) yet; \"\(label)\" is drawn without it",
            stage: .codeGen, nodeID: node.id
        )
    }
}
