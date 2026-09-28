//
//  NodeDifferTests.swift
//  WoodcaseTests
//

import Testing
import Woodcase

struct NodeDifferTests {
    // MARK: - Helpers

    private func makeFrame(
        id: String = "f1",
        name: String? = nil,
        fills: PenFills? = nil,
        stroke: PenFills? = nil,
        strokeWidth: PenStrokeWidth? = nil,
        effects: PenEffects? = nil,
        cornerRadius: PenCornerRadius? = nil,
        opacity: PenValue<Double>? = nil,
        width: PenSizing? = nil,
        height: PenSizing? = nil,
        padding: PenPadding? = nil,
        gap: PenValue<Double>? = nil,
        children: [PenNode]? = nil
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: name, opacity: opacity),
            kind: .frame(PenNode.FrameData(
                width: width,
                height: height,
                cornerRadius: cornerRadius,
                fills: fills,
                stroke: stroke,
                strokeWidth: strokeWidth,
                effects: effects,
                gap: gap,
                padding: padding,
                children: children
            ))
        )
    }

    private func makeText(
        id: String = "t1",
        name: String? = nil,
        fills: PenFills? = nil,
        fontSize: PenValue<Double>? = nil,
        fontWeight: PenValue<String>? = nil,
        content: String = "Hello"
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: name),
            kind: .text(PenNode.TextData(
                content: .literal(content),
                fontSize: fontSize,
                fontWeight: fontWeight,
                fills: fills
            ))
        )
    }

    private func makeRect(
        id: String = "r1",
        name: String? = nil,
        fills: PenFills? = nil,
        cornerRadius: PenCornerRadius? = nil
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: name),
            kind: .rectangle(PenNode.RectangleData(
                cornerRadius: cornerRadius,
                fills: fills
            ))
        )
    }

    // MARK: - Identical Nodes

    @Test("Identical nodes produce empty deltas and are not structural")
    func identicalNodes() {
        let base = makeFrame(name: "Root", fills: .single(.shorthand("#FF0000")))
        let variant = makeFrame(name: "Root", fills: .single(.shorthand("#FF0000")))

        let result = NodeDiffer.diff(base: base, variant: variant)

        #expect(result.deltas.isEmpty)
        #expect(!result.isStructural)
    }

    // MARK: - Root Property Changes

    @Test("Root fill change produces delta at path '.'")
    func rootFillChange() {
        let base = makeFrame(name: "Root", fills: .single(.shorthand("#FF0000")))
        let variant = makeFrame(name: "Root", fills: .single(.shorthand("#00FF00")))

        let result = NodeDiffer.diff(base: base, variant: variant)

        #expect(!result.isStructural)
        #expect(result.deltas.count == 1)
        #expect(result.deltas[0].nodePath == ".")
        #expect(result.deltas[0].changes.contains { $0.property == .fills })
    }

    @Test("Root opacity change produces delta at path '.'")
    func rootOpacityChange() {
        let base = makeFrame(name: "Root", opacity: .literal(1.0))
        let variant = makeFrame(name: "Root", opacity: .literal(0.5))

        let result = NodeDiffer.diff(base: base, variant: variant)

        #expect(!result.isStructural)
        #expect(result.deltas.count == 1)
        #expect(result.deltas[0].nodePath == ".")
        #expect(result.deltas[0].changes.contains { $0.property == .opacity })
    }

    @Test("Root stroke paint change produces a strokeColor delta")
    func rootStrokePaintChange() {
        let base = makeFrame(name: "Root", stroke: .single(.shorthand("#FF0000")))
        let variant = makeFrame(name: "Root", stroke: .single(.shorthand("#00FF00")))

        let result = NodeDiffer.diff(base: base, variant: variant)

        #expect(result.deltas.count == 1)
        #expect(result.deltas[0].changes.contains { $0.property == .strokeColor })
    }

    @Test("A stroke width change alone produces a strokeWidth delta")
    func rootStrokeWidthChange() {
        let paint: PenFills = .single(.shorthand("#FF0000"))
        let base = makeFrame(name: "Root", stroke: paint, strokeWidth: .uniform(.literal(1)))
        let variant = makeFrame(name: "Root", stroke: paint, strokeWidth: .uniform(.literal(4)))

        let result = NodeDiffer.diff(base: base, variant: variant)

        #expect(result.deltas.count == 1)
        #expect(result.deltas[0].changes.contains { $0.property == .strokeWidth })
        #expect(!result.deltas[0].changes.contains { $0.property == .strokeColor })
    }

    @Test("Root corner radius change produces delta")
    func rootCornerRadiusChange() {
        let base = makeFrame(name: "Root", cornerRadius: .uniform(.literal(8)))
        let variant = makeFrame(name: "Root", cornerRadius: .uniform(.literal(16)))

        let result = NodeDiffer.diff(base: base, variant: variant)

        #expect(result.deltas.count == 1)
        #expect(result.deltas[0].changes.contains { $0.property == .cornerRadius })
    }

    // MARK: - Nested Changes

    @Test("Child fill change produces delta at child name path")
    func nestedChildChange() {
        let base = makeFrame(name: "Root", children: [
            makeRect(name: "Background", fills: .single(.shorthand("#FF0000"))),
        ])
        let variant = makeFrame(name: "Root", children: [
            makeRect(name: "Background", fills: .single(.shorthand("#00FF00"))),
        ])

        let result = NodeDiffer.diff(base: base, variant: variant)

        #expect(!result.isStructural)
        #expect(result.deltas.count == 1)
        #expect(result.deltas[0].nodePath == "Background")
        #expect(result.deltas[0].changes.contains { $0.property == .fills })
    }

    @Test("Deeply nested change produces path with separator")
    func deeplyNestedChange() {
        let base = makeFrame(name: "Root", children: [
            makeFrame(name: "Header", children: [
                makeText(name: "Title", fills: .single(.shorthand("#000000"))),
            ]),
        ])
        let variant = makeFrame(name: "Root", children: [
            makeFrame(name: "Header", children: [
                makeText(name: "Title", fills: .single(.shorthand("#FF0000"))),
            ]),
        ])

        let result = NodeDiffer.diff(base: base, variant: variant)

        #expect(!result.isStructural)
        #expect(result.deltas.count == 1)
        #expect(result.deltas[0].nodePath == "Header/Title")
    }

    // MARK: - Text Changes

    @Test("Text color change produces textColor delta")
    func textColorChange() {
        let base = makeText(name: "Label", fills: .single(.shorthand("#000000")))
        let variant = makeText(name: "Label", fills: .single(.shorthand("#FF0000")))

        let result = NodeDiffer.diff(base: base, variant: variant)

        #expect(result.deltas.count == 1)
        #expect(result.deltas[0].changes.contains { $0.property == .textColor })
    }

    @Test("Font size change produces fontSize delta")
    func fontSizeChange() {
        let base = makeText(name: "Label", fontSize: .literal(14))
        let variant = makeText(name: "Label", fontSize: .literal(16))

        let result = NodeDiffer.diff(base: base, variant: variant)

        #expect(result.deltas.count == 1)
        #expect(result.deltas[0].changes.contains { $0.property == .fontSize })
    }

    @Test("Font weight change produces fontWeight delta")
    func fontWeightChange() {
        let base = makeText(name: "Label", fontWeight: .literal("400"))
        let variant = makeText(name: "Label", fontWeight: .literal("700"))

        let result = NodeDiffer.diff(base: base, variant: variant)

        #expect(result.deltas.count == 1)
        #expect(result.deltas[0].changes.contains { $0.property == .fontWeight })
    }

    // MARK: - Multiple Changes

    @Test("Multiple properties changing on same node produce multiple changes in one delta")
    func multipleChanges() {
        let base = makeFrame(
            name: "Root",
            fills: .single(.shorthand("#FF0000")),
            opacity: .literal(1.0)
        )
        let variant = makeFrame(
            name: "Root",
            fills: .single(.shorthand("#00FF00")),
            opacity: .literal(0.5)
        )

        let result = NodeDiffer.diff(base: base, variant: variant)

        #expect(result.deltas.count == 1)
        #expect(result.deltas[0].nodePath == ".")
        #expect(result.deltas[0].changes.count == 2)
    }

    // MARK: - Structural Changes

    @Test("Child added in variant is structural")
    func childAdded() {
        let base = makeFrame(name: "Root", children: [
            makeRect(name: "Background"),
        ])
        let variant = makeFrame(name: "Root", children: [
            makeRect(name: "Background"),
            makeRect(name: "Spinner"),
        ])

        let result = NodeDiffer.diff(base: base, variant: variant)

        #expect(result.isStructural)
    }

    @Test("Child removed in variant is structural")
    func childRemoved() {
        let base = makeFrame(name: "Root", children: [
            makeRect(name: "Background"),
            makeRect(name: "Icon"),
        ])
        let variant = makeFrame(name: "Root", children: [
            makeRect(name: "Background"),
        ])

        let result = NodeDiffer.diff(base: base, variant: variant)

        #expect(result.isStructural)
    }

    @Test("Children reordered is structural")
    func childrenReordered() {
        let base = makeFrame(name: "Root", children: [
            makeRect(name: "A"),
            makeRect(name: "B"),
        ])
        let variant = makeFrame(name: "Root", children: [
            makeRect(name: "B"),
            makeRect(name: "A"),
        ])

        let result = NodeDiffer.diff(base: base, variant: variant)

        #expect(result.isStructural)
    }

    @Test("Child position change (x/y) is structural")
    func childPositionChangeIsStructural() {
        let base = makeFrame(name: "Root", children: [
            PenNode(
                id: "thumb",
                common: PenNodeCommon(name: "Thumb", x: .literal(20), y: .literal(2)),
                kind: .ellipse(PenNode.EllipseData(width: .fixed(22), height: .fixed(22)))
            ),
        ])
        let variant = makeFrame(name: "Root", children: [
            PenNode(
                id: "thumb",
                common: PenNodeCommon(name: "Thumb", x: .literal(2), y: .literal(2)),
                kind: .ellipse(PenNode.EllipseData(width: .fixed(22), height: .fixed(22)))
            ),
        ])

        let result = NodeDiffer.diff(base: base, variant: variant)

        #expect(result.isStructural)
    }

    @Test("Structural diff still captures property changes on matched nodes")
    func structuralWithPropertyChanges() {
        let base = makeFrame(name: "Root", children: [
            makeRect(name: "Background", fills: .single(.shorthand("#FF0000"))),
        ])
        let variant = makeFrame(name: "Root", children: [
            makeRect(name: "Background", fills: .single(.shorthand("#00FF00"))),
            makeRect(name: "Spinner"),
        ])

        let result = NodeDiffer.diff(base: base, variant: variant)

        #expect(result.isStructural)
        #expect(result.deltas.contains { $0.nodePath == "Background" })
    }

    // MARK: - Edge Cases

    @Test("Both leaf nodes with no visual differences produce empty result")
    func leafNodesNoDiff() {
        let base = makeRect(name: "Box")
        let variant = makeRect(name: "Box")

        let result = NodeDiffer.diff(base: base, variant: variant)

        #expect(result.deltas.isEmpty)
        #expect(!result.isStructural)
    }

    @Test("Frame padding change detected")
    func paddingChange() {
        let base = makeFrame(name: "Root", padding: .uniform(.literal(8)))
        let variant = makeFrame(name: "Root", padding: .uniform(.literal(16)))

        let result = NodeDiffer.diff(base: base, variant: variant)

        #expect(result.deltas.count == 1)
        #expect(result.deltas[0].changes.contains { $0.property == .padding })
    }

    @Test("Frame gap change detected")
    func gapChange() {
        let base = makeFrame(name: "Root", gap: .literal(8))
        let variant = makeFrame(name: "Root", gap: .literal(16))

        let result = NodeDiffer.diff(base: base, variant: variant)

        #expect(result.deltas.count == 1)
        #expect(result.deltas[0].changes.contains { $0.property == .gap })
    }
}
