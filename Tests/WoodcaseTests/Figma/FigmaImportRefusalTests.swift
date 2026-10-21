//
//  FigmaImportRefusalTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A selection holding a node the importer cannot map is refused whole, naming each such
/// node, rather than imported in part.
struct FigmaImportRefusalTests {
    private typealias Fixtures = FigmaImportFixtures

    @Test("A node of an unsupported type refuses the whole selection, naming its type and layer")
    func refusesUnsupportedType() throws {
        let sticky = Fixtures.nodeChange("STICKY", name: "Note to self", id: 60)
        let rectangle = Fixtures.nodeChange("ROUNDED_RECTANGLE", name: "fine", id: 61, position: "\"")
        do {
            _ = try FigmaImporter().clip(from: Fixtures.message([sticky, rectangle]))
            Issue.record("imported")
        } catch let .unsupportedNodes(nodes) {
            #expect(nodes == [FigmaImportError.UnsupportedNode(type: "STICKY", name: "Note to self", nodeID: "figma-1-60")])
            #expect(FigmaImportError.unsupportedNodes(nodes).description.contains("STICKY"))
            #expect(FigmaImportError.unsupportedNodes(nodes).description.contains("Note to self"))
        } catch {
            Issue.record("\(error)")
        }
    }

    @Test("An unsupported node deep inside a frame still refuses the selection")
    func refusesNested() throws {
        let frame = Fixtures.nodeChange("FRAME", name: "board", id: 62)
        let connector = Fixtures.nodeChange("CONNECTOR", name: "connector", id: 63, parent: Fixtures.guid(1, 62))
        #expect(throws: FigmaImportError.unsupportedNodes([
            FigmaImportError.UnsupportedNode(type: "CONNECTOR", name: "connector", nodeID: "figma-1-63"),
        ])) {
            try FigmaImporter().clip(from: Fixtures.message([frame, connector]))
        }
    }

    @Test("A message with nothing on its page is refused")
    func refusesEmpty() throws {
        #expect(throws: FigmaImportError.noContent) {
            try FigmaImporter().clip(from: Fixtures.message([]))
        }
    }

    @Test("A node whose network blob is missing is refused rather than drawn empty")
    func refusesMissingBlob() throws {
        let vector = Fixtures.nodeChange("VECTOR", name: "broken", id: 64, extra: [
            "vectorData": .message(KiwiRecord(typeName: "VectorData", fields: ["vectorNetworkBlob": .uint(3)])),
        ])
        #expect(throws: FigmaImportError.blob(.blobIndexOutOfRange(index: 3, count: 0))) {
            try FigmaImporter().clip(from: Fixtures.message([vector]))
        }
    }
}

/// The FigJam and Slides captures, which hold node types the importer does not map, refuse
/// whole. They are local only (see ``FigmaClipboardCaptureTests``).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FIGMA_CASES"] != nil, "set FIGMA_CASES to a folder of raw captures"))
struct FigmaImportCaptureRefusalTests {
    @Test("FigJam and Slides selections are refused, naming their node types", arguments: ["E1", "E2a", "E2b"])
    func refusesOtherEditors(name: String) throws {
        let folder = try #require(FigmaClipboardCaptureTests.folder)
        let html = try Data(contentsOf: folder.appendingPathComponent("\(name).html"))
        let clipboard = try FigmaClipboardDecoder().decode(html: html)
        do {
            _ = try FigmaImporter().clip(from: clipboard)
            Issue.record("\(name) imported")
        } catch let .unsupportedNodes(nodes) {
            #expect(!nodes.isEmpty)
            print("\(name) refused: \(Set(nodes.map(\.type)).sorted())")
        } catch {
            Issue.record("\(name): \(error)")
        }
    }

    @Test("Every Design capture imports", arguments: ["V1", "V1-browser", "V1-brave", "T1", "G1", "P1", "I1", "C1", "R1", "L1"])
    func designCapturesImport(name: String) throws {
        let folder = try #require(FigmaClipboardCaptureTests.folder)
        let html = try Data(contentsOf: folder.appendingPathComponent("\(name).html"))
        let result = try FigmaImporter().clip(from: FigmaClipboardDecoder().decode(html: html))
        #expect(!result.clip.document.children.isEmpty)
        #expect(!result.losses.contains { $0.feature == .unreadField }, "\(name)")
    }
}
