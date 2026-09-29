//
//  ReactEmitter+Mesh.swift
//  Woodcase
//

import Foundation

extension ReactEmitter {
    /// The side of a baked mesh raster, in pixels, for a box whose size is not fixed.
    ///
    /// The browser stretches the square over whatever box it lands in; a mesh gradient is
    /// low-frequency, so a smooth one loses little (`project/2026-09-26-mesh-gradients.md`
    /// §3 has the table). A fixed box is baked at ``Options/meshRasterScale`` instead, as a
    /// fold's or a transparent patch's edge steps at 64 px.
    static let meshRasterLongSide = 64

    /// The most pixels a baked mesh raster has on its long side, which keeps a very large
    /// box's `data:` URI in bounds: past it the raster is scaled down, proportionally.
    static let meshRasterMaximumSide = 1024

    /// What follows a mesh raster in a CSS `background` layer: stretch it over the box.
    static let meshLayerPlacement = " center / 100% 100% no-repeat"

    /// The CSS `background` layer that paints a mesh gradient fill, or `nil` when Pen
    /// would not draw the fill (a missing field or a count that does not match the grid).
    ///
    /// The mesh is baked to a PNG `data:` URI by the pure-Swift mesh core, with the
    /// fill's own opacity folded into its alpha. When any color depends on a theme axis,
    /// the mesh is baked once per theme and the layer reads `var(--wc-mesh-…)`, which
    /// ``EmitContext/meshProperties`` records for `theme.css` to declare per theme.
    ///
    /// - Parameters:
    ///   - fill: The mesh fill, with its variables unresolved.
    ///   - box: The node's box, which sets the raster's proportions.
    ///   - ctx: The emission context: its theme manifest resolves variables, and it
    ///     collects any per-theme custom property.
    /// - Returns: A layer such as `url('data:…') center / 100% 100% no-repeat`.
    static func emitMeshLayer(
        _ fill: PenFill.PenMeshGradientFill,
        box: FillBox,
        ctx: EmitContext
    ) -> String? {
        emitMeshImage(fill, box: box, ctx: ctx).map { $0 + meshLayerPlacement }
    }

    /// The CSS image that paints a mesh gradient fill — `url('data:…')`, or
    /// `var(--wc-mesh-…)` when it changes with the theme — without the placement
    /// ``emitMeshLayer(_:box:ctx:)`` adds, for callers that size and place layers
    /// themselves. `nil` when Pen would not draw the fill.
    static func emitMeshImage(
        _ fill: PenFill.PenMeshGradientFill,
        box: FillBox,
        ctx: EmitContext
    ) -> String? {
        guard (try? PenMeshGrid(fill)) != nil else { return nil }
        let themes = MeshThemes.themes(for: fill, in: ctx.theme)
        let uris = themes.compactMap { theme in
            bakedMeshURI(
                MeshThemes.resolvedFill(fill, theme: theme.selection, in: ctx.theme),
                box: box, scale: ctx.options.meshRasterScale
            )
        }
        guard uris.count == themes.count, let first = uris.first else { return nil }
        guard themes.count > 1 else {
            return "url('\(first)')"
        }

        var hasher = FNV1aHasher()
        for uri in uris {
            hasher.combine(uri)
        }
        let name = "wc-mesh-\(hasher.hexString.prefix(12))"
        ctx.meshProperties[name] = ThemedCustomProperty(
            name: name,
            values: zip(themes, uris).map { theme, uri in
                ThemedCustomProperty.Value(conditions: theme.conditions, css: "url('\(uri)')")
            }
        )
        return "var(--\(name))"
    }

    /// Rasterizes a resolved mesh fill at `scale` pixels per point of `box` and encodes it
    /// as a PNG `data:` URI (see ``FillBox/meshRasterSize(scale:)``).
    static func bakedMeshURI(_ fill: PenFill.PenMeshGradientFill, box: FillBox, scale: Double) -> String? {
        guard let grid = try? PenMeshGrid(fill) else { return nil }
        let size = box.meshRasterSize(scale: scale)
        var raster = PenMeshRasterizer.rasterize(grid, width: size.width, height: size.height)
        let opacity = min(max(fill.opacity?.literalValue ?? 1, 0), 1)
        if opacity < 1 {
            // Premultiplied, so opacity scales every channel alike.
            raster = PenMeshRaster(
                width: raster.width,
                height: raster.height,
                pixels: raster.pixels.map { UInt8((Double($0) * opacity).rounded()) }
            )
        }
        return "data:image/png;base64," + raster.pngData().base64EncodedString()
    }
}
