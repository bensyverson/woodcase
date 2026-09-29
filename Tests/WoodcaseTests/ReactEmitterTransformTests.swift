import Testing
@testable import Woodcase

/// How React spells a node's own turn and flips: Pen turns counter-clockwise about the
/// node's `x`/`y` and flips before it turns, so a free-positioned node's CSS transform
/// pivots at its top-left corner, and the angle keeps its fraction.
struct ReactEmitterTransformTests {
    private func emit(parentLayout: PenLayoutDirection, child: PenNodeCommon) -> String {
        let doc = PenDocument(version: "2.17", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    width: .fixed(120),
                    height: .fixed(120),
                    layout: parentLayout,
                    children: [
                        PenNode(
                            id: "r1",
                            common: child,
                            kind: .rectangle(PenNode.RectangleData(width: .fixed(50), height: .fixed(50)))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let files = ReactEmitter.emit(document: doc, components: components, theme: ThemeAnalyzer.analyze(doc)).files
        return files.first { $0.path.hasPrefix("components/") }?.content ?? ""
    }

    @Test("A free-positioned turned node pivots at its x/y")
    func freeTurnPivotsAtAnchor() {
        let output = emit(
            parentLayout: PenLayoutDirection.none,
            child: PenNodeCommon(x: .literal(35), y: .literal(35), rotation: .literal(25))
        )
        #expect(output.contains("transform: \"rotate(-25deg)\""))
        #expect(output.contains("transformOrigin: \"0 0\""))
    }

    @Test("A free-positioned flipped node mirrors about its x/y")
    func freeFlipPivotsAtAnchor() {
        let output = emit(
            parentLayout: PenLayoutDirection.none,
            child: PenNodeCommon(x: .literal(70), y: .literal(35), flipX: .literal(true))
        )
        #expect(output.contains("transform: \"scaleX(-1)\""))
        #expect(output.contains("transformOrigin: \"0 0\""))
    }

    @Test("An absolutely positioned node in a flex parent pivots at its x/y")
    func absoluteInFlowPivotsAtAnchor() {
        let output = emit(
            parentLayout: .vertical,
            child: PenNodeCommon(x: .literal(10), y: .literal(10), rotation: .literal(25), layoutPosition: .absolute)
        )
        #expect(output.contains("transformOrigin: \"0 0\""))
    }

    @Test("A turned node in a flex flow keeps CSS's center pivot")
    func flowTurnKeepsCenterPivot() {
        let output = emit(parentLayout: .vertical, child: PenNodeCommon(rotation: .literal(25)))
        #expect(output.contains("transform: \"rotate(-25deg)\""))
        #expect(!output.contains("transformOrigin"))
    }

    @Test("A fractional turn keeps its fraction")
    func fractionalTurn() {
        let output = emit(parentLayout: .vertical, child: PenNodeCommon(rotation: .literal(12.5)))
        #expect(output.contains("transform: \"rotate(-12.5deg)\""))
    }

    @Test("An unturned, unflipped node writes no transform")
    func zeroTurnWritesNothing() {
        let output = emit(parentLayout: .vertical, child: PenNodeCommon(rotation: .literal(0)))
        #expect(!output.contains("transform"))
    }
}
