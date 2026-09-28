//
//  ReactEmitterTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

struct ReactEmitterTests {
    // MARK: - Helpers

    /// Compare content against golden file, updating the golden file if UPDATE_GOLDEN=1.
    ///
    /// The comparison itself lives in ``GoldenFile``, which
    /// ``ReactEmitterPageGoldenTests`` shares.
    private func assertGolden(_ content: String, name: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        try GoldenFile.assert(content, name: name, sourceLocation: sourceLocation)
    }

    // MARK: - Unit Tests

    @Test("Emits one file per component")
    func emitsOneFilePerComponent() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(layout: .vertical))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files

        let componentFiles = files.filter { $0.path.starts(with: "components/") }
        #expect(componentFiles.count == 1)
        #expect(componentFiles[0].path == "components/Card.tsx")
    }

    @Test("Generated component has correct interface and function")
    func hasInterfaceAndFunction() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Widget", reusable: true, metadata: [
                    "type": "component",
                    "_props": .dictionary(["title": .string("Title")]),
                ]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "t1",
                            common: PenNodeCommon(name: "Title"),
                            kind: .text(PenNode.TextData(content: .literal("Hello")))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files

        let content = files[0].content
        #expect(content.contains("interface WidgetProps"))
        #expect(content.contains("export function Widget("))
        #expect(content.contains("title?: string;"))
    }

    // MARK: - Golden File

    // MARK: - Strokes

    @Test("Frame with inner stroke emits inset box-shadow (not border)")
    func frameInnerStroke() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    stroke: .single(.shorthand("$accent")),
                    strokeWidth: .uniform(.literal(8)),
                    strokeAlignment: .inner,
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        // Inside strokes must not use CSS border (which eats content space
        // with box-sizing: border-box). Instead use inset box-shadow, which
        // paints on top like the pixel renderer does.
        #expect(content.contains("boxShadow: \"inset 0 0 0 8px var(--accent)\""))
        #expect(!content.contains("border:"))
    }

    /// Was an `outline`, which WebKit draws nothing of around a 0×0 box where Pen draws a
    /// band (`render-stroke-bands`, leaf Mu4JsL); a spread box-shadow draws both.
    @Test("Frame with outer stroke emits a spread box-shadow")
    func frameOuterStroke() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    stroke: .single(.shorthand("#FF0000")),
                    strokeWidth: .uniform(.literal(3)),
                    strokeAlignment: .outer,
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("boxShadow: \"0 0 0 3px #FF0000\""))
        #expect(!content.contains("outline"))
    }

    /// Was a border per side, which moves the children where Pen's stroke does not
    /// (`render-inner-sides`, leaf Mu4JsL); now the per-side overlay every alignment uses.
    @Test("Frame with an inner per-side stroke draws it as an overlay, not borders")
    func framePerSideStroke() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    stroke: .single(.shorthand("$accent")),
                    strokeWidth: .perSide(PenStrokeWidth.Sides(top: .literal(3), right: nil, bottom: .literal(3), left: nil)),
                    strokeAlignment: .inner,
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("padding: \"3px 0 3px 0\""), "\(content)")
        #expect(content.contains("linear-gradient(var(--accent), var(--accent))"), "\(content)")
        #expect(!content.contains("borderTop"))
        #expect(!content.contains("borderBottom"))
    }

    @Test("A stroke width with no stroke paint emits no border")
    func strokeWithNoPaint() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    strokeWidth: .uniform(.literal(2)),
                    strokeAlignment: .inner,
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(!content.contains("border"))
    }

    @Test("Inner stroke + drop shadow combine into single boxShadow")
    func innerStrokePlusShadow() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    stroke: .single(.shorthand("#000")),
                    strokeWidth: .uniform(.literal(2)),
                    strokeAlignment: .inner,
                    effects: .single(.shadow(PenEffect.PenShadowEffect(
                        offset: PenEffect.PenOffset(x: .literal(0), y: .literal(4)),
                        blur: .literal(8),
                        color: .literal("rgba(0,0,0,0.2)")
                    ))),
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        // Both should be in a single boxShadow declaration
        // The stroke first: CSS paints the first shadow on top, and Pen draws the stroke over the shadow.
        #expect(content.contains("boxShadow: \"inset 0 0 0 2px #000, 0px 4px 8px rgba(0,0,0,0.2)\""))
        // Should only have one boxShadow key
        let count = content.components(separatedBy: "boxShadow:").count - 1
        #expect(count == 1)
    }

    @Test("Center stroke emits an inset and an outer box-shadow of half the width each (not border)")
    func centerStroke() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    stroke: .single(.shorthand("#000")),
                    strokeWidth: .uniform(.literal(4)),
                    strokeAlignment: .center,
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        // Pen centres the stroke on the edge; box-shadows straddle it without eating
        // content space.
        #expect(content.contains("boxShadow: \"inset 0 0 0 2px #000, 0 0 0 2px #000\""))
        #expect(!content.contains("border:"))
    }

    // MARK: - Clip + Absolute Positioning

    @Test("Frame with clip true emits overflow hidden")
    func frameClip() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    clip: .literal(true),
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("overflow: \"hidden\""))
    }

    @Test("Child with absolute position emits position absolute and left/top")
    func absoluteChild() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "child1",
                            common: PenNodeCommon(
                                name: "FAB",
                                x: .literal(16),
                                y: .literal(24),
                                layoutPosition: .absolute
                            ),
                            kind: .frame(PenNode.FrameData(layout: .vertical))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("position: \"absolute\""))
        #expect(content.contains("left: 16"))
        #expect(content.contains("top: 24"))
    }

    @Test("Parent of absolute child gets relative class")
    func absoluteParentRelative() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "child1",
                            common: PenNodeCommon(layoutPosition: .absolute),
                            kind: .frame(PenNode.FrameData(layout: .vertical))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("relative"))
    }

    @Test("Absolute child with variable x emits var reference")
    func absoluteVariablePosition() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "child1",
                            common: PenNodeCommon(
                                x: .variable("fab-x"),
                                layoutPosition: .absolute
                            ),
                            kind: .frame(PenNode.FrameData(layout: .vertical))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("left: \"var(--fab-x)\""))
    }

    @Test("Frame with layout none positions children absolutely")
    func layoutNone() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Toggle", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    width: .fixed(44),
                    height: .fixed(26),
                    cornerRadius: .uniform(.literal(13)),
                    fills: .single(.shorthand("#CCC")),
                    layout: PenLayoutDirection.none,
                    children: [
                        PenNode(
                            id: "thumb",
                            common: PenNodeCommon(x: .literal(20), y: .literal(2)),
                            kind: .ellipse(PenNode.EllipseData(
                                width: .fixed(22),
                                height: .fixed(22),
                                fills: .single(.shorthand("#FFF"))
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        // Parent should use position: relative, not flex layout
        #expect(content.contains("relative"))
        #expect(!content.contains("\"flex "))
        // Child should be absolutely positioned with left/top from x/y
        #expect(content.contains("position: \"absolute\""))
        #expect(content.contains("left: 20"))
        #expect(content.contains("top: 2"))
    }

    // MARK: - Polygons + SVG Shapes

    @Test("Polygon with 6 sides emits hexagon SVG")
    func polygonHexagon() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "p1",
                            common: PenNodeCommon(),
                            kind: .polygon(PenNode.PolygonData(
                                width: .fixed(40),
                                height: .fixed(40),
                                polygonCount: .literal(6),
                                fills: .single(.shorthand("$accent"))
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("<svg"))
        #expect(content.contains("<polygon"))
        #expect(content.contains("points="))
    }

    @Test("Polygon with 3 sides emits triangle SVG")
    func polygonTriangle() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "p1",
                            common: PenNodeCommon(),
                            kind: .polygon(PenNode.PolygonData(
                                width: .fixed(30),
                                height: .fixed(30),
                                polygonCount: .literal(3)
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("<polygon"))
        #expect(content.contains("points="))
    }

    @Test("Ellipse with innerRadius emits donut SVG")
    func ellipseDonut() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "e1",
                            common: PenNodeCommon(),
                            kind: .ellipse(PenNode.EllipseData(
                                width: .fixed(40),
                                height: .fixed(40),
                                innerRadius: .literal(0.4),
                                fills: .single(.shorthand("$accent"))
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("<svg"))
        #expect(content.contains("<path"))
    }

    @Test("Ellipse with sweepAngle emits arc SVG with correct orientation")
    func ellipseArc() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "e1",
                            common: PenNodeCommon(),
                            kind: .ellipse(PenNode.EllipseData(
                                width: .fixed(40),
                                height: .fixed(40),
                                sweepAngle: .literal(270),
                                fills: .single(.shorthand("#CCC"))
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("<svg"))
        #expect(content.contains("<path"))
        // A pie slice from the centre: out to 0° (east/right, (40, 20), not top-center),
        // then 270° counter-clockwise — the large arc, SVG sweep flag 0 — to (20, 40).
        #expect(content.contains("M20 20 L40 20 A20 20 0 1 0 20 40 Z"))
    }

    @Test("Path with geometry and fill emits SVG path")
    func pathSVG() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "path1",
                            common: PenNodeCommon(),
                            kind: .path(PenNode.PathData(
                                width: .fixed(24),
                                height: .fixed(24),
                                geometry: "M0 0L24 24",
                                fills: .single(.shorthand("#000"))
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("<svg"))
        #expect(content.contains("d=\"M0 0L24 24\""))
        #expect(content.contains("fill=\"#000\""))
    }

    @Test("Line with stroke emits SVG line")
    func lineSVG() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "l1",
                            common: PenNodeCommon(),
                            kind: .line(PenNode.LineData(
                                width: .fixed(100),
                                height: .fixed(1),
                                stroke: .single(.shorthand("#CCC")),
                                strokeWidth: .uniform(.literal(1))
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("<svg"))
        #expect(content.contains("<line"))
        #expect(content.contains("stroke=\"#CCC\""))
    }

    // MARK: - Transforms, Opacity, Blend Modes, Enabled

    @Test("Rotation 45 degrees emits transform rotate")
    func rotation() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "f1",
                            common: PenNodeCommon(rotation: .literal(45)),
                            kind: .frame(PenNode.FrameData(layout: .vertical))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("transform: \"rotate(-45deg)\""))
    }

    @Test("FlipX emits scaleX(-1) transform")
    func flipX() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "f1",
                            common: PenNodeCommon(flipX: .literal(true)),
                            kind: .frame(PenNode.FrameData(layout: .vertical))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("transform: \"scaleX(-1)\""))
    }

    @Test("Rotation + flipX combined into single transform")
    func rotationPlusFlip() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "f1",
                            common: PenNodeCommon(rotation: .literal(90), flipX: .literal(true)),
                            kind: .frame(PenNode.FrameData(layout: .vertical))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("transform: \"rotate(-90deg) scaleX(-1)\""))
    }

    @Test("Opacity 0.3 emits opacity style")
    func opacity() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "f1",
                            common: PenNodeCommon(opacity: .literal(0.3)),
                            kind: .frame(PenNode.FrameData(layout: .vertical))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("opacity: 0.3"))
    }

    @Test("Enabled false emits display none")
    func enabledFalse() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "f1",
                            common: PenNodeCommon(enabled: .literal(false)),
                            kind: .frame(PenNode.FrameData(layout: .vertical))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("display: \"none\""))
    }

    @Test("Blend mode multiply emits mixBlendMode")
    func blendModeMultiply() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    blendMode: .multiply,
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "t1",
                            common: PenNodeCommon(name: "Label"),
                            kind: .text(PenNode.TextData(content: .literal("Hi")))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("mixBlendMode: \"multiply\""))
    }

    // MARK: - Effects

    @Test("Inner shadow emits inset prefix in boxShadow")
    func innerShadow() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    effects: .single(.shadow(PenEffect.PenShadowEffect(
                        shadowType: .inner,
                        offset: PenEffect.PenOffset(x: .literal(0), y: .literal(2)),
                        blur: .literal(4),
                        color: .literal("rgba(0,0,0,0.1)")
                    ))),
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("inset 0px 2px 4px rgba(0,0,0,0.1)"))
    }

    @Test("Outer + inner shadow combined with comma")
    func combinedShadows() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    effects: .multiple([
                        .shadow(PenEffect.PenShadowEffect(
                            shadowType: .outer,
                            offset: PenEffect.PenOffset(x: .literal(0), y: .literal(4)),
                            blur: .literal(8),
                            color: .literal("rgba(0,0,0,0.2)")
                        )),
                        .shadow(PenEffect.PenShadowEffect(
                            shadowType: .inner,
                            offset: PenEffect.PenOffset(x: .literal(0), y: .literal(1)),
                            blur: .literal(2),
                            color: .literal("rgba(0,0,0,0.1)")
                        )),
                    ]),
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        // Inner shadows before outer since leaf 0M8jRo, the stroke's place first; the two
        // kinds do not overlap, so this order draws what the old one did.
        #expect(content.contains("inset 0px 1px 2px rgba(0,0,0,0.1), 0px 4px 8px rgba(0,0,0,0.2)"))
    }

    @Test("Blur effect emits filter style")
    func blurEffect() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    effects: .single(.blur(PenEffect.PenBlurEffect(radius: .literal(4)))),
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("filter: \"blur(2px)\""))
    }

    @Test("Background blur emits backdropFilter style")
    func backgroundBlurEffect() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    // A fill to blur through: since leaf 0M8jRo a node with none writes no
                    // backdrop-filter, as Pen draws none.
                    fills: .single(.shorthand("#FFFFFF80")),
                    effects: .single(.backgroundBlur(PenEffect.PenBackgroundBlurEffect(radius: .literal(8)))),
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("backdropFilter: \"blur(4px)\""))
        #expect(content.contains("WebkitBackdropFilter: \"blur(4px)\""))
    }

    @Test("Disabled effect is skipped")
    func disabledEffect() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    effects: .single(.shadow(PenEffect.PenShadowEffect(
                        enabled: .literal(false),
                        offset: PenEffect.PenOffset(x: .literal(0), y: .literal(4)),
                        blur: .literal(8),
                        color: .literal("#000")
                    ))),
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(!content.contains("boxShadow"))
    }

    // MARK: - Fills + Gradients

    @Test("Image fill with mode fill emits backgroundImage, cover, and center position")
    func imageFillCover() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    fills: .single(.image(PenFill.PenImageFill(url: "thumb.png", mode: .fill))),
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("backgroundImage: \"url('thumb.png')\""))
        #expect(content.contains("backgroundSize: \"cover\""))
        #expect(content.contains("backgroundPosition: \"center\""))
    }

    @Test("Linear gradient with 2 stops and rotation emits CSS gradient")
    func linearGradient() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    fills: .single(.gradient(PenFill.PenGradientFill(
                        gradientType: .linear,
                        rotation: .literal(45),
                        colors: [
                            PenFill.PenGradientStop(color: .literal("#FF0000"), position: .literal(0)),
                            PenFill.PenGradientStop(color: .literal("#0000FF"), position: .literal(1)),
                        ]
                    ))),
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        // .pen rotation increases counter-clockwise, so 45° points the ramp up and left. Pen
        // lays it out in the normalised box, where 45° is the box's diagonal whatever its
        // proportions — CSS's `to top left` — and its line is one unit long, shorter than
        // CSS's corner-to-corner line (ReactEmitterGradientGeometryTests).
        #expect(content.contains("linear-gradient(to top left, #FF0000 14.645%, #0000FF 85.355%)"))
    }

    @Test("Radial gradient emits CSS radial-gradient")
    func radialGradient() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    fills: .single(.gradient(PenFill.PenGradientFill(
                        gradientType: .radial,
                        colors: [
                            PenFill.PenGradientStop(color: .literal("#FFF"), position: .literal(0)),
                            PenFill.PenGradientStop(color: .literal("#000"), position: .literal(1)),
                        ]
                    ))),
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        // Pen's radial gradient touches the box's sides (radius ½ of the normalised box),
        // which is CSS's closest-side; CSS's default, farthest-corner, drew it √2 too large.
        #expect(content.contains("background: \"radial-gradient(closest-side, #FFF 0%, #000 100%)\""))
    }

    @Test("Angular gradient with 3 stops emits conic-gradient")
    func angularGradient() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    fills: .single(.gradient(PenFill.PenGradientFill(
                        gradientType: .angular,
                        colors: [
                            PenFill.PenGradientStop(color: .literal("#F00"), position: .literal(0)),
                            PenFill.PenGradientStop(color: .literal("#0F0"), position: .literal(0.5)),
                            PenFill.PenGradientStop(color: .literal("#00F"), position: .literal(1)),
                        ]
                    ))),
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("background: \"conic-gradient(#F00 0%, #0F0 50%, #00F 100%)\""))
    }

    @Test("Multiple fills with blend mode emit combined background")
    func multiFillWithBlend() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    fills: .multiple([
                        .shorthand("$accent"),
                        .gradient(PenFill.PenGradientFill(
                            blendMode: .overlay,
                            gradientType: .linear,
                            rotation: .literal(90),
                            colors: [
                                PenFill.PenGradientStop(color: .literal("#FFF"), position: .literal(0)),
                                PenFill.PenGradientStop(color: .literal("#000"), position: .literal(1)),
                            ]
                        )),
                    ]),
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("background:"))
        #expect(content.contains("backgroundBlendMode:"))
    }

    @Test("Disabled fill is skipped")
    func disabledFill() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    fills: .single(.color(PenFill.PenColorFill(
                        enabled: .literal(false),
                        color: .literal("#FF0000")
                    ))),
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(!content.contains("background"))
        #expect(!content.contains("#FF0000"))
    }

    // MARK: - Extended Text Properties

    @Test("Text with textAlign justify emits textAlign style")
    func textAlignJustify() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "t1",
                            common: PenNodeCommon(name: "Body"),
                            kind: .text(PenNode.TextData(
                                content: .literal("Hello"),
                                textAlign: .justify
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("textAlign: \"justify\""))
    }

    /// Changed with leaf 3Xbv46: it expected `lineHeight: 1.3`, a guess at Core Text's
    /// metrics. A text with no `lineHeight` is now set at Pen's natural pitch for its font,
    /// and this one names no family, so the browser's own line height stands.
    @Test("Text with nil lineHeight and no family emits the browser's normal line height")
    func defaultLineHeight() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "t1",
                            common: PenNodeCommon(name: "Label"),
                            kind: .text(PenNode.TextData(
                                content: .literal("Hello"),
                                fontSize: .literal(14)
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("lineHeight: \"normal\""))
    }

    @Test("Text with explicit lineHeight emits the specified value")
    func explicitLineHeight() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "t1",
                            common: PenNodeCommon(name: "Label"),
                            kind: .text(PenNode.TextData(
                                content: .literal("Hello"),
                                fontSize: .literal(14),
                                lineHeight: .literal(24)
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("lineHeight: 24"))
    }

    @Test("Text with underline and strikethrough emits combined textDecoration")
    func textDecorations() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "t1",
                            common: PenNodeCommon(name: "Body"),
                            kind: .text(PenNode.TextData(
                                content: .literal("Hello"),
                                underline: .literal(true),
                                strikethrough: .literal(true)
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("textDecoration: \"underline line-through\""))
    }

    @Test("Text with href emits anchor element")
    func textHref() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "t1",
                            common: PenNodeCommon(name: "Link"),
                            kind: .text(PenNode.TextData(
                                content: .literal("Click me"),
                                href: "https://example.com"
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("<a href=\"https://example.com\""))
        #expect(content.contains("Click me"))
        #expect(content.contains("</a>"))
    }

    @Test("Text with fontStyle italic emits fontStyle")
    func textFontStyleItalic() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "t1",
                            common: PenNodeCommon(name: "Body"),
                            kind: .text(PenNode.TextData(
                                content: .literal("Hello"),
                                fontStyle: .literal("italic")
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("fontStyle: \"italic\""))
    }

    @Test("Text with fixedWidth textGrowth emits width style")
    func textGrowthFixedWidth() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "t1",
                            common: PenNodeCommon(name: "Body"),
                            kind: .text(PenNode.TextData(
                                width: .fixed(200),
                                content: .literal("Hello"),
                                textGrowth: .fixedWidth
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("width: 200"))
    }

    @Test("Text emits its content in a paragraph, with no span children")
    func textEmitsNoSpans() {
        let doc = PenDocument(version: "2.17", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "t1",
                            common: PenNodeCommon(name: "Body"),
                            kind: .text(PenNode.TextData(
                                content: .literal("Bold Normal"),
                                fontWeight: .literal("700")
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(!content.contains("<span"))
        #expect(content.contains("fontWeight: 700"))
        #expect(content.contains("Bold Normal"))
    }

    // MARK: - Icons

    @Test("Icon bell emits Bell component")
    func iconBasic() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "i1",
                            common: PenNodeCommon(name: "Icon"),
                            kind: .icon(PenNode.IconData(
                                icon: .literal("bell"),
                                library: .literal("lucide"),
                                width: .fixed(18),
                                height: .fixed(18)
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("<Bell size={18}"))
        #expect(content.contains("import { Bell } from \"lucide-react\";"))
    }

    @Test("Icon with fill emits color prop")
    func iconColor() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "i1",
                            common: PenNodeCommon(),
                            kind: .icon(PenNode.IconData(
                                icon: .literal("heart"),
                                library: .literal("lucide"),
                                width: .fixed(24),
                                height: .fixed(24),
                                fills: .single(.shorthand("$accent"))
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("<Heart size={24} color=\"var(--accent)\""))
    }

    @Test("Multiple icons emit single import with all names")
    func iconMultiple() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "i1",
                            common: PenNodeCommon(),
                            kind: .icon(PenNode.IconData(
                                icon: .literal("bell"),
                                library: .literal("lucide"),
                                width: .fixed(18),
                                height: .fixed(18)
                            ))
                        ),
                        PenNode(
                            id: "i2",
                            common: PenNodeCommon(),
                            kind: .icon(PenNode.IconData(
                                icon: .literal("arrow-left"),
                                library: .literal("lucide"),
                                width: .fixed(18),
                                height: .fixed(18)
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        // Should have a single import with both names (sorted)
        #expect(content.contains("import { ArrowLeft, Bell } from \"lucide-react\";"))
    }

    @Test("Non-lucide icon emits comment placeholder")
    func iconNonLucide() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "i1",
                            common: PenNodeCommon(),
                            kind: .icon(PenNode.IconData(
                                icon: .literal("custom-icon"),
                                library: .literal("material"),
                                width: .fixed(18),
                                height: .fixed(18)
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("{/* unsupported icon family: material */}"))
    }

    // MARK: - Groups

    @Test("Group children are emitted absolutely positioned inside a relative container")
    func groupBasic() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "g1",
                            common: PenNodeCommon(name: "Group"),
                            kind: .group(PenNode.GroupData(
                                children: [
                                    PenNode(
                                        id: "t1",
                                        common: PenNodeCommon(name: "Label", x: .literal(4), y: .literal(8)),
                                        kind: .text(PenNode.TextData(content: .literal("Hello")))
                                    ),
                                ]
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        // The group itself is just a relative anchor — no flex classes.
        #expect(content.contains("className=\"relative\""))
        // The child is wrapped in its own absolutely positioned div at its own x/y.
        #expect(content.contains("position: \"absolute\""))
        #expect(content.contains("left: 4"))
        #expect(content.contains("top: 8"))
        #expect(content.contains("Hello"))
    }

    // MARK: - Rectangles + Ellipses

    @Test("Rectangle with fixed size and fill emits div with styles")
    func rectangleBasic() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Bar", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "r1",
                            common: PenNodeCommon(name: "Progress"),
                            kind: .rectangle(PenNode.RectangleData(
                                width: .fixed(100),
                                height: .fixed(4),
                                fills: .single(.shorthand("$accent"))
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("width: 100"))
        #expect(content.contains("height: 4"))
        #expect(content.contains("backgroundColor: \"var(--accent)\""))
    }

    @Test("Rectangle with corner radius emits borderRadius")
    func rectangleCornerRadius() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Bar", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "r1",
                            common: PenNodeCommon(),
                            kind: .rectangle(PenNode.RectangleData(
                                width: .fixed(80),
                                height: .fixed(8),
                                cornerRadius: .uniform(.literal(4)),
                                fills: .single(.shorthand("#CCC"))
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("borderRadius: 4"))
    }

    @Test("Rectangle with fill_container width emits 100%")
    func rectangleFillContainer() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Bar", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "r1",
                            common: PenNodeCommon(),
                            kind: .rectangle(PenNode.RectangleData(
                                width: .fillContainer(fallback: nil),
                                height: .fixed(1)
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("width: \"100%\""))
    }

    @Test("Ellipse with fixed size emits div with border-radius 50%")
    func ellipseBasic() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Dot", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "e1",
                            common: PenNodeCommon(),
                            kind: .ellipse(PenNode.EllipseData(
                                width: .fixed(8),
                                height: .fixed(8),
                                fills: .single(.shorthand("$accent"))
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("borderRadius: \"50%\""))
        #expect(content.contains("width: 8"))
        #expect(content.contains("height: 8"))
        #expect(content.contains("backgroundColor: \"var(--accent)\""))
    }

    // MARK: - Ref Instantiation

    @Test("Ref with no overrides emits bare component tag")
    func refNoOverrides() throws {
        let refNode = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "Component/Card"),
            kind: .ref(PenNode.RefData(ref: "comp1"))
        )
        let componentNode = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
            kind: .frame(PenNode.FrameData(layout: .vertical))
        )
        let doc = PenDocument(version: "2.9", children: [componentNode, refNode])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let cardFile = try #require(files.first { $0.path.contains("Card") })

        // The component itself shouldn't contain a ref to itself, but we verify bare tag emission
        #expect(cardFile.content.contains("Card"))
    }

    @Test("Ref with text override emits prop on component tag")
    func refWithTextOverride() throws {
        let titleText = PenNode(
            id: "V:title1",
            common: PenNodeCommon(name: "Title"),
            kind: .text(PenNode.TextData(content: .literal("Default")))
        )
        let componentNode = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: [
                "type": "component",
                "_props": .dictionary(["title": .string("Title")]),
            ]),
            kind: .frame(PenNode.FrameData(layout: .vertical, children: [titleText]))
        )
        let refNode = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "Component/Card"),
            kind: .ref(PenNode.RefData(
                ref: "comp1",
                descendants: [
                    "V:title1": PenDescendantOverride(properties: [
                        "content": .string("Custom Title"),
                    ]),
                ]
            ))
        )
        // Parent frame that contains the ref
        let pageNode = PenNode(
            id: "page1",
            common: PenNodeCommon(name: "Page", reusable: true, metadata: ["type": "component"]),
            kind: .frame(PenNode.FrameData(layout: .vertical, children: [refNode]))
        )
        let doc = PenDocument(version: "2.9", children: [componentNode, pageNode])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let pageFile = try #require(files.first { $0.path.contains("Page") })

        #expect(pageFile.content.contains("title=\"Custom Title\""))
    }

    @Test("Ref with multiple overrides emits all props")
    func refWithMultipleOverrides() throws {
        let titleText = PenNode(
            id: "V:title1",
            common: PenNodeCommon(name: "Title"),
            kind: .text(PenNode.TextData(content: .literal("Default")))
        )
        let subtitleText = PenNode(
            id: "V:sub1",
            common: PenNodeCommon(name: "Subtitle"),
            kind: .text(PenNode.TextData(content: .literal("Sub")))
        )
        let componentNode = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: [
                "type": "component",
                "_props": .dictionary([
                    "title": .string("Title"),
                    "subtitle": .string("Subtitle"),
                ]),
            ]),
            kind: .frame(PenNode.FrameData(layout: .vertical, children: [titleText, subtitleText]))
        )
        let refNode = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "Component/Card"),
            kind: .ref(PenNode.RefData(
                ref: "comp1",
                descendants: [
                    "V:title1": PenDescendantOverride(properties: ["content": .string("New Title")]),
                    "V:sub1": PenDescendantOverride(properties: ["content": .string("New Sub")]),
                ]
            ))
        )
        let pageNode = PenNode(
            id: "page1",
            common: PenNodeCommon(name: "Page", reusable: true, metadata: ["type": "component"]),
            kind: .frame(PenNode.FrameData(layout: .vertical, children: [refNode]))
        )
        let doc = PenDocument(version: "2.9", children: [componentNode, pageNode])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let pageFile = try #require(files.first { $0.path.contains("Page") })

        #expect(pageFile.content.contains("subtitle=\"New Sub\""))
        #expect(pageFile.content.contains("title=\"New Title\""))
    }

    // MARK: - Ref Root Overrides

    @Test("Ref with root overrides emits style prop")
    func refRootOverrides() throws {
        let componentNode = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
            kind: .frame(PenNode.FrameData(layout: .vertical))
        )
        let refNode = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "Component/Card"),
            kind: .ref(PenNode.RefData(
                ref: "comp1",
                descendants: nil,
                rootOverrides: [
                    "width": .double(200),
                    "height": .double(100),
                ]
            ))
        )
        let pageNode = PenNode(
            id: "page1",
            common: PenNodeCommon(name: "Page", reusable: true, metadata: ["type": "component"]),
            kind: .frame(PenNode.FrameData(layout: .vertical, children: [refNode]))
        )
        let doc = PenDocument(version: "2.9", children: [componentNode, pageNode])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let pageFile = try #require(files.first { $0.path.contains("Page") })

        #expect(pageFile.content.contains("style={{"))
        #expect(pageFile.content.contains("width: 200"))
        #expect(pageFile.content.contains("height: 100"))
    }

    @Test("Ref with combined root and descendant overrides emits both")
    func refCombinedOverrides() throws {
        let titleText = PenNode(
            id: "V:title1",
            common: PenNodeCommon(name: "Title"),
            kind: .text(PenNode.TextData(content: .literal("Default")))
        )
        let componentNode = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: [
                "type": "component",
                "_props": .dictionary(["title": .string("Title")]),
            ]),
            kind: .frame(PenNode.FrameData(layout: .vertical, children: [titleText]))
        )
        let refNode = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "Component/Card"),
            kind: .ref(PenNode.RefData(
                ref: "comp1",
                descendants: [
                    "V:title1": PenDescendantOverride(properties: ["content": .string("Override")]),
                ],
                rootOverrides: [
                    "width": .double(300),
                ]
            ))
        )
        let pageNode = PenNode(
            id: "page1",
            common: PenNodeCommon(name: "Page", reusable: true, metadata: ["type": "component"]),
            kind: .frame(PenNode.FrameData(layout: .vertical, children: [refNode]))
        )
        let doc = PenDocument(version: "2.9", children: [componentNode, pageNode])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let pageFile = try #require(files.first { $0.path.contains("Page") })

        #expect(pageFile.content.contains("title=\"Override\""))
        #expect(pageFile.content.contains("style={{"))
        #expect(pageFile.content.contains("width: 300"))
    }

    @Test("Ref with fill_container width emits flex style")
    func refFillContainerWidth() throws {
        let componentNode = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
            kind: .frame(PenNode.FrameData(layout: .vertical))
        )
        let refNode = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "Component/Card"),
            kind: .ref(PenNode.RefData(
                ref: "comp1",
                descendants: nil,
                rootOverrides: [
                    "width": .string("fill_container"),
                ]
            ))
        )
        let pageNode = PenNode(
            id: "page1",
            common: PenNodeCommon(name: "Page", reusable: true, metadata: ["type": "component"]),
            kind: .frame(PenNode.FrameData(layout: .vertical, children: [refNode]))
        )
        let doc = PenDocument(version: "2.9", children: [componentNode, pageNode])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let pageFile = try #require(files.first { $0.path.contains("Page") })

        // fill_container should map to a flex/width style
        #expect(pageFile.content.contains("style={{"))
    }

    // MARK: - Page Emission

    @Test("Page emits as tsx file in pages/ directory")
    func pageEmitsInPagesDir() {
        let componentNode = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
            kind: .frame(PenNode.FrameData(layout: .vertical))
        )
        let refNode = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "Card Instance"),
            kind: .ref(PenNode.RefData(ref: "comp1"))
        )
        let pageNode = PenNode(
            id: "page1",
            common: PenNodeCommon(name: "Home"),
            kind: .frame(PenNode.FrameData(layout: .vertical, children: [refNode]))
        )
        let doc = PenDocument(version: "2.9", children: [componentNode, pageNode])
        let components = ComponentAnalyzer.analyze(doc)
        let pages = PageAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, pages: pages, theme: theme).files
        let pageFile = files.first { $0.path.starts(with: "pages/") }

        #expect(pageFile != nil)
        #expect(pageFile?.path == "pages/Home.tsx")
    }

    @Test("Page imports referenced components")
    func pageImportsComponents() throws {
        let componentNode = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
            kind: .frame(PenNode.FrameData(layout: .vertical))
        )
        let refNode = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "Card Instance"),
            kind: .ref(PenNode.RefData(ref: "comp1"))
        )
        let pageNode = PenNode(
            id: "page1",
            common: PenNodeCommon(name: "Home"),
            kind: .frame(PenNode.FrameData(layout: .vertical, children: [refNode]))
        )
        let doc = PenDocument(version: "2.9", children: [componentNode, pageNode])
        let components = ComponentAnalyzer.analyze(doc)
        let pages = PageAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, pages: pages, theme: theme).files
        let pageFile = try #require(files.first { $0.path == "pages/Home.tsx" })

        #expect(pageFile.content.contains("import { Card } from \"../components/Card\";"))
    }

    /// A page declares no props of its own, but its root is emitted through the same
    /// `isRoot` path a component root takes — `className={cn(…, className)}` and
    /// `...style` — so it takes the same two optional members, and defaults them so
    /// `<Home />` still renders.
    @Test("Page has a props interface carrying only className and style")
    func pageHasOnlyTheRootPropsInterface() throws {
        let pageNode = PenNode(
            id: "page1",
            common: PenNodeCommon(name: "Home"),
            kind: .frame(PenNode.FrameData(layout: .vertical))
        )
        let doc = PenDocument(version: "2.9", children: [pageNode])
        let components: [ComponentDefinition] = []
        let pages = PageAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, pages: pages, theme: theme).files
        let pageFile = try #require(files.first { $0.path == "pages/Home.tsx" })

        #expect(pageFile.content.contains("interface HomeProps {"))
        #expect(pageFile.content.contains("  className?: string;"))
        #expect(pageFile.content.contains("  style?: React.CSSProperties;"))
        #expect(pageFile.content.contains("export function Home({ className, style }: HomeProps = {}) {"))
    }

    // MARK: - Theme & Utility Files

    @Test("ThemeProvider contains correct axes from manifest")
    func themeProviderAxes() throws {
        let theme = ThemeManifest(
            axes: [
                ThemeAxis(name: "mode", values: ["light", "dark"]),
                ThemeAxis(name: "density", values: ["default", "compact"]),
            ],
            variables: [],
            contextNodes: []
        )
        let doc = PenDocument(version: "2.9", children: [])

        let files = ReactEmitter.emit(document: doc, components: [], pages: [], theme: theme).files
        let provider = files.first { $0.path == "ThemeProvider.tsx" }

        #expect(provider != nil)
        #expect(try #require(provider?.content.contains("data-mode={mode}")))
        #expect(try #require(provider?.content.contains("data-density={density}")))
        #expect(try #require(provider?.content.contains("useState(\"light\")")))
        #expect(try #require(provider?.content.contains("useState(\"default\")")))
    }

    @Test("cn.ts utility is generated with correct content")
    func cnUtility() throws {
        let theme = ThemeManifest(axes: [], variables: [], contextNodes: [])
        let doc = PenDocument(version: "2.9", children: [])

        let files = ReactEmitter.emit(document: doc, components: [], pages: [], theme: theme).files
        let cn = files.first { $0.path == "lib/cn.ts" }

        #expect(cn != nil)
        #expect(try #require(cn?.content.contains("twMerge")))
        #expect(try #require(cn?.content.contains("clsx")))
        #expect(try #require(cn?.content.contains("export function cn")))
    }

    @Test("theme.css is included in output")
    func themeCssIncluded() throws {
        // The emitter measures the fonts it names: register them, whatever ran before.
        TestFontRegistration.registerTestFonts()
        let url = try #require(Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"))
        let doc = try PenParser.parse(contentsOf: url)
        let components = ComponentAnalyzer.analyze(doc)
        let pages = PageAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, pages: pages, theme: theme).files
        let css = files.first { $0.path == "theme.css" }

        #expect(css != nil)
        #expect(try !#require(css?.content.isEmpty))
    }

    // MARK: - Complete File Structure

    @Test("emit() returns complete file manifest with all file types")
    func completeFileManifest() {
        let componentNode = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
            kind: .frame(PenNode.FrameData(layout: .vertical))
        )
        let pageNode = PenNode(
            id: "page1",
            common: PenNodeCommon(name: "Home"),
            kind: .frame(PenNode.FrameData(layout: .vertical))
        )
        let doc = PenDocument(version: "2.9", children: [componentNode, pageNode])
        let components = ComponentAnalyzer.analyze(doc)
        let pages = PageAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, pages: pages, theme: theme).files
        let paths = Set(files.map(\.path))

        // Component
        #expect(paths.contains("components/Card.tsx"))
        // Page
        #expect(paths.contains("pages/Home.tsx"))
        // Utilities
        #expect(paths.contains("lib/cn.ts"))
        #expect(paths.contains("ThemeProvider.tsx"))
        #expect(paths.contains("theme.css"))
    }

    @Test("No generated files are empty in full fixture")
    func noEmptyFiles() throws {
        // The emitter measures the fonts it names: register them, whatever ran before.
        TestFontRegistration.registerTestFonts()
        let url = try #require(Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"))
        let doc = try PenParser.parse(contentsOf: url)
        let components = ComponentAnalyzer.analyze(doc)
        let pages = PageAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, pages: pages, theme: theme).files

        for file in files {
            #expect(!file.content.isEmpty, "File \(file.path) has empty content")
        }
    }

    @Test("Full fixture produces correct file count")
    func fullFixtureFileCount() throws {
        // The emitter measures the fonts it names: register them, whatever ran before.
        TestFontRegistration.registerTestFonts()
        let url = try #require(Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"))
        let doc = try PenParser.parse(contentsOf: url)
        let components = ComponentAnalyzer.analyze(doc)
        let pages = PageAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, pages: pages, theme: theme).files

        // 21 components + pages + utility files (cn.ts, ThemeProvider.tsx, theme.css, states.css, manifest.json)
        let componentCount = files.count(where: { $0.path.starts(with: "components/") })
        let utilityCount = files.count(where: { ["lib/cn.ts", "ThemeProvider.tsx", "theme.css"].contains($0.path) })
        #expect(componentCount == 18)
        #expect(utilityCount == 3)
    }

    // MARK: - Golden File

    @Test("Stat Card component emits correct TSX")
    func statCardGolden() throws {
        // The emitter measures the fonts it names: register them, whatever ran before.
        TestFontRegistration.registerTestFonts()
        let url = try #require(Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"))
        let doc = try PenParser.parse(contentsOf: url)
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let statCard = try #require(files.first { $0.path.contains("StatCard") })

        try assertGolden(statCard.content, name: "StatCard.tsx")
    }

    @Test("ScreenLab component emits correct TSX")
    func screenLabGolden() throws {
        // The emitter measures the fonts it names: register them, whatever ran before.
        TestFontRegistration.registerTestFonts()
        let url = try #require(Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"))
        let doc = try PenParser.parse(contentsOf: url)
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let file = try #require(files.first { $0.path.contains("ScreenLab") })

        try assertGolden(file.content, name: "ScreenLab.tsx")
    }

    @Test("PencilListItem component emits correct TSX")
    func pencilListItemGolden() throws {
        // The emitter measures the fonts it names: register them, whatever ran before.
        TestFontRegistration.registerTestFonts()
        let url = try #require(Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"))
        let doc = try PenParser.parse(contentsOf: url)
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let file = try #require(files.first { $0.path.contains("PencilListItem") })

        try assertGolden(file.content, name: "PencilListItem.tsx")
    }

    @Test("ActionButton component emits correct TSX")
    func actionButtonGolden() throws {
        // The emitter measures the fonts it names: register them, whatever ran before.
        TestFontRegistration.registerTestFonts()
        let url = try #require(Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"))
        let doc = try PenParser.parse(contentsOf: url)
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let file = try #require(files.first { $0.path.contains("ActionButton") })

        try assertGolden(file.content, name: "ActionButton.tsx")
    }

    @Test("TextInput component emits correct TSX")
    func textInputGolden() throws {
        // The emitter measures the fonts it names: register them, whatever ran before.
        TestFontRegistration.registerTestFonts()
        let url = try #require(Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"))
        let doc = try PenParser.parse(contentsOf: url)
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let file = try #require(files.first { $0.path.contains("TextInput") })

        try assertGolden(file.content, name: "TextInput.tsx")
    }

    // MARK: - Page & Utility Golden Files

    @Test("HomeCollection component (with refs) emits correct TSX")
    func homeCollectionGolden() throws {
        // The emitter measures the fonts it names: register them, whatever ran before.
        TestFontRegistration.registerTestFonts()
        let url = try #require(Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"))
        let doc = try PenParser.parse(contentsOf: url)
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let file = try #require(files.first { $0.path.contains("HomeCollection") })

        try assertGolden(file.content, name: "HomeCollection.tsx")
    }

    @Test("ThemeProvider emits correct TSX from fixture")
    func themeProviderGolden() throws {
        // The emitter measures the fonts it names: register them, whatever ran before.
        TestFontRegistration.registerTestFonts()
        let url = try #require(Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"))
        let doc = try PenParser.parse(contentsOf: url)
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let file = try #require(files.first { $0.path == "ThemeProvider.tsx" })

        try assertGolden(file.content, name: "ThemeProvider.tsx")
    }

    @Test("cn.ts emits correct content")
    func cnGolden() throws {
        // The emitter measures the fonts it names: register them, whatever ran before.
        TestFontRegistration.registerTestFonts()
        let url = try #require(Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"))
        let doc = try PenParser.parse(contentsOf: url)
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let file = try #require(files.first { $0.path == "lib/cn.ts" })

        try assertGolden(file.content, name: "cn.ts")
    }

    @Test("Tabbar component emits correct TSX with N-way dispatch")
    func tabbarGolden() throws {
        // The emitter measures the fonts it names: register them, whatever ran before.
        TestFontRegistration.registerTestFonts()
        let url = try #require(Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"))
        let doc = try PenParser.parse(contentsOf: url)
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let file = try #require(files.first { $0.path.contains("TabBar") })

        try assertGolden(file.content, name: "TabBar.tsx")
    }

    @Test("ScreenSettings component (with refs) emits correct TSX")
    func screenSettingsGolden() throws {
        // The emitter measures the fonts it names: register them, whatever ran before.
        TestFontRegistration.registerTestFonts()
        let url = try #require(Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"))
        let doc = try PenParser.parse(contentsOf: url)
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let file = try #require(files.first { $0.path.contains("ScreenSettings") })

        try assertGolden(file.content, name: "ScreenSettings.tsx")
    }

    // MARK: - Layout Direction Defaults

    @Test("Frame with nil layout defaults to flex-row (horizontal)")
    func frameNilLayoutDefaultsHorizontal() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Row", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    children: [
                        PenNode(id: "r1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData(width: .fixed(20), height: .fixed(20)))),
                        PenNode(id: "r2", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData(width: .fixed(20), height: .fixed(20)))),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        // nil layout on frame → horizontal (CSS flex default is row, so no flex-col)
        #expect(!content.contains("flex-col"))
        #expect(content.contains("flex"))
    }

    @Test("Frame with explicit vertical layout emits flex-col")
    func frameExplicitVerticalLayout() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Col", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(id: "r1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData(width: .fixed(20), height: .fixed(20)))),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("flex-col"))
    }

    @Test("A group never emits flex classes — its children are always absolutely positioned")
    func groupNilLayoutDefaultsNone() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Wrapper", reusable: true, metadata: ["type": "component"]),
                // Horizontal wrapper so any "flex-col" found below can only have come from the group.
                kind: .frame(PenNode.FrameData(
                    layout: .horizontal,
                    children: [
                        PenNode(
                            id: "g1",
                            common: PenNodeCommon(),
                            kind: .group(PenNode.GroupData(
                                children: [
                                    PenNode(id: "r1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData(width: .fixed(20), height: .fixed(20)))),
                                ]
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        // A group is never a flex container — it has no layout property to be one.
        #expect(!content.contains("flex-col"))
        #expect(content.contains("className=\"relative\""))
    }

    // MARK: - Corner Radius Units

    @Test("Per-corner borderRadius includes px units")
    func perCornerRadiusHasPxUnits() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "r1",
                            common: PenNodeCommon(),
                            kind: .rectangle(PenNode.RectangleData(
                                width: .fixed(80),
                                height: .fixed(40),
                                cornerRadius: .perCorner(topLeft: .literal(16), topRight: .literal(16), bottomRight: .literal(0), bottomLeft: .literal(0))
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("borderRadius: \"16px 16px 0px 0px\""))
    }

    @Test("Frame with per-corner borderRadius includes px units")
    func framePerCornerRadiusHasPxUnits() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    cornerRadius: .perCorner(topLeft: .literal(0), topRight: .literal(16), bottomRight: .literal(0), bottomLeft: .literal(16)),
                    layout: .vertical,
                    children: []
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("borderRadius: \"0px 16px 0px 16px\""))
    }

    // MARK: - B1: flexShrink on fixed-size children

    @Test("Fixed-size child frame emits flexShrink 0")
    func fixedChildFlexShrink() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Row", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .horizontal,
                    children: [
                        PenNode(
                            id: "box",
                            common: PenNodeCommon(),
                            kind: .frame(PenNode.FrameData(
                                width: .fixed(40), height: .fixed(40),
                                layout: .vertical
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("flexShrink: 0"))
    }

    @Test("Absolute-positioned child does NOT get flexShrink 0")
    func absoluteChildNoFlexShrink() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Stack", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "box",
                            common: PenNodeCommon(x: .literal(10), y: .literal(10), layoutPosition: .absolute),
                            kind: .frame(PenNode.FrameData(
                                width: .fixed(40), height: .fixed(40),
                                layout: .vertical
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(!content.contains("flexShrink: 0"))
    }

    @Test("Fixed-size rectangle child emits flexShrink 0")
    func fixedRectangleFlexShrink() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Row", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .horizontal,
                    children: [
                        PenNode(
                            id: "r1",
                            common: PenNodeCommon(),
                            kind: .rectangle(PenNode.RectangleData(width: .fixed(20), height: .fixed(20)))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("flexShrink: 0"))
    }

    // MARK: - B2: emitCommonStyles on all node types

    @Test("Rectangle with rotation emits transform style")
    func rectangleRotation() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "r1",
                            common: PenNodeCommon(rotation: .literal(45)),
                            kind: .rectangle(PenNode.RectangleData(width: .fixed(20), height: .fixed(20)))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("transform: \"rotate(-45deg)\""))
    }

    @Test("Text with opacity emits opacity style")
    func textOpacity() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "t1",
                            common: PenNodeCommon(opacity: .literal(0.5)),
                            kind: .text(PenNode.TextData(content: .literal("Hello")))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("opacity: 0.5"))
    }

    @Test("Group with blendMode emits mixBlendMode style")
    func groupBlendMode() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "g1",
                            common: PenNodeCommon(),
                            kind: .group(PenNode.GroupData(blendMode: .multiply))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("mixBlendMode: \"multiply\""))
    }

    @Test("Ellipse with enabled false emits display none")
    func ellipseEnabled() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "e1",
                            common: PenNodeCommon(enabled: .literal(false)),
                            kind: .ellipse(PenNode.EllipseData(width: .fixed(20), height: .fixed(20)))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("display: \"none\""))
    }

    @Test("Polygon with rotation emits transform on SVG")
    func polygonRotation() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "p1",
                            common: PenNodeCommon(rotation: .literal(30)),
                            kind: .polygon(PenNode.PolygonData(
                                width: .fixed(40), height: .fixed(40),
                                polygonCount: .literal(6)
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("transform: \"rotate(-30deg)\""))
    }

    @Test("Icon with flipX emits scaleX transform")
    func iconFlip() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "i1",
                            common: PenNodeCommon(flipX: .literal(true)),
                            kind: .icon(PenNode.IconData(
                                icon: .literal("bell"),
                                library: .literal("lucide"),
                                width: .fixed(24)
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("transform: \"scaleX(-1)\""))
    }

    // MARK: - B3: Group absolute positioning

    @Test("Group with absolute child gets relative class")
    func groupAbsoluteChildRelative() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Overlay", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "g1",
                            common: PenNodeCommon(),
                            kind: .group(PenNode.GroupData(
                                children: [
                                    PenNode(
                                        id: "child",
                                        common: PenNodeCommon(x: .literal(5), y: .literal(5), layoutPosition: .absolute),
                                        kind: .rectangle(PenNode.RectangleData(width: .fixed(10), height: .fixed(10)))
                                    ),
                                ]
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("relative"))
    }

    @Test("Group with absolute position emits position absolute and coordinates")
    func groupAbsolutePosition() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Overlay", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "g1",
                            common: PenNodeCommon(x: .literal(10), y: .literal(20), layoutPosition: .absolute),
                            kind: .group(PenNode.GroupData())
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("position: \"absolute\""))
        #expect(content.contains("left: 10"))
        #expect(content.contains("top: 20"))
    }

    // MARK: - C2: Text wrapping

    @Test("Fixed-width text emits overflowWrap break-word")
    func fixedWidthTextWrapping() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "t1",
                            common: PenNodeCommon(),
                            kind: .text(PenNode.TextData(
                                width: .fixed(200),
                                content: .literal("Long text here"),
                                textGrowth: .fixedWidth
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("overflowWrap: \"break-word\""))
    }

    // MARK: - C3: Fill overrides on refs

    @Test("Ref with fill override emits backgroundColor style")
    func refFillOverride() throws {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "comp1",
                common: PenNodeCommon(name: "Component/Button", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(layout: .vertical))
            ),
            PenNode(
                id: "screen",
                common: PenNodeCommon(name: "Screen", metadata: ["type": "screen"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "ref1",
                            common: PenNodeCommon(name: "Delete Button"),
                            kind: .ref(PenNode.RefData(
                                ref: "comp1",
                                rootOverrides: ["fill": .string("$status-negative")]
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let pages = PageAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, pages: pages, theme: theme).files
        let screenFile = try #require(files.first { $0.path.contains("Screen") })
        #expect(screenFile.content.contains("backgroundColor: \"var(--status-negative)\""))
    }

    @Test("Ref with literal color fill override emits backgroundColor")
    func refLiteralFillOverride() throws {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "comp1",
                common: PenNodeCommon(name: "Component/Box", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(layout: .vertical))
            ),
            PenNode(
                id: "screen",
                common: PenNodeCommon(name: "Screen", metadata: ["type": "screen"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "ref1",
                            common: PenNodeCommon(name: "Red Box"),
                            kind: .ref(PenNode.RefData(
                                ref: "comp1",
                                rootOverrides: ["fill": .string("#FF0000")]
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let pages = PageAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, pages: pages, theme: theme).files
        let screenFile = try #require(files.first { $0.path.contains("Screen") })
        #expect(screenFile.content.contains("backgroundColor: \"#FF0000\""))
    }

    // MARK: - Fill-level blend mode (Fix 6)

    @Test("Single fill with blend mode emits mixBlendMode")
    func singleFillBlendMode() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    fills: .single(.color(PenFill.PenColorFill(
                        blendMode: .multiply,
                        color: .literal("#7B68B0")
                    ))),
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("backgroundColor: \"#7B68B0\""))
        #expect(content.contains("mixBlendMode: \"multiply\""))
    }

    @Test("Rectangle with single fill blend mode emits mixBlendMode")
    func rectangleSingleFillBlendMode() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "r1",
                            common: PenNodeCommon(name: "Rect"),
                            kind: .rectangle(PenNode.RectangleData(
                                width: .fixed(100), height: .fixed(100),
                                fills: .single(.color(PenFill.PenColorFill(
                                    blendMode: .screen,
                                    color: .literal("#FF0000")
                                )))
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("mixBlendMode: \"screen\""))
    }

    @Test("Parent frame of child with fill-level blendMode gets isolation: isolate")
    func parentIsolationForBlendMode() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "r1",
                            common: PenNodeCommon(name: "Overlay"),
                            kind: .rectangle(PenNode.RectangleData(
                                width: .fixed(100), height: .fixed(100),
                                fills: .single(.color(PenFill.PenColorFill(
                                    blendMode: .multiply,
                                    color: .literal("#7B68B0")
                                )))
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("isolation: \"isolate\""))
    }

    // MARK: - Line with fill_container width (Fix 1)

    @Test("Line with fill_container width emits CSS div instead of SVG")
    func lineFillContainerWidth() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "l1",
                            common: PenNodeCommon(name: "Divider"),
                            kind: .line(PenNode.LineData(
                                width: .fillContainer(fallback: nil),
                                height: .fixed(1),
                                stroke: .single(.shorthand("$border-strong")),
                                strokeWidth: .uniform(.literal(1))
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("width: \"100%\""))
        #expect(content.contains("borderTop:"))
        #expect(!content.contains("<svg"))
    }

    // MARK: - Line stroke height (Fix 3)

    @Test("Line SVG grows by half its stroke, so the stroke centres on the line")
    func lineStrokeHeight() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "l1",
                            common: PenNodeCommon(name: "StrokeLine"),
                            kind: .line(PenNode.LineData(
                                width: .fixed(100),
                                height: .fixed(1),
                                stroke: .single(.shorthand("#000")),
                                strokeWidth: .uniform(.literal(2))
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        // The SVG is the box grown by half the stroke on every side, so the stroke centres
        // on the line, which runs corner to corner as the renderer draws it.
        #expect(content.contains("height={3}"))
        #expect(content.contains(##"viewBox="-1 -1 102 3""##))
        #expect(content.contains(##"<line x1="0" y1="0" x2="100" y2="1""##))
    }

    // MARK: - Blur radius halved (Fix 4)

    @Test("Blur effect radius is halved for CSS")
    func blurRadiusHalved() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    effects: .single(.blur(PenEffect.PenBlurEffect(radius: .literal(4)))),
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("filter: \"blur(2px)\""))
    }

    @Test("Background blur radius is halved for CSS")
    func backgroundBlurRadiusHalved() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    // A fill to blur through: since leaf 0M8jRo a node with none writes no
                    // backdrop-filter, as Pen draws none.
                    fills: .single(.shorthand("#FFFFFF80")),
                    effects: .single(.backgroundBlur(PenEffect.PenBackgroundBlurEffect(radius: .literal(8)))),
                    layout: .vertical
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        #expect(content.contains("backdropFilter: \"blur(4px)\""))
    }

    // MARK: - Empty text element (Fix 5)

    @Test("Empty text element has minHeight and non-collapsing content")
    func emptyTextMinHeight() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "t1",
                            common: PenNodeCommon(name: "EmptyText"),
                            kind: .text(PenNode.TextData(
                                content: .literal(""),
                                fontSize: .literal(16),
                                lineHeight: .literal(1.5)
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files
        let content = files[0].content
        // Should have minHeight = 16 * 1.5 = 24
        #expect(content.contains("minHeight: 24"))
        // Should have non-breaking space to prevent collapse
        #expect(content.contains("&nbsp;") || content.contains("whiteSpace: \"pre\""))
    }

    // MARK: - All-Component Crash Test

    @Test("All components emit without crashing")
    func allComponentsEmit() throws {
        // The emitter measures the fonts it names: register them, whatever ran before.
        TestFontRegistration.registerTestFonts()
        let url = try #require(Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"))
        let doc = try PenParser.parse(contentsOf: url)
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let files = ReactEmitter.emit(document: doc, components: components, theme: theme).files

        #expect(files.count >= 20)
        for file in files {
            #expect(!file.content.isEmpty, "File \(file.path) has empty content")
        }
    }
}
