//
//  ReactEmitter+IconPaint.swift
//  Woodcase
//

extension ReactEmitter {
    /// What paints an icon's glyph.
    enum IconPaint: Friendly {
        /// A CSS colour, passed as the component's `color` prop.
        case color(String)

        /// A paint server: `attribute="url(#…)"` on the component, naming a definition in
        /// `definitions`, which go in a hidden `<svg>` beside it.
        case server(attribute: String, reference: String, definitions: [String])
    }

    /// The paint of an icon of `family` whose fills are `fills`.
    ///
    /// Pen paints the topmost enabled fill over the others, and lays a gradient or an image
    /// out over the node's box, drawing it through the glyph (`render-text-unfilled.pen`,
    /// the `gradient` and `image` boards). So the topmost enabled fill the emitter can
    /// write decides: a solid is the `color` prop, by `glyphColor(_:)`;
    /// a gradient, an image or a mesh is an SVG paint server (``svgPaint(_:index:shape:overhang:defs:ctx:)``)
    /// laid out over the component's `viewBox` — which the component scales onto the
    /// node's box — and set on the attribute the library paints its glyph with
    /// (``IconLibraryMapping/Glyph``). A paint that cannot be written — a shader, an
    /// angular gradient — is passed over for the one beneath it; with none left, the icon is
    /// ``noGlyphPaint``, as Pen draws an unfilled icon.
    ///
    /// - Parameters:
    ///   - fills: The icon's fills.
    ///   - family: The icon's library.
    ///   - nodeID: The node's id, which keeps its paint servers' ids apart from others'.
    ///   - ctx: The emission context, for a mesh.
    static func iconPaint(_ fills: PenFills?, family: String, nodeID: String, ctx: EmitContext) -> IconPaint {
        let glyph = IconLibraryMapping.glyph(for: family)
        for (index, fill) in (fills?.all ?? []).enumerated().reversed() where fill.isEnabled {
            if let color = fill.solidColor {
                return .color(glyphColor(color))
            }
            guard let glyph else { continue }
            let shape = SVGStrokedShape(
                element: "path", geometry: "", fill: nil, fillRule: nil, domain: glyph.viewBox, nodeID: nodeID
            )
            var definitions: [String] = []
            if let paint = svgPaint(fill, index: index, shape: shape, overhang: 0, defs: &definitions, ctx: ctx) {
                return .server(attribute: glyph.paintAttribute, reference: paint, definitions: definitions)
            }
        }
        return .color(noGlyphPaint)
    }

    /// The lines of a hidden, zero-size `<svg>` holding `definitions`: absolutely placed, so
    /// it takes no room in its parent's layout, and not `display: none`, which would stop a
    /// browser painting from the servers inside it.
    static func hiddenDefinitions(_ definitions: [String], pad: String) -> [String] {
        ["\(pad)<svg width={0} height={0} aria-hidden=\"true\" style={{ position: \"absolute\" }}>", "\(pad)  <defs>"]
            + definitions.map { "\(pad)    \($0)" }
            + ["\(pad)  </defs>", "\(pad)</svg>"]
    }
}
