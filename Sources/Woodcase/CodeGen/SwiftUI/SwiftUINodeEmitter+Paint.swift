//
//  SwiftUINodeEmitter+Paint.swift
//  Woodcase
//

import Foundation

extension SwiftUINodeEmitter {
    /// `fills`' enabled layers, bottom to top, laid out over a box of `box`'s size.
    ///
    /// Colours, gradients (``SwiftUIGradient``), meshes (``SwiftUIMeshGradient``) and local
    /// images are painted, each with its own opacity and blend mode; an opaque colour of
    /// normal blend hides everything under it, so those layers are left out. A colour
    /// variable, in a colour, a gradient stop or a mesh vertex, is read through the theme
    /// (``colorCode(_:unemitted:)``), and a gradient stop's position variable through it too
    /// (``number(_:unemitted:)``). A shader, a
    /// variable the theme has no colour or number for, a remote image and a malformed colour
    /// are named in `unemitted`.
    ///
    /// In a component's body, the paint a colour or image prop of the node `nodeID` reads
    /// (``SwiftUIProp/boundFillIndex(_:)``) is the prop: the `Color`, or the `Image` placed
    /// by the fill's mode.
    func paintLayers(_ fills: PenFills?, box: FillBox, of nodeID: String? = nil, unemitted: inout [String]) -> [SwiftUIPaintLayer] {
        let boundIndex = nodeID == nil ? nil : SwiftUIProp.boundFillIndex(fills)
        let color = nodeID.flatMap { scope.prop(.color, at: $0) }
        let image = nodeID.flatMap { scope.prop(.image, at: $0) }
        var layers: [SwiftUIPaintLayer] = []
        for (index, fill) in (fills?.all ?? []).enumerated() where fill.isEnabled {
            let content: SwiftUIPaintLayer.Content?
            var opacity: Double?
            var opaque = false
            let bindsColor = index == boundIndex && color != nil
            let bindsImage = index == boundIndex && image != nil
            switch fill {
            case .shorthand where bindsColor, .color where bindsColor:
                // A colour an instance passes may be translucent, so nothing under it is dropped.
                if color?.themedDefault != nil { themeReads.note() }
                content = color.map { .style($0.themedRead) }
            case let .image(fill) where bindsImage:
                content = image.flatMap { imageContent(fill, head: $0.name, unemitted: &unemitted) }
                opacity = fill.opacity?.literalValue
            case .shorthand, .color:
                let color = fill.solidColor.flatMap { colorCode($0, unemitted: &unemitted) }
                content = color.map { .style($0.code) }
                opaque = color?.opaque ?? false
            case let .gradient(gradient):
                content = SwiftUIGradient.content(gradient, box: box, color: colorCode, number: number, unemitted: &unemitted)
                opacity = gradient.opacity?.literalValue
            case let .image(image):
                content = imageContent(image, unemitted: &unemitted)
                opacity = image.opacity?.literalValue
            case let .meshGradient(mesh):
                content = SwiftUIMeshGradient.content(mesh, color: colorCode, unemitted: &unemitted)
                opacity = mesh.opacity?.literalValue
            case .shader, .unknown:
                unemitted.append("\(fill.kindName) fills")
                content = nil
            }
            guard let content else { continue }
            var layer = SwiftUIPaintLayer(content: content)
            if let opacity, opacity < 1 {
                layer.opacity = max(0, opacity)
            }
            if let mode = fill.blendMode, mode != .normal {
                if let name = SwiftUIBlendMode.name(for: mode) {
                    layer.blendMode = ".\(name)"
                } else {
                    unemitted.append("the blend mode \(SwiftUILiteral.string(mode.rawString))")
                }
            }
            layer.isColor = fill.solidColor != nil
            if case .gradient = fill, case .view = content {
                layer.extendsPastBox = true
            }
            layer.covers = opaque && layer.blendMode == nil
            if layer.covers {
                layers.removeAll()
            }
            layers.append(layer)
        }
        return layers
    }

    /// The box a node's paints are laid out over, from its frame's two dimensions.
    func fillBox(width: Dimension, height: Dimension) -> FillBox {
        FillBox(width: width.fixedValue, height: height.fixedValue)
    }

    /// `shape` painted with `layers`, before its frame: the top style filling the shape and
    /// each lower one a background in it, or — when a layer is a view — every layer in a
    /// `ZStack`, clipped to the shape after the frame by ``clip(_:to:)``.
    func paintedShape(_ shape: Outline, layers: [SwiftUIPaintLayer]) -> SwiftUIViewCode {
        let styles = layers.compactMap(\.style)
        guard styles.count == layers.count else {
            return SwiftUIViewCode(head: "ZStack", body: layers.map(\.view))
        }
        var view = SwiftUIViewCode(head: shape.view).modified(".fill(\(styles.last ?? ".clear")\(shape.fillStyle()))")
        for style in styles.dropLast().reversed() {
            view = view.modified(".background(\(style), in: \(shape.argument)\(shape.fillStyle(label: "fillStyle")))")
        }
        return view
    }

    /// Whether ``paintedShape(_:layers:)`` wrote `layers` as views, which need the shape's clip.
    func needsClip(_ layers: [SwiftUIPaintLayer]) -> Bool {
        layers.contains { $0.style == nil }
    }

    /// `view` clipped to `shape`: `.clipped()` for a plain rectangle.
    func clip(_ view: SwiftUIViewCode, to shape: Outline) -> SwiftUIViewCode {
        view.modified(shape == .rectangle ? ".clipped()" : ".clipShape(\(shape.argument)\(shape.fillStyle()))")
    }

    /// The modifiers that paint `layers` behind a view in `shape`: a background per style,
    /// bottom one outermost, or one background of every layer as a view, clipped.
    func backgrounds(_ layers: [SwiftUIPaintLayer], in shape: Outline) -> [SwiftUIViewCode.Modifier] {
        guard !layers.isEmpty else { return [] }
        let styles = layers.compactMap(\.style)
        guard styles.count == layers.count else {
            let stack = clip(SwiftUIViewCode(head: "ZStack", body: layers.map(\.view)), to: shape)
            return [SwiftUIViewCode.Modifier(".background", content: [stack])]
        }
        return styles.reversed().map { style in
            SwiftUIViewCode.Modifier(
                shape == .rectangle ? ".background(\(style))" : ".background(\(style), in: \(shape.argument)\(shape.fillStyle(label: "fillStyle")))"
            )
        }
    }
}

private extension PenFill {
    /// The fill's kind, as a diagnostic names it.
    var kindName: String {
        switch self {
        case .shorthand, .color: "colour"
        case .gradient: "gradient"
        case .image: "image"
        case .meshGradient: "mesh gradient"
        case .shader: "shader"
        case let .unknown(typeName, _): typeName
        }
    }
}
