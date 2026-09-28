//
//  PenMeshColorTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Pen's mesh colour parse, row by row as `render-mesh-colors.pen` measured it (Pen's
/// exports of each colour over `#00FF00`; `PenMeshColorSnapshotTests` holds the renderer
/// to them): an optional leading `#` dropped, then three digits read one by one, six or
/// eight read as one JavaScript `parseInt(…, 16)` and split into bytes, and any other
/// length transparent.
struct PenMeshColorTests {
    @Test("Six-digit hex is opaque")
    func sixDigits() {
        #expect(PenMeshColor(penMesh: "#FF8000") == PenMeshColor(red: 1, green: 128.0 / 255, blue: 0, alpha: 1))
    }

    @Test("Eight-digit hex carries alpha last")
    func eightDigits() {
        #expect(PenMeshColor(penMesh: "#0000FF80") == PenMeshColor(red: 0, green: 0, blue: 1, alpha: 128.0 / 255))
    }

    @Test("Three-digit hex doubles each digit, and the # is optional")
    func shorthand() {
        #expect(PenMeshColor(penMesh: "F0a") == PenMeshColor(red: 1, green: 0, blue: 170.0 / 255))
    }

    @Test(
        "A length other than 3, 6 or 8 after one leading # is transparent",
        arguments: ["", "#", "#12", "#F00F", "#F008", "#FF000", "#FF00000", "#FF0000FFF", "F00#", "##F00", "#F#F00"]
    )
    func transparent(_ text: String) {
        #expect(PenMeshColor(penMesh: text) == .transparent)
    }

    @Test(
        "Three digits read one by one, a digit that is not hex reading 0",
        arguments: [("red", [0, 238, 221]), ("#F0G", [255, 0, 0]), ("#-0F", [0, 0, 255])]
    )
    func threeDigitsPerDigit(_ text: String, _ channels: [UInt8]) {
        #expect(PenMeshColor.hexColor(penMesh: text) == PenHexColor(red: channels[0], green: channels[1], blue: channels[2]))
    }

    @Test(
        "Six digits read as one parseInt: its leading hex prefix, whitespace, sign and 0x as JavaScript reads them",
        arguments: [
            ("#GGGGGG", [0, 0, 0]), ("#eGeGeG", [0, 0, 14]), ("#FFGG00", [0, 0, 255]), ("#-f-f-f", [255, 255, 241]),
            ("# f f f", [0, 0, 15]), ("#+f+f+f", [0, 0, 15]), ("#0x0x0x", [0, 0, 0]), ("#-00001", [255, 255, 255]),
        ]
    )
    func sixDigitsAsOneNumber(_ text: String, _ channels: [UInt8]) {
        #expect(PenMeshColor.hexColor(penMesh: text) == PenHexColor(red: channels[0], green: channels[1], blue: channels[2]))
    }

    @Test(
        "Eight digits read as one parseInt, alpha its low byte",
        arguments: [
            ("#eGeGeGeG", [0, 0, 0, 14]), ("#FF0000FG", [15, 240, 0, 15]), ("#GGGGGGGG", [0, 0, 0, 0]),
            ("#-0000001", [255, 255, 255, 255]), ("#FF00GG80", [0, 0, 255, 0]), ("# FFFF00F", [15, 255, 240, 15]),
            ("#ff000080", [255, 0, 0, 128]),
        ]
    )
    func eightDigitsAsOneNumber(_ text: String, _ channels: [UInt8]) {
        #expect(PenMeshColor.hexColor(penMesh: text) == PenHexColor(
            red: channels[0], green: channels[1], blue: channels[2], alpha: channels[3]
        ))
    }

    @Test("The colour's channels are its hex colour's, over 255")
    func unitChannels() {
        #expect(PenMeshColor(penMesh: "#-f-f-f") == PenMeshColor(red: 1, green: 1, blue: 241.0 / 255))
    }
}
