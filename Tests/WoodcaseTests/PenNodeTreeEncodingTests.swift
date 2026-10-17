//
//  PenNodeTreeEncodingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Encoding a node writes its whole subtree exactly as before, although the subtree is
/// walked from a work list rather than by each node encoding its children.
struct PenNodeTreeEncodingTests {
    /// A tree with nested containers, extras on a nested node, a node of an unknown type,
    /// a container that declares an empty list and one that declares none.
    private static let tree = PenNode(
        id: "root",
        common: PenNodeCommon(name: "Root"),
        kind: .frame(PenNode.FrameData(width: .fixed(100), children: [
            PenNode(
                id: "group",
                common: PenNodeCommon(),
                kind: .group(PenNode.GroupData(children: [
                    PenNode(id: "text", common: PenNodeCommon(), kind: .text(PenNode.TextData(content: .literal("hi")))),
                    PenNode(
                        id: "odd",
                        common: PenNodeCommon(),
                        kind: .unknown(typeName: "video_clip", properties: ["src": .string("a.mp4")])
                    ),
                ])),
                extras: PenExtras(["custom": .int(7)])
            ),
            PenNode(id: "empty", common: PenNodeCommon(), kind: .frame(PenNode.FrameData(children: []))),
            PenNode(id: "bare", common: PenNodeCommon(), kind: .frame(PenNode.FrameData())),
        ]))
    )

    @Test("A tree encodes to the nested object the format describes")
    func nestedObject() throws {
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.tree)) as? NSDictionary
        let expected: NSDictionary = [
            "id": "root", "type": "frame", "name": "Root", "width": 100,
            "children": [
                [
                    "id": "group", "type": "group", "custom": 7,
                    "children": [
                        ["id": "text", "type": "text", "content": "hi"],
                        ["id": "odd", "type": "video_clip", "src": "a.mp4"],
                    ],
                ],
                ["id": "empty", "type": "frame", "children": [Any]()],
                ["id": "bare", "type": "frame"],
            ],
        ]

        #expect(encoded == expected)
    }

    @Test("A tree survives an encode and a decode")
    func roundTrip() throws {
        let decoded = try JSONDecoder().decode(PenNode.self, from: JSONEncoder().encode(Self.tree))

        #expect(decoded == Self.tree)
    }
}
