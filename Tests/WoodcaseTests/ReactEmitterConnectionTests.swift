//
//  ReactEmitterConnectionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// A `connection` joins two nodes on the canvas — Pen allows one only at the top level,
/// between artboards — so it has no place in a component's or a page's markup. The
/// emitter writes nothing for it: a top-level one never becomes a page, and one found
/// inside a frame (which Pen's validator refuses) is skipped rather than reported as an
/// unsupported node.
struct ReactEmitterConnectionTests {
    private let connection = PenNode.ConnectionData(
        source: PenNode.ConnectionData.Endpoint(path: "t1", anchor: .right),
        target: PenNode.ConnectionData.Endpoint(path: "t2", anchor: .left),
        stroke: .single(.color(PenFill.PenColorFill(color: .literal("#000000"))))
    )

    @Test("A connection inside a component emits nothing, not an unsupported-node comment")
    func nestedEmitsNothing() {
        let doc = PenDocument(children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [PenNode(id: "k1", common: PenNodeCommon(name: "Link"), kind: .connection(connection))]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let content = ReactEmitter.emit(document: doc, components: components, theme: theme).files[0].content
        #expect(!content.contains("unsupported node type"))
        #expect(!content.contains("Link"))
    }

    @Test("A top-level connection is not a page")
    func topLevelIsNotAPage() {
        let doc = PenDocument(children: [
            PenNode(id: "p1", common: PenNodeCommon(name: "Home"), kind: .frame(PenNode.FrameData())),
            PenNode(id: "k1", common: PenNodeCommon(name: "Flow"), kind: .connection(connection)),
        ])
        #expect(PageAnalyzer.analyze(doc).map(\.id) == ["p1"])
    }
}
