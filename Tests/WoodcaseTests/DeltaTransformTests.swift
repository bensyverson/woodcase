//
//  DeltaTransformTests.swift
//  WoodcaseTests
//

import Testing
import Woodcase

/// A designer's state that turns or flips a node carries the change as a typed
/// ``DeltaTransform``, not a string an emitter would have to parse. React spells it as
/// valid CSS — the string the diff used to write (`rotate(45.0)`, `flipX`, `flipY`) was
/// never valid CSS, so a turned or flipped designer state never drew. Pen turns
/// counter-clockwise and CSS's `rotate()` clockwise, so the angle is negated; the flips
/// follow the turn, so they apply to the node first, as Pen applies them.
struct DeltaTransformTests {
    private func frame(_ id: String, rotation: Double? = nil, flipX: Bool? = nil, flipY: Bool? = nil) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(
                name: "Root",
                rotation: rotation.map { .literal($0) },
                flipX: flipX.map { .literal($0) },
                flipY: flipY.map { .literal($0) }
            ),
            kind: .frame(PenNode.FrameData())
        )
    }

    @Test("A turn and a flip diff to one typed transform")
    func turnAndFlip() throws {
        let result = NodeDiffer.diff(base: frame("a"), variant: frame("b", rotation: 45, flipX: true))
        let change = try #require(result.deltas.first?.changes.first { $0.property == .transform })
        #expect(change.value == .transform(DeltaTransform(rotation: 45, flipX: true, flipY: false)))
    }

    @Test("A turn taken away diffs to a transform with no rotation")
    func turnRemoved() throws {
        let result = NodeDiffer.diff(base: frame("a", rotation: 30, flipY: true), variant: frame("b"))
        let change = try #require(result.deltas.first?.changes.first { $0.property == .transform })
        #expect(change.value == .transform(DeltaTransform(rotation: nil, flipX: false, flipY: false)))
    }

    @Test("React spells a transform delta as valid CSS", arguments: [
        (DeltaTransform(rotation: 45, flipX: true, flipY: false), "rotate(-45deg) scaleX(-1)"),
        (DeltaTransform(rotation: nil, flipX: false, flipY: true), "scaleY(-1)"),
        (DeltaTransform(rotation: -12.5, flipX: true, flipY: true), "rotate(12.5deg) scaleX(-1) scaleY(-1)"),
        (DeltaTransform(rotation: 0, flipX: false, flipY: false), "none"),
        (DeltaTransform(rotation: nil, flipX: false, flipY: false), "none"),
    ])
    func reactSpelling(transform: DeltaTransform, css: String) {
        let component = ComponentDefinition(
            id: "c1", name: "Spinner", sourceNode: frame("a"), props: [], actions: [], bindings: [], role: .button,
            states: [
                StateDefinition(
                    name: "hover", trigger: .hover, source: .designerOverride, isStructural: false,
                    deltas: [StateDelta(nodePath: ".", changes: [PropertyChange(transform: transform)])],
                    variantNode: nil
                ),
            ]
        )
        let output = StateEmitter.emitCSS(for: [component])
        #expect(output.contains(".wc-spinner:hover {\n  --wc-spinner-transform: \(css);\n}"))
    }
}
