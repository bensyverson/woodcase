//
//  FuzzFixture.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// The base documents the fuzz suites start from.
enum FuzzFixture {
    /// A base document with ~10 nodes plus a reusable component and two instances of it.
    ///
    /// ``RandomEditGenerator`` aims its "hot" operations at the containers `f1`, `f2` and
    /// `g1`, and its descendant overrides at the component's children `btnL` and `btnI`.
    static func document() -> PenDocument {
        let r1 = PenNode(
            id: "r1",
            common: PenNodeCommon(name: "Rect1"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100)))
        )
        let r2 = PenNode(
            id: "r2",
            common: PenNodeCommon(name: "Rect2"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(80)))
        )
        let t1 = PenNode(
            id: "t1",
            common: PenNodeCommon(name: "Text1"),
            kind: .text(PenNode.TextData(width: .fixed(200)))
        )
        let t2 = PenNode(
            id: "t2",
            common: PenNodeCommon(name: "Text2"),
            kind: .text(PenNode.TextData(width: .fixed(150)))
        )
        let g1 = PenNode(
            id: "g1",
            common: PenNodeCommon(name: "Group1"),
            kind: .group(PenNode.GroupData(children: [r2, t2]))
        )
        let f1 = PenNode(
            id: "f1",
            common: PenNodeCommon(name: "Frame1", theme: ["mode": "dark"]),
            kind: .frame(PenNode.FrameData(width: .fixed(400), children: [r1, t1, g1]))
        )
        let r3 = PenNode(
            id: "r3",
            common: PenNodeCommon(name: "Rect3"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(60)))
        )
        let e1 = PenNode(
            id: "e1",
            common: PenNodeCommon(name: "Ellipse1"),
            kind: .ellipse(PenNode.EllipseData(width: .fixed(50)))
        )
        let f2 = PenNode(
            id: "f2",
            common: PenNodeCommon(name: "Frame2", theme: ["density": "compact"]),
            kind: .frame(PenNode.FrameData(width: .fixed(300), children: [r3, e1]))
        )
        let r4 = PenNode(
            id: "r4",
            common: PenNodeCommon(name: "Rect4"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(120)))
        )

        // Reusable component: a button with a label and icon
        let btnLabel = PenNode(
            id: "btnL",
            common: PenNodeCommon(name: "BtnLabel"),
            kind: .text(PenNode.TextData(width: .fixed(80)))
        )
        let btnIcon = PenNode(
            id: "btnI",
            common: PenNodeCommon(name: "BtnIcon"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(24)))
        )
        let btnComp = PenNode(
            id: "btnC",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData(width: .fixed(120), children: [btnIcon, btnLabel]))
        )

        // Ref instances of the button component
        let ref1 = PenNode(
            id: "bR1",
            common: PenNodeCommon(name: "Submit"),
            kind: .ref(PenNode.RefData(ref: "btnC"))
        )
        let ref2 = PenNode(
            id: "bR2",
            common: PenNodeCommon(name: "Cancel"),
            kind: .ref(PenNode.RefData(ref: "btnC", descendants: [
                "btnL": PenDescendantOverride(properties: ["name": .string("Cancel")]),
            ]))
        )

        return PenDocument(
            themes: ["mode": ["light", "dark"], "density": ["normal", "compact"]],
            variables: [
                "bgColor": PenVariable(type: .color, value: .themed([
                    PenThemedValue(value: .string("#FFFFFF"), theme: ["mode": "light"]),
                    PenThemedValue(value: .string("#000000"), theme: ["mode": "dark"]),
                ])),
                "spacing": PenVariable(type: .number, value: .themed([
                    PenThemedValue(value: .double(16), theme: ["density": "normal"]),
                    PenThemedValue(value: .double(8), theme: ["density": "compact"]),
                ])),
            ],
            children: [f1, f2, r4, btnComp, ref1, ref2]
        )
    }
}
