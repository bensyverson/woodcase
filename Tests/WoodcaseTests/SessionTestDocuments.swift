//
//  SessionTestDocuments.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// Small documents the change-key, normalization and granular-inverse suites share.
enum SessionTestDocuments {
    /// `f1 > [c1 rect, c2 text, c3 ellipse]`, `f2 > [c4 rect]`, a reusable `comp1 > [inner, label]`,
    /// and `ref1` pointing at it with an override on `inner` and a root override, plus
    /// one variable, import and theme axis.
    static func make() -> EditableDocument {
        let c1 = PenNode(
            id: "c1",
            common: PenNodeCommon(name: "Child1"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100), height: .fixed(40)))
        )
        let c2 = PenNode(id: "c2", common: PenNodeCommon(name: "Child2"), kind: .text(PenNode.TextData()))
        let c3 = PenNode(id: "c3", common: PenNodeCommon(name: "Child3"), kind: .ellipse(PenNode.EllipseData()))
        let f1 = PenNode(
            id: "f1",
            common: PenNodeCommon(name: "Frame1"),
            kind: .frame(PenNode.FrameData(children: [c1, c2, c3]))
        )
        let c4 = PenNode(id: "c4", common: PenNodeCommon(name: "Child4"), kind: .rectangle(PenNode.RectangleData()))
        let f2 = PenNode(id: "f2", common: PenNodeCommon(name: "Frame2"), kind: .frame(PenNode.FrameData(children: [c4])))
        let inner = PenNode(id: "inner", common: PenNodeCommon(name: "Inner"), kind: .rectangle(PenNode.RectangleData()))
        let label = PenNode(id: "label", common: PenNodeCommon(name: "Label"), kind: .text(PenNode.TextData()))
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Component", reusable: true),
            kind: .frame(PenNode.FrameData(children: [inner, label]))
        )
        let ref = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "Instance"),
            kind: .ref(PenNode.RefData(
                ref: "comp1",
                descendants: ["inner": PenDescendantOverride(properties: ["fill": "#ff0000"])],
                rootOverrides: ["width": 120]
            ))
        )
        return EditableDocument(from: PenDocument(
            themes: ["mode": ["light", "dark"]],
            imports: ["lib": "lib.pen"],
            variables: ["primary": PenVariable(type: .color, value: .simple(AnyCodable("#ff0000")))],
            children: [f1, f2, component, ref]
        ))
    }
}
