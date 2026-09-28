//
//  PenBrowserDataTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Covers the typed `browser` node Pen 2.19 added: ``PenNode/BrowserData`` decodes
/// every key Pen's 2.19 format defines, dispatches through ``PenNode``'s Codable like
/// every other kind, and a hand-written fixture survives a decode and a canonical
/// encode byte for byte.
struct PenBrowserDataTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var fixtureURL: URL {
        get throws {
            try #require(Bundle.module.url(forResource: "browser", withExtension: "pen", subdirectory: "Fixtures"))
        }
    }

    // MARK: - Dispatch

    @Test("A browser node, as Pen 1.2.14 writes one, decodes to Kind.browser")
    func decodesAsBrowser() throws {
        let json = """
        {"type":"browser","id":"vlIb0","x":220,"y":300,"name":"browser","width":200,"height":90,"url":"example.com"}
        """
        let node = try decoder.decode(PenNode.self, from: Data(json.utf8))
        guard case let .browser(data) = node.kind else {
            Issue.record("Expected .browser, got \(node.kind)")
            return
        }
        #expect(data.url == "example.com")
        #expect(data.width == .fixed(200))
        #expect(data.height == .fixed(90))
        #expect(node.common.name == "browser")
    }

    @Test("Every key of Pen's browser schema decodes")
    func decodesEveryKey() throws {
        let json = """
        {"type":"browser","id":"B1","width":"fill_container","height":120,
         "url":"https://pen.dev","deviceId":"iphone-15","zoom":0.75,"scrollX":4,"scrollY":240,
         "cornerRadius":[16,16,0,0],"stroke":"#10B981","strokeWidth":2,"strokeAlignment":"inner",
         "strokeLinecap":"round","strokeLinejoin":"bevel",
         "effect":{"type":"shadow","shadowType":"outer","color":"#00000033","blur":8}}
        """
        let node = try decoder.decode(PenNode.self, from: Data(json.utf8))
        guard case let .browser(data) = node.kind else {
            Issue.record("Expected .browser, got \(node.kind)")
            return
        }
        #expect(data.width == .fillContainer(fallback: nil))
        #expect(data.height == .fixed(120))
        #expect(data.url == "https://pen.dev")
        #expect(data.deviceId == "iphone-15")
        #expect(data.zoom == 0.75)
        #expect(data.scrollX == 4)
        #expect(data.scrollY == 240)
        #expect(data.cornerRadius == .perCorner(
            topLeft: .literal(16), topRight: .literal(16), bottomRight: .literal(0), bottomLeft: .literal(0)
        ))
        #expect(data.stroke == .single(.shorthand("#10B981")))
        #expect(data.strokeWidth == .uniform(.literal(2)))
        #expect(data.strokeAlignment == .inner)
        #expect(data.strokeLinecap == .round)
        #expect(data.strokeLinejoin == .bevel)
        #expect(data.effects?.all.count == 1)
    }

    @Test("NodeType includes .browser, with a summary that says it is never loaded")
    func nodeTypeIncludesBrowser() {
        #expect(PenNode.NodeType(rawValue: "browser") == .browser)
        #expect(PenNode.NodeType.browser.summary.contains("never"))
        #expect(PenNode.Kind.browser(PenNode.BrowserData()).typeName == "browser")
        #expect(PenNode.Kind.browser(PenNode.BrowserData()).nodeType == .browser)
    }

    @Test("A browser node round-trips through PenNode's Codable dispatch")
    func nodeRoundTrips() throws {
        let node = PenNode(
            id: "b1",
            common: PenNodeCommon(name: "Web", x: .literal(0), y: .literal(0)),
            kind: .browser(PenNode.BrowserData(
                url: "example.com", deviceId: "desktop", zoom: 1.5, scrollX: 0, scrollY: 12,
                cornerRadius: .uniform(.literal(8)),
                width: .fixed(200), height: .fitContent(fallback: 90),
                stroke: .single(.shorthand("#000000")), strokeWidth: .uniform(.literal(1))
            ))
        )
        let decoded = try decoder.decode(PenNode.self, from: encoder.encode(node))
        #expect(decoded == node)
    }

    @Test("An absent key stays absent: nothing is defaulted into the file")
    func absentKeysStayAbsent() throws {
        let json = #"{"type":"browser","id":"B1"}"#
        let node = try decoder.decode(PenNode.self, from: Data(json.utf8))
        let sorted = JSONEncoder()
        sorted.outputFormatting = .sortedKeys
        let reencoded = try String(decoding: sorted.encode(node), as: UTF8.self)
        #expect(reencoded == #"{"id":"B1","type":"browser"}"#)
    }

    @Test("The hand-written browser fixture round-trips through encodeForFile byte for byte")
    func fixtureIsByteStable() throws {
        let original = try Data(contentsOf: fixtureURL)
        let reencoded = try PenParser.encodeForFile(PenParser.parse(original))
        #expect(String(decoding: reencoded, as: UTF8.self) == String(decoding: original, as: UTF8.self))
    }

    // MARK: - The page address

    @Test("The page URL restores the https scheme Pen strips", arguments: [
        ("example.com", "https://example.com"),
        ("example.com/path?q=1", "https://example.com/path?q=1"),
        ("https://example.com", "https://example.com"),
        ("http://localhost:3000", "http://localhost:3000"),
        ("localhost:3000", "https://localhost:3000"),
        ("//cdn.example.com/x", "https://cdn.example.com/x"),
        ("about:blank", "about:blank"),
        ("  example.com  ", "https://example.com"),
    ])
    func pageURLRestoresScheme(stored: String, expected: String) {
        #expect(PenNode.BrowserData(url: stored).pageURL == expected)
    }

    @Test("An absent or blank URL has no page")
    func blankURLHasNoPage() {
        #expect(PenNode.BrowserData().pageURL == nil)
        #expect(PenNode.BrowserData(url: "").pageURL == nil)
        #expect(PenNode.BrowserData(url: "   ").pageURL == nil)
    }
}
