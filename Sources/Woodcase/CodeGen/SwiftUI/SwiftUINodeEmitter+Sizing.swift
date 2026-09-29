//
//  SwiftUINodeEmitter+Sizing.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// One axis of a node's size, as SwiftUI's frames can say it.
    enum Dimension: Friendly {
        /// Exactly this many points: `width: 80`.
        case fixed(Double)

        /// As much as the container offers, and no less than nothing: `minWidth: 0,
        /// maxWidth: .infinity`, so content larger than its room overflows the frame rather
        /// than growing it, as a flex item with `min-width: 0` does.
        case fill

        /// At least this many points, more if the content needs it: `minWidth: 200`.
        case minimum(Double)

        /// The content's own size: no frame at all.
        case fit
    }

    /// The axis of a size.
    enum Axis: Friendly {
        case width, height
    }

    /// The sizing Pen lays `node` out by on `axis`, defaults included.
    func declaredSizing(_ node: PenNode, axis: Axis) -> PenSizing {
        switch axis {
        case .width: PenLayoutEngine.widthSizing(of: node)
        case .height: PenLayoutEngine.heightSizing(of: node)
        }
    }

    /// How `sizing` reads inside `container`.
    ///
    /// `fill_container` has nothing to fill in a page root or a `layout: none` parent, so
    /// there it is its fallback when it has one. `fit_content(N)` is at least `N`. A node
    /// with no content to size it (`empty`: a shape, a placeholder, a frame with no
    /// children, a `layout: none` frame) fits to exactly `N`, or to zero — what Pen draws;
    /// left unframed, a SwiftUI `Shape` or `Color` would take all the space it is offered
    /// instead, and a `ZStack` would size itself to its children.
    func dimension(_ sizing: PenSizing, in container: Container, empty: Bool = false) -> Dimension {
        switch sizing {
        case let .fixed(value):
            return .fixed(value)
        case let .fillContainer(fallback):
            if container == .root || container == .absolute, let fallback {
                return .fixed(fallback)
            }
            return .fill
        case let .fitContent(fallback):
            if empty { return .fixed(fallback ?? 0) }
            return fallback.map { .minimum($0) } ?? .fit
        case .variable:
            return .fit
        }
    }

    /// The `.frame` modifiers for a size and an alignment.
    ///
    /// SwiftUI splits fixed and flexible frames into two overloads, so a node fixed on
    /// one axis and flexible on the other gets two: the fixed frame first, the flexible
    /// one around it, both carrying the alignment. A centered alignment is left unwritten.
    func frameModifiers(width: Dimension, height: Dimension, alignment: SwiftUIAlignment) -> [SwiftUIViewCode.Modifier] {
        var fixed: [String] = []
        var flexible: [String] = []
        for (axis, dimension) in [("Width", width), ("Height", height)] {
            let name = axis.lowercased()
            switch dimension {
            case let .fixed(value): fixed.append("\(name): \(SwiftUILiteral.number(value))")
            case .fill:
                // Without the zero minimum the frame takes its content's size as its
                // floor and grows past its room; Pen's flex item shrinks and overflows.
                flexible += ["min\(axis): 0", "max\(axis): .infinity"]
            case let .minimum(value): flexible.append("min\(axis): \(SwiftUILiteral.number(value))")
            case .fit: break
            }
        }
        let aligned = alignment == .center ? [] : ["alignment: \(alignment.code)"]
        var modifiers: [SwiftUIViewCode.Modifier] = []
        if !fixed.isEmpty {
            modifiers.append(.init(".frame(\((fixed + aligned).joined(separator: ", ")))"))
        }
        if !flexible.isEmpty {
            // SwiftUI's parameter order is minWidth, maxWidth, minHeight, maxHeight.
            let ordered = flexible.sorted { order($0) < order($1) }
            modifiers.append(.init(".frame(\((ordered + aligned).joined(separator: ", ")))"))
        }
        return modifiers
    }

    private func order(_ argument: String) -> Int {
        ["minWidth", "maxWidth", "minHeight", "maxHeight"].firstIndex { argument.hasPrefix($0) } ?? 4
    }

    /// Warn when `node`'s size names a document variable, which this slice does not
    /// resolve: the node is sized by its content instead.
    func warnVariableSizing(_ node: PenNode) {
        var properties: [String] = []
        if case let .variable(name) = declaredSizing(node, axis: .width) {
            properties.append("width $\(name)")
        }
        if case let .variable(name) = declaredSizing(node, axis: .height) {
            properties.append("height $\(name)")
        }
        warnUnemitted(node, properties)
    }
}

extension SwiftUINodeEmitter.Dimension {
    /// The size in points when fixed.
    var fixedValue: Double? {
        guard case let .fixed(value) = self else { return nil }
        return value
    }
}
