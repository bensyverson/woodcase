//
//  PenRendererBlendTests.swift
//  Woodcase
//

import CoreGraphics
import Testing
@testable import Woodcase

/// The reference renderer composites blend modes as W3C Compositing and Blending Level 1
/// does — `co = αs·(1 − αb)·Cs + αs·αb·B(Cb, Cs) + (1 − αs)·αb·Cb` — over opaque and
/// translucent backdrops, from opaque and translucent sources. Linear burn and linear dodge
/// are Photoshop's `max(0, Cb + Cs − 1)` and `min(1, Cb + Cs)` (Ben's ruling, 2026-10-20).
///
/// Expected colors are that formula on the 8-bit inputs, rounded; the pixel is read
/// un-premultiplied, and each channel may be one step off for rounding. The pen CLI
/// (2026-10-20) draws the soft light, color dodge, color burn and non-separable cases
/// here the same; it draws linear burn as multiply and linear dodge as a plus operator,
/// which the ruling sets aside.
struct PenRendererBlendTests {
    private static let size = CGSize(width: 10, height: 10)
    private static let box = PenRect(x: 0, y: 0, width: 10, height: 10)

    /// A 10-point rectangle filled with `fill`, blended by `blendMode` and faded by `opacity`.
    private static func rect(
        _ id: String, _ fill: PenFill, blendMode: PenBlendMode? = nil, opacity: Double? = nil
    ) -> PenNode {
        var node = PenNode(
            id: id, common: PenNodeCommon(opacity: opacity.map { .literal($0) }),
            kind: .rectangle(PenNode.RectangleData(fills: .single(fill)))
        )
        node.blendMode = blendMode
        return node
    }

    /// A color fill blended by `mode`.
    private static func fill(_ color: String, _ mode: PenBlendMode? = nil) -> PenFill {
        .color(PenFill.PenColorFill(blendMode: mode, color: .literal(color)))
    }

    /// The center pixel of `nodes`, every one placed over the whole canvas unless `rects`
    /// says otherwise.
    private static func render(_ nodes: [PenNode], rects: [String: PenRect] = [:]) throws -> PixelGrid.RGBA {
        var placed = rects
        func place(_ node: PenNode) {
            if placed[node.id] == nil { placed[node.id] = box }
            if case let .frame(data) = node.kind { data.children?.forEach(place) }
        }
        nodes.forEach(place)
        let image = try #require(PenRenderer.render(
            PenDocument(version: "2.20", children: nodes), layoutRects: placed, size: size
        ))
        return try #require(PixelGrid(image)).pixel(5, 5)
    }

    /// `source` filled with `mode` over a `backdrop` fill beneath it on the same node — a
    /// paint-level blend, which blends only within its node's paint stack (Ben's reading-1
    /// ruling, 2026-10-20; `PenRendererPaintIsolationTests`).
    private static func fillBlend(_ mode: PenBlendMode, _ source: String, over backdrop: String) throws -> PixelGrid.RGBA {
        try render([stack("src", [fill(backdrop), fill(source, mode)])])
    }

    /// A 10-point rectangle painted by `fills`, bottom first.
    private static func stack(_ id: String, _ fills: [PenFill]) -> PenNode {
        PenNode(id: id, common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData(fills: .multiple(fills))))
    }

    /// `source` as a node blended by `mode` over a `backdrop` rectangle.
    private static func nodeBlend(
        _ mode: PenBlendMode, _ source: String, over backdrop: String, opacity: Double? = nil
    ) throws -> PixelGrid.RGBA {
        try render([rect("bd", fill(backdrop)), rect("src", fill(source), blendMode: mode, opacity: opacity)])
    }

    private static func expectColor(
        _ pixel: PixelGrid.RGBA, _ hex: String, alpha: Int = 255,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let expected = PenHexColor(hex)!
        let close = abs(pixel.r - Int(expected.red)) <= 1 && abs(pixel.g - Int(expected.green)) <= 1
            && abs(pixel.b - Int(expected.blue)) <= 1 && abs(pixel.a - alpha) <= 1
        #expect(close, "got \(pixel), expected \(hex) at alpha \(alpha)", sourceLocation: sourceLocation)
    }

    // MARK: - Soft light

    /// Cb = (230, 153, 77)/255, Cs = (51, 102, 255)/255. Red and green, Cs ≤ 0.5:
    /// Cb − (1 − 2·Cs)·Cb·(1 − Cb) → 216, 141. Blue, Cs = 1 > 0.5 and Cb > 0.25:
    /// Cb + (√Cb − Cb) = √0.302 → 140. Core Graphics' own soft light gives blue 131.
    @Test func `Soft light over an opaque backdrop is W3C's`() throws {
        try Self.expectColor(Self.fillBlend(.softLight, "#3366FF", over: "#E6994D"), "#D88D8C")
    }

    /// αb = 0.4: co = 0.6·Cs + 0.4·B(Cb, Cs), with B from the opaque case
    /// → (117, 118, 209).
    @Test func `Soft light over a translucent backdrop weighs the blend by its alpha`() throws {
        try Self.expectColor(Self.fillBlend(.softLight, "#3366FF", over: "#E6994D66"), "#7576D1")
    }

    /// Cb = 26/255 ≤ 0.25, Cs = 0.8: D = ((16·Cb − 12)·Cb + 4)·Cb = 0.33,
    /// B = Cb + 0.6·(D − Cb) = 0.22 → 56. Core Graphics gives 40, Photoshop's √Cb 59.
    @Test func `Soft light over a dark backdrop takes W3C's polynomial`() throws {
        try Self.expectColor(Self.fillBlend(.softLight, "#CCCCCC", over: "#1A1A1A"), "#383838")
    }

    @Test func `Soft light as a node's blend mode is W3C's`() throws {
        try Self.expectColor(Self.nodeBlend(.softLight, "#3366FF", over: "#E6994D"), "#D88D8C")
    }

    // MARK: - Color dodge and burn

    /// αb = 0.4: B = min(1, Cb/(1 − Cs)) = (1, 1, 1) here, so co = 0.6·Cs + 0.4
    /// → (133, 163, 255). Core Graphics gives red 146.
    @Test func `Color dodge over a translucent backdrop weighs the blend by its alpha`() throws {
        try Self.expectColor(Self.fillBlend(.colorDodge, "#3366FF", over: "#E6994D66"), "#85A3FF")
    }

    /// αs = 0.5 over opaque: co = 0.5·B + 0.5·Cb with B = (1, 1, 1) → (243, 204, 166).
    /// Core Graphics gives blue 255.
    @Test func `Color dodge from a translucent source mixes the blend by its alpha`() throws {
        try Self.expectColor(Self.fillBlend(.colorDodge, "#3366FF80", over: "#E6994D"), "#F3CCA6")
    }

    /// αs = 0.4 over opaque (26, 51, 230): B = (0, 1 − min(1, 0.8/0.9), 0) = (0, 0.111, 0),
    /// co = 0.4·B + 0.6·Cb → (16, 42, 138). Core Graphics gives (0, 42, 0).
    @Test func `Color burn from a translucent source mixes the blend by its alpha`() throws {
        try Self.expectColor(Self.fillBlend(.colorBurn, "#00E60066", over: "#1A33E6"), "#102A8A")
    }

    // MARK: - Linear burn and dodge

    /// max(0, Cb + Cs − 1) = (26, 0, 77) — not multiply's (46, 61, 77), which Pen draws.
    @Test func `Linear burn over an opaque backdrop is a true linear burn`() throws {
        try Self.expectColor(Self.fillBlend(.linearBurn, "#3366FF", over: "#E6994D"), "#1A004D")
    }

    /// Cs = (128, 179, 255) over (0, 26, 179) at αb = 0.4: B = (0, 0, 0.702),
    /// co = 0.6·Cs + 0.4·B → (77, 107, 225). Core Graphics' plus-darker gives red 26.
    @Test func `Linear burn over a translucent backdrop weighs the blend by its alpha`() throws {
        try Self.expectColor(Self.fillBlend(.linearBurn, "#80B3FF", over: "#001AB366"), "#4D6BE1")
    }

    /// min(1, Cb + Cs) = (1, 1, 1) — not screen's (235, 194, 255).
    @Test func `Linear dodge over an opaque backdrop is an add`() throws {
        try Self.expectColor(Self.fillBlend(.linearDodge, "#3366FF", over: "#E6994D"), "#FFFFFF")
    }

    /// αb = 0.4: co = 0.6·Cs + 0.4·(1, 1, 1) → (133, 163, 255). Core Graphics' plus-lighter
    /// and Pen give red 143.
    @Test func `Linear dodge over a translucent backdrop weighs the blend by its alpha`() throws {
        try Self.expectColor(Self.fillBlend(.linearDodge, "#3366FF", over: "#E6994D66"), "#85A3FF")
    }

    /// αs = 0.5 over αb = 0.4: αo = 0.5 + 0.4·0.5 = 0.7 → 179, and
    /// co = 0.5·0.6·Cs + 0.5·0.4·(1, 1, 1) + 0.5·0.4·Cb → (160, 160, 204) un-premultiplied.
    /// A plus operator sums the alphas to 230.
    @Test func `Linear dodge keeps source-over's alpha`() throws {
        try Self.expectColor(Self.fillBlend(.linearDodge, "#3366FF80", over: "#E6994D66"), "#A0A0CC", alpha: 179)
    }

    // MARK: - Non-separable modes

    /// SetSat((0, 0, 0.2), Sat(Cs) = 0.4) = (0, 0, 0.4); SetLum to Lum(Cb) = 0.022 gives
    /// (−0.022, −0.022, 0.378), which ClipColor pulls to (0, 0, 0.2) → 51. Core Graphics gives 46.
    @Test func `Saturation is W3C's`() throws {
        try Self.expectColor(Self.fillBlend(.saturation, "#4D801A", over: "#000033"), "#000033")
    }

    /// SetLum(Cb = (0, 0, 0.902), Lum(Cs) = 0.0866) = ClipColor(−0.013, −0.013, 0.889)
    /// → (0, 0, 216). Core Graphics gives 221.
    @Test func `Luminosity is W3C's`() throws {
        try Self.expectColor(Self.fillBlend(.luminosity, "#001A4D", over: "#0000E6"), "#0000D8")
    }

    /// SetLum(Cs = (0.302, 0.102, 1), Lum(Cb) = 0.0451) = ClipColor(…) → (20, 0, 92).
    /// Core Graphics gives (24, 0, 97).
    @Test func `Color is W3C's`() throws {
        try Self.expectColor(Self.fillBlend(.color, "#4D1AFF", over: "#1A004D"), "#14005C")
    }

    // MARK: - Node compositing

    /// A node's blend applies with its opacity: αs = 0.5, co = 0.5·Cb·Cs + 0.5·Cb
    /// → (138, 107, 77). Opacity alone would give (140, 128, 166).
    @Test func `A translucent node still blends`() throws {
        try Self.expectColor(Self.nodeBlend(.multiply, "#3366FF", over: "#E6994D", opacity: 0.5), "#8A6B4D")
    }

    /// The same for a mode drawn per pixel: co = 0.5·B + 0.5·Cb → (223, 147, 109).
    @Test func `A translucent node blends per pixel too`() throws {
        try Self.expectColor(Self.nodeBlend(.softLight, "#3366FF", over: "#E6994D", opacity: 0.5), "#DF936D")
    }

    /// A blended frame composites its contents as one group, as W3C's `mix-blend-mode`
    /// does: inside the frame the green child covers the blue one normally, and only the
    /// result multiplies the backdrop — (51, 204, 102)·(230, 153, 77)/255 → (46, 122, 31).
    /// Blending each child on its own multiplies green over blue over the backdrop.
    @Test func `A blended frame blends its contents as a group`() throws {
        var frame = PenNode(id: "grp", common: PenNodeCommon(), kind: .frame(PenNode.FrameData(
            layout: PenLayoutDirection.none,
            children: [Self.rect("blue", Self.fill("#3366FF")), Self.rect("green", Self.fill("#33CC66"))]
        )))
        frame.blendMode = .multiply
        try Self.expectColor(Self.render([Self.rect("bd", Self.fill("#E6994D")), frame]), "#2E7A1F")
    }

    /// A soft-light fill inside a frame at 50% opacity blends against the fill beneath it,
    /// inside the frame's group: B(#E6994D, #3366FF) = #D88D8C, then the group is drawn at
    /// half alpha over the empty canvas.
    @Test func `A per-pixel blend inside a translucent frame blends inside the frame`() throws {
        let frame = PenNode(
            id: "grp", common: PenNodeCommon(opacity: .literal(0.5)),
            kind: .frame(PenNode.FrameData(
                layout: PenLayoutDirection.none,
                children: [Self.stack("src", [Self.fill("#E6994D"), Self.fill("#3366FF", .softLight)])]
            ))
        )
        try Self.expectColor(Self.render([frame]), "#D88D8C", alpha: 128)
    }

    /// Outside the blended node the backdrop is untouched.
    @Test func `A per-pixel blend leaves the backdrop around the node`() throws {
        let image = try #require(PenRenderer.render(
            PenDocument(version: "2.20", children: [
                Self.rect("bd", Self.fill("#E6994D66")),
                Self.stack("src", [Self.fill("#E6994D66"), Self.fill("#3366FF", .softLight)]),
            ]),
            layoutRects: ["bd": Self.box, "src": PenRect(x: 0, y: 0, width: 4, height: 10)], size: Self.size
        ))
        let grid = try #require(PixelGrid(image))
        Self.expectColor(grid.pixel(8, 5), "#E6994D", alpha: 102)
        Self.expectColor(grid.pixel(1, 5), "#7576D1")
    }

    /// The same above and below: the layer finds the node's rows, which run down from the
    /// bitmap's top while Core Graphics' device space runs up from its bottom.
    @Test func `A per-pixel blend finds the node's rows`() throws {
        let image = try #require(PenRenderer.render(
            PenDocument(version: "2.20", children: [
                Self.rect("bd", Self.fill("#E6994D66")),
                Self.stack("src", [Self.fill("#E6994D66"), Self.fill("#3366FF", .softLight)]),
            ]),
            layoutRects: ["bd": Self.box, "src": PenRect(x: 0, y: 0, width: 10, height: 4)], size: Self.size
        ))
        let grid = try #require(PixelGrid(image))
        Self.expectColor(grid.pixel(5, 1), "#7576D1")
        Self.expectColor(grid.pixel(5, 8), "#E6994D", alpha: 102)
    }
}
