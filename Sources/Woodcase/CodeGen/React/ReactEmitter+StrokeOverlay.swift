//
//  ReactEmitter+StrokeOverlay.swift
//  Woodcase
//

extension ReactEmitter {
    /// The outline a stroke overlay follows.
    enum StrokeOverlayShape: Friendly {
        /// A box with the node's corner radius, if any.
        case box(PenCornerRadius?)
        /// An ellipse inscribed in the box.
        case ellipse
    }

    /// The ring mask: everything, minus the content box.
    private static let ringMaskLayers = "linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0)"

    /// The style of the element that draws a box's stroke when it is more than one plain
    /// color or a plain color on per-side widths, or `nil` when a plain declaration
    /// (``emitStroke(_:)``) draws it or nothing does.
    ///
    /// CSS borders, outlines and box-shadows take one color, so the stroke is an absolutely
    /// positioned overlay whose three boxes line up with the stroke's geometry:
    ///
    /// - its **border box** is the stroke's outer edge — the node's box grown by the
    ///   stroke's outer reach, a transparent border of that width on each side;
    /// - its **padding box** is therefore the node's box, Pen's paint domain for every
    ///   alignment (`project/2026-09-26-text-and-stroke-fills.md`, finding 2), so an image
    ///   or mesh layer placed against it lands where Pen puts it and draws nowhere else;
    /// - its **content box**, inset by the rest of the width as padding, is the stroke's
    ///   inner edge, which the mask cuts out, leaving the ring. Border radii shrink box by
    ///   box as CSS rounds them, so the ring follows the node's corners.
    ///
    /// Gradients are laid out over the whole element with their geometry pulled back onto
    /// the node's box, so they pad past it as Pen's do.
    ///
    /// - Parameters:
    ///   - stroke: The node's stroke.
    ///   - shape: The outline the stroke follows.
    ///   - beneathChildren: Whether the overlay must paint under the node's children, as
    ///     Pen draws a container's stroke before them; the host must then isolate.
    /// A cropped image paint (``isCroppedImage(_:)``) and every paint above it are not
    /// background layers but elements inside the overlay (``strokeOverlayChildren(_:ring:box:ctx:)``),
    /// which its mask cuts to the ring like the rest.
    ///
    /// - Parameters:
    ///   - stroke: The node's stroke.
    ///   - shape: The outline the stroke follows.
    ///   - beneathChildren: Whether the overlay must paint under the node's children, as
    ///     Pen draws a container's stroke before them; the host must then isolate.
    ///   - box: The node's box, which sizes a mesh raster.
    ///   - ctx: The emission context, for a themed mesh.
    static func strokeOverlay(
        _ stroke: any PenStrokable,
        shape: StrokeOverlayShape,
        beneathChildren: Bool,
        box: FillBox,
        ctx: EmitContext
    ) -> FillLayer? {
        guard let fills = overlayFills(stroke) else { return nil }
        let ring = StrokeRing(stroke)
        let split = PaintSplit(fills)
        let layers = paintLayers(split.background, outsets: ring.outsets, box: box, ctx: ctx)
        let children = strokeOverlayChildren(split.layered, ring: ring, box: box, ctx: ctx)
        guard !layers.isEmpty || !children.isEmpty else { return nil }

        var styles = overlayBox(ring)
        if let radius = overlayRadius(shape, outsets: ring.outsets) {
            styles.append(("borderRadius", radius))
        }
        if !layers.isEmpty {
            styles.append(contentsOf: paintLayerDeclarations(layers, withOrigin: true))
        }
        styles.append(("WebkitMask", "\"\(ringMaskLayers)\""))
        styles.append(("WebkitMaskComposite", "\"xor\""))
        styles.append(("mask", "\"linear-gradient(#000 0 0) content-box exclude, linear-gradient(#000 0 0)\""))
        if children.isEmpty, let blend = loneLayerBlend(layers) {
            styles.append(("mixBlendMode", "\"\(blend)\""))
        }
        if beneathChildren {
            styles.append(("zIndex", "-1"))
        }
        styles.append(("pointerEvents", "\"none\""))
        return FillLayer(styles, children: children)
    }

    /// The position, transparent border and padding that put an overlay's border box on the
    /// stroke's outer edge, its padding box on the node's box and its content box on the
    /// stroke's inner edge.
    private static func overlayBox(_ ring: StrokeRing) -> [(String, String)] {
        var styles = [("position", "\"absolute\"")]
        let inset = ring.outsets.map { $0.scaled(by: -1) }
        styles.append(("inset", inset.isZero ? "0" : "\"\(inset.css)\""))
        if !ring.outsets.isZero {
            styles.append(("borderStyle", "\"solid\""))
            styles.append(("borderColor", "\"transparent\""))
            styles.append(("borderWidth", "\"\(ring.outsets.css)\""))
        }
        if !ring.insideWidths.isZero {
            styles.append(("padding", "\"\(ring.insideWidths.css)\""))
        }
        return styles
    }

    /// The elements inside an overlay that draw its `layered` paints, bottom first: a crop
    /// over the node's box — the overlay's padding box — unclipped, since a cover crop shows
    /// image past the box in an outer stroke; any other paint on an element with the
    /// overlay's own geometry, so it lands where the overlay's background would put it.
    private static func strokeOverlayChildren(
        _ layered: [PenFill],
        ring: StrokeRing,
        box: FillBox,
        ctx: EmitContext
    ) -> [FillLayer] {
        layered.compactMap { fill -> FillLayer? in
            if case let .image(image) = fill, image.transform != nil {
                guard fill.isEnabled, let element = imageCropElement(image, ctx: ctx) else { return nil }
                let styles = [("position", "\"absolute\""), ("inset", "0")] + cropLayerPaintStyles(image)
                return FillLayer(styles, content: element)
            }
            let layers = paintLayers([fill], outsets: ring.outsets, box: box, ctx: ctx)
            guard !layers.isEmpty else { return nil }
            var styles = overlayBox(ring) + paintLayerDeclarations(layers, withOrigin: true)
            if let blend = loneLayerBlend(layers) {
                styles.append(("mixBlendMode", "\"\(blend)\""))
            }
            return FillLayer(styles)
        }
    }

    /// The layers an overlay paints for `stroke`, or `nil` when a plain declaration draws
    /// it: every layer of a painted stroke, or a plain color on per-side widths. A CSS
    /// border cannot draw those even inside the box: it would move the children, which
    /// Pen's stroke does not (`render-inner-sides`), and paint over them.
    private static func overlayFills(_ stroke: any PenStrokable) -> [PenFill]? {
        let route = PaintRoute(stroke.stroke)
        if let layered = route.layeredFills { return layered }
        guard let color = route.plainColor, case .perSide = stroke.strokeWidth else {
            return nil
        }
        return [.color(PenFill.PenColorFill(color: color))]
    }

    /// Writes the overlay element with `styles` into `ctx`, at `indent`.
    static func emitStrokeOverlay(_ styles: [(String, String)], indent: Int, ctx: EmitContext) {
        let pad = String(repeating: " ", count: indent)
        ctx.lines.append("\(pad)<div")
        ctx.lines.append("\(pad)  aria-hidden=\"true\"")
        ctx.lines.append("\(pad)  style={{")
        for (key, value) in styles {
            ctx.lines.append("\(pad)    \(key): \(value),")
        }
        ctx.lines.append("\(pad)  }}")
        ctx.lines.append("\(pad)/>")
    }

    /// The overlay's corner radii: the node's, grown by the outset on each side, so the
    /// outer edge stays concentric with the node's corners. A sharp corner stays sharp,
    /// as a mitered stroke's is.
    private static func overlayRadius(_ shape: StrokeOverlayShape, outsets: EdgeLengths) -> String? {
        switch shape {
        case .ellipse:
            return "\"50%\""
        case .box(nil):
            return nil
        case let .box(.uniform(value)?):
            if value.literalValue == 0 { return nil }
            let radius = SymbolicLength(value)
            if outsets.isUniform {
                let grown = radius + outsets.top
                return grown.literalPoints.map { cssNumber($0) } ?? "\"\(grown.css)\""
            }
            return cornerRadii([radius, radius, radius, radius], outsets: outsets)
        case let .box(.perCorner(topLeft, topRight, bottomRight, bottomLeft)?):
            return cornerRadii([topLeft, topRight, bottomRight, bottomLeft].map(SymbolicLength.init), outsets: outsets)
        }
    }

    /// Per-corner radii (top-left, top-right, bottom-right, bottom-left), each grown by the
    /// outsets of the two sides it joins — elliptical where those differ.
    private static func cornerRadii(_ radii: [SymbolicLength], outsets: EdgeLengths) -> String {
        let horizontalSides = [outsets.left, outsets.right, outsets.right, outsets.left]
        let verticalSides = [outsets.top, outsets.top, outsets.bottom, outsets.bottom]
        let grow = { (sides: [SymbolicLength]) in
            zip(radii, sides).map { radius, side in radius.isZero ? radius : radius + side }
        }
        let horizontal = grow(horizontalSides)
        let vertical = grow(verticalSides)
        let list = { (lengths: [SymbolicLength]) in lengths.map(\.css).joined(separator: " ") }
        return horizontal == vertical
            ? "\"\(list(horizontal))\""
            : "\"\(list(horizontal)) / \(list(vertical))\""
    }
}
