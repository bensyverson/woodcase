//
//  ReactEmitterImageCropTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How the React emitter places an image paint by its mode and crops it by its `transform`
/// (format 2.20, `project/2026-10-03-pen-1.2.15-format-2.20.md`).
///
/// An uncropped paint stays a CSS background. A cropped one needs the image's own aspect,
/// which only the running page knows, so it is drawn by the generated `PenImageCrop`
/// (`lib/PenImageCrop.tsx`) in a layer of its own: over the fills beneath it, under the
/// fills above it, the node's inner strokes and shadows, and its children.
struct ReactEmitterImageCropTests {
    // MARK: - Helpers

    /// Every file emitted for a `Card` component holding one child node, given as JSON.
    private func files(child: String) throws -> [GeneratedFile] {
        let document = try PenParser.parse("""
        {"version": "2.20",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [\(child)]}]}
        """)
        return ReactEmitter.emit(
            document: document,
            components: ComponentAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document)
        ).files
    }

    /// The emitted `Card` component holding `child`.
    private func card(child: String) throws -> String {
        try #require(files(child: child).first { $0.path == "components/Card.tsx" }).content
    }

    /// A 200 × 120 rectangle filled with `fill`, plus anything in `extra`.
    private func rectangle(fill: String, extra: String = "") throws -> String {
        try card(child: ##"{"type": "rectangle", "id": "Rect1", "name": "Box", "width": 200, "height": 120, "fill": \##(fill)\##(extra)}"##)
    }

    /// An image paint of `./images/uv.png` with `mode` (none when `nil`) and `transform`.
    private static func image(mode: String? = nil, transform: String? = nil, extra: String = "") -> String {
        var fields = [##""type": "image""##, ##""url": "./images/uv.png""##]
        if let mode { fields.append(##""mode": "\##(mode)""##) }
        if let transform { fields.append(##""transform": \##(transform)"##) }
        return "{" + (fields + (extra.isEmpty ? [] : [extra])).joined(separator: ", ") + "}"
    }

    private static let rightHalf = "[2, 0, 0, 1, -1, 0]"

    // MARK: - Uncropped paints

    @Test("An uncropped paint stays a background sized by its mode", arguments: [
        ("stretch", "100% 100%"), ("cover", "cover"), ("contain", "contain"), ("fill", "cover"), ("fit", "contain"),
    ])
    func uncroppedStaysBackground(mode: String, size: String) throws {
        let content = try rectangle(fill: Self.image(mode: mode))
        #expect(content.contains(##"backgroundImage: "url('./images/uv.png')","##))
        #expect(content.contains(##"backgroundSize: "\##(size)","##))
        #expect(!content.contains("PenImageCrop"))
    }

    @Test("An uncropped paint with no mode is cover")
    func missingModeIsCover() throws {
        #expect(try rectangle(fill: Self.image()).contains(##"backgroundSize: "cover","##))
    }

    @Test("An uncropped paint is drawn once, never tiled: contain leaves the rest of the box empty")
    func uncroppedDoesNotRepeat() throws {
        let content = try rectangle(fill: Self.image(mode: "contain"))
        #expect(content.contains(##"backgroundRepeat: "no-repeat","##))
    }

    // MARK: - Cropped paints

    @Test("A cropped paint is drawn by PenImageCrop with its placement and crop", arguments: ["stretch", "contain"])
    func croppedUsesHelper(mode: String) throws {
        let content = try rectangle(fill: Self.image(mode: mode, transform: Self.rightHalf))
        #expect(content.contains(##"<PenImageCrop href="./images/uv.png" placement="\##(mode)" crop={[2, 0, 0, 1, -1, 0]} />"##), "\(content)")
        #expect(!content.contains("backgroundImage"))
        #expect(content.contains(##"import { PenImageCrop } from "../lib/PenImageCrop";"##))
    }

    @Test("A cropped paint with no mode is placed as cover")
    func croppedMissingModeIsCover() throws {
        let content = try rectangle(fill: Self.image(transform: "[2, 0, 0, 2, -0.5, -0.5]"))
        #expect(content.contains(##"placement="cover" crop={[2, 0, 0, 2, -0.5, -0.5]}"##), "\(content)")
    }

    @Test("A cover crop is written already kept inside the image")
    func coverCropKeptInside() throws {
        // The window spans u 0.6–1.27; kept inside, it spans 0.33–1, so tx becomes -0.5.
        let content = try rectangle(fill: Self.image(mode: "cover", transform: "[1.5, 0, 0, 1.5, -0.9, -0.25]"))
        #expect(content.contains(##"crop={[1.5, 0, 0, 1.5, -0.5, -0.25]}"##), "\(content)")
    }

    @Test("A singular crop draws nothing")
    func singularCropDrawsNothing() throws {
        let content = try rectangle(fill: Self.image(mode: "contain", transform: "[1, 1, 1, 1, 0, 0]"))
        #expect(!content.contains("PenImageCrop"))
        #expect(!content.contains("backgroundImage"))
    }

    @Test("The crop's layer clips to the node's shape and carries the paint's opacity")
    func layerClipsAndFades() throws {
        let content = try rectangle(fill: Self.image(mode: "contain", transform: Self.rightHalf, extra: ##""opacity": 0.5"##))
        #expect(content.contains(##"overflow: "hidden","##))
        #expect(content.contains(##"borderRadius: "inherit","##))
        #expect(content.contains("opacity: 0.5,"))
        #expect(content.contains(##"position: "relative","##))
    }

    @Test("Fills beneath a crop stay the node's background; fills above it are layers over it")
    func stackSplitsAtTheCrop() throws {
        let fills = "[\"#112233\", \(Self.image(mode: "contain", transform: Self.rightHalf)), \"#44556680\"]"
        let content = try rectangle(fill: fills)
        #expect(content.contains(##"backgroundColor: "#112233","##), "\(content)")
        let crop = try #require(content.range(of: "<PenImageCrop"))
        let above = try #require(content.range(of: ##"backgroundColor: "#44556680","##))
        #expect(crop.lowerBound < above.lowerBound)
    }

    @Test("An inner stroke and inner shadow are drawn over a cropped fill, not under it")
    func insetShadowsRideAboveTheCrop() throws {
        let content = try rectangle(
            fill: Self.image(mode: "contain", transform: Self.rightHalf),
            extra: ##", "stroke": "#FF0000", "strokeWidth": 4, "strokeAlignment": "inner""##
        )
        let crop = try #require(content.range(of: "<PenImageCrop"))
        let stroke = try #require(content.range(of: ##"boxShadow: "inset 0 0 0 4px #FF0000","##), "\(content)")
        #expect(crop.lowerBound < stroke.lowerBound)
    }

    @Test("A frame's crop layer sits beneath its children, which the frame isolates")
    func frameLayerBeneathChildren() throws {
        let content = try card(child: """
        {"type": "frame", "id": "Pic1", "name": "Pic", "width": 200, "height": 120,
         "fill": \(Self.image(mode: "cover", transform: Self.rightHalf)),
         "children": [{"type": "rectangle", "id": "Dot1", "width": 10, "height": 10, "fill": "#FFFFFF"}]}
        """)
        #expect(content.contains("zIndex: -1,"), "\(content)")
        #expect(content.contains(##"isolation: "isolate","##))
    }

    @Test("A CSS ellipse's crop layer follows its outline")
    func ellipseLayer() throws {
        let content = try card(child: """
        {"type": "ellipse", "id": "Oval1", "width": 200, "height": 120, "fill": \(Self.image(mode: "contain", transform: Self.rightHalf))}
        """)
        #expect(content.contains("<PenImageCrop"), "\(content)")
        #expect(content.contains(##"borderRadius: "inherit","##))
    }

    @Test("A cropped stroke paint is drawn by PenImageCrop inside the stroke overlay")
    func croppedStroke() throws {
        let content = try rectangle(
            fill: "\"#333333\"",
            extra: ##", "stroke": \##(Self.image(mode: "cover", transform: "[2, 0, 0, 2, -0.5, -0.5]")), "strokeWidth": 16, "strokeAlignment": "outer""##
        )
        #expect(content.contains("WebkitMask"))
        #expect(content.contains(##"<PenImageCrop href="./images/uv.png" placement="cover" crop={[2, 0, 0, 2, -0.5, -0.5]} />"##), "\(content)")
    }

    @Test("A cropped paint on an SVG shape is drawn by PenImageCrop inside its pattern")
    func croppedSVGPattern() throws {
        let content = try card(child: """
        {"type": "polygon", "id": "Poly1", "width": 40, "height": 40, "polygonCount": 6,
         "fill": \(Self.image(mode: "contain", transform: Self.rightHalf))}
        """)
        #expect(content.contains("<pattern id=\"wc-paint-"), "\(content)")
        #expect(content.contains(##"<PenImageCrop href="./images/uv.png" placement="contain" crop={[2, 0, 0, 1, -1, 0]} frame={["##), "\(content)")
    }

    @Test("A cropped paint on text is drawn uncropped, and generating it warns")
    func croppedTextWarns() throws {
        let document = try PenParser.parse("""
        {"version": "2.20",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [{"type": "text", "id": "Txt1", "content": "Hi", "fill": \(Self.image(mode: "cover", transform: Self.rightHalf))}]}]}
        """)
        let diagnostics = PenDiagnosticCollector()
        let files = ReactEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document), diagnostics: diagnostics
        ).files
        let content = try #require(files.first { $0.path == "components/Card.tsx" }).content
        #expect(content.contains("url('./images/uv.png')"))
        #expect(diagnostics.diagnostics.contains { $0.message.contains("crop") && $0.nodeID == "Txt1" })
    }

    // MARK: - The support file

    @Test("The support file is emitted only when a crop uses it")
    func supportFileOnlyWhenUsed() throws {
        let cropped = try files(child: ##"{"type": "rectangle", "id": "R1", "width": 20, "height": 20, "fill": \##(Self.image(mode: "contain", transform: Self.rightHalf))}"##)
        let support = try #require(cropped.first { $0.path == "lib/PenImageCrop.tsx" })
        #expect(support.content.contains("export function PenImageCrop("))
        let plain = try files(child: ##"{"type": "rectangle", "id": "R1", "width": 20, "height": 20, "fill": \##(Self.image(mode: "contain"))}"##)
        #expect(!plain.contains { $0.path == "lib/PenImageCrop.tsx" })
    }

    @Test("The harness inlines PenImageCrop and holds its ready signal until every crop has measured its image")
    func harnessWaitsForCrops() throws {
        let cropped = try files(child: ##"{"type": "rectangle", "id": "R1", "width": 20, "height": 20, "fill": \##(Self.image(mode: "contain", transform: Self.rightHalf))}"##)
        let html = ReactHarnessBuilder.buildHTML(from: cropped, componentName: "Card", viewportWidth: 200)
        #expect(html.contains("function PenImageCrop("))
        #expect(!html.contains("export function PenImageCrop("))
        #expect(html.contains(#"[data-pen-image="loading"]"#))
    }
}
