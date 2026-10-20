//
//  FigmaClipboardPayloadTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `FigmaClipboardPayload` extracts figmeta and the binary from every wrapper Figma's
/// clipboard HTML comes in, and refuses HTML that lacks them.
struct FigmaClipboardPayloadTests {
    private typealias Fixtures = FigmaClipboardFixtures

    private static func expectError(_ expected: FigmaDecodeError, html: String) {
        #expect(throws: expected) { try FigmaClipboardPayload(html: Data(html.utf8)) }
    }

    // MARK: - Committed captures

    @Test("figmeta and the binary come out of V1's committed clipboard.html")
    func extractsV1() throws {
        let payload = try FigmaClipboardPayload(html: Fixtures.html("V1"))
        #expect(payload.metadata == FigmaClipboardMetadata(
            fileKey: Fixtures.fixtureFileKey,
            pasteID: 160_774_220,
            dataType: "scene",
            editorType: "design",
            environment: "www.figma.com",
            selectedNodeData: "1:309|4|0|0",
            imageHashes: [:]
        ))
        #expect(payload.metadataJSON.first == UInt8(ascii: "{"))
        #expect(payload.buffer.count == 36327)
        #expect(payload.buffer.starts(with: Data("fig-kiwi".utf8)))
    }

    @Test("figmeta and the binary come out of M1a's committed clipboard.html")
    func extractsM1a() throws {
        let payload = try FigmaClipboardPayload(html: Fixtures.html("M1a"))
        #expect(payload.metadata.selectedNodeData == "1:485|27|0|0,1:483|30|0|0")
        #expect(payload.metadata.pasteID == 1_226_866_095)
        #expect(payload.buffer.count == 35343)
    }

    // MARK: - Wrappers

    @Test("Safari's entity-escaped, styled wrapper reads the same as the desktop app's")
    func safariWrapper() throws {
        let desktop = try Fixtures.htmlText("V1")
        let style = " style=\"caret-color: rgb(0, 0, 0); white-space: normal;\""
        let safari = desktop
            .replacingOccurrences(of: "<meta charset='utf-8'><meta charset=\"utf-8\">", with: "")
            .replacingOccurrences(of: "=\"<!--(", with: "=\"&lt;!--(")
            .replacingOccurrences(of: ")-->\"", with: ")--&gt;\"" + style)
        #expect(!safari.contains("\"<!--"))
        let expected = try FigmaClipboardPayload(html: Data(desktop.utf8))
        #expect(try FigmaClipboardPayload(html: Data(safari.utf8)) == expected)
    }

    @Test("Decimal and hexadecimal character references decode")
    func numericReferences() throws {
        let desktop = try Fixtures.htmlText("V1")
        let escaped = desktop
            .replacingOccurrences(of: "=\"<!--(", with: "=\"&#60;&#x21;--(")
            .replacingOccurrences(of: ")-->\"", with: ")-&#45;&#X3E;\"")
        let expected = try FigmaClipboardPayload(html: Data(desktop.utf8))
        #expect(try FigmaClipboardPayload(html: Data(escaped.utf8)) == expected)
    }

    @Test("Single-quoted attribute values read")
    func singleQuotes() throws {
        let desktop = try Fixtures.htmlText("V1")
        let quoted = desktop
            .replacingOccurrences(of: "=\"<!--(", with: "='<!--(")
            .replacingOccurrences(of: ")-->\"", with: ")-->'")
        let expected = try FigmaClipboardPayload(html: Data(desktop.utf8))
        #expect(try FigmaClipboardPayload(html: Data(quoted.utf8)) == expected)
    }

    @Test("Base64 broken across lines still reads")
    func wrappedBase64() throws {
        let metadata = Data("{\"dataType\":\"scene\"}".utf8)
        let base64 = metadata.base64EncodedString()
        let split = base64.prefix(8) + "\n  " + base64.dropFirst(8)
        let html = "<span data-metadata=\"<!--(figmeta)\(split)(/figmeta)-->\"></span>"
            + "<span data-buffer=\"<!--(figma)AAEC(/figma)-->\"></span>"
        let payload = try FigmaClipboardPayload(html: Data(html.utf8))
        #expect(payload.metadata.dataType == "scene")
        #expect(payload.buffer == Data([0, 1, 2]))
    }

    // MARK: - Refusals

    @Test("Empty input has no metadata")
    func emptyInput() {
        Self.expectError(.missingSection(.metadata), html: "")
    }

    @Test("Plain HTML without Figma's attributes has no metadata")
    func plainHTML() {
        Self.expectError(.missingSection(.metadata), html: "<p>Hello, <b>world</b></p>")
    }

    @Test("Metadata without a buffer is refused")
    func missingBuffer() {
        Self.expectError(.missingSection(.buffer), html: "<span data-metadata=\"<!--(figmeta)e30=(/figmeta)-->\"></span>")
    }

    @Test("An attribute without its markers is missing")
    func missingMarkers() {
        Self.expectError(
            .missingSection(.buffer),
            html: "<span data-metadata=\"<!--(figmeta)e30=(/figmeta)-->\"></span><span data-buffer=\"AAEC\"></span>"
        )
    }

    @Test("An unterminated attribute value is missing")
    func unterminatedValue() {
        Self.expectError(.missingSection(.metadata), html: "<span data-metadata=\"<!--(figmeta)e30=(/figmeta)-->")
    }

    @Test("Markers outside the attribute do not count")
    func markersOutsideAttribute() {
        Self.expectError(.missingSection(.metadata), html: "<!--(figmeta)e30=(/figmeta)--><!--(figma)AAEC(/figma)-->")
    }

    @Test("Text between the markers that is not base64 is refused")
    func invalidBase64() {
        Self.expectError(
            .invalidBase64(.buffer),
            html: "<span data-metadata=\"<!--(figmeta)e30=(/figmeta)-->\"></span>"
                + "<span data-buffer=\"<!--(figma)not*base64(/figma)-->\"></span>"
        )
    }

    @Test("Metadata that is not a JSON object is refused", arguments: ["[]", "null", "{", "{\"pasteID\":\"seven\"}"])
    func invalidMetadata(json: String) {
        let html = Fixtures.html(metadata: Data(json.utf8), buffer: Data([0]))
        #expect(throws: FigmaDecodeError.invalidMetadata) { try FigmaClipboardPayload(html: html) }
    }

    @Test("Bytes that are not UTF-8 never trap")
    func notUTF8() {
        #expect(throws: FigmaDecodeError.missingSection(.metadata)) {
            try FigmaClipboardPayload(html: Data([0xFF, 0xFE, 0x26, 0x23, 0x78, 0xFF, 0x3B]))
        }
    }

    @Test("A character reference past Unicode's range is left as text")
    func outOfRangeReference() {
        Self.expectError(
            .invalidBase64(.metadata),
            html: "<span data-metadata=\"<!--(figmeta)&#x110000;(/figmeta)-->\"></span>"
                + "<span data-buffer=\"<!--(figma)AAEC(/figma)-->\"></span>"
        )
    }
}
