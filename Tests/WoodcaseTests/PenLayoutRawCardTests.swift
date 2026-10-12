//
//  PenLayoutRawCardTests.swift
//  WoodcaseTests
//

import Foundation
import Synchronization
import Testing
@testable import Woodcase

/// A note, prompt or context an editor draws raw grows to fit its raw markdown: its
/// height is the most of its set height, its styled text's and its raw text's (Ben's
/// ruling 2026-10-12, leaf `WfbzYQ`). Without the card named raw, layout is unchanged.
struct PenLayoutRawCardTests {
    /// Markdown whose source is far longer than its display text.
    static let source = "**a** **b** **c** **d** **e** **f** **g** **h** **i** **j**"

    /// The options that draw `N1` raw.
    static let raw = PenLayoutOptions(rawBodies: ["N1"])

    /// A board holding a title, the note `N1` and a footer, hugging its content.
    static func json(content: String = source, height: Int = 40, type: String = "note") -> String {
        let encoded = String(data: try! JSONEncoder().encode(content), encoding: .utf8)!
        return """
        {"version": "2.17", "children": [
          {"id": "B", "type": "frame", "x": 0, "y": 0, "width": 400, "height": "fit_content",
           "layout": "vertical", "gap": 4,
           "children": [
             {"id": "title", "type": "text", "content": "A board"},
             {"id": "N1", "type": "\(type)", "width": 160, "height": \(height), "content": \(encoded)},
             {"id": "footer", "type": "text", "content": "The end"}
           ]},
          {"id": "Other", "type": "frame", "x": 600, "y": 0, "layout": "vertical",
           "children": [ { "id": "otherText", "type": "text", "content": "Elsewhere" } ] }
        ]}
        """
    }

    private let measurer = RecordingTextMeasurer().measurer

    private func document(content: String = source, height: Int = 40, type: String = "note") throws -> PenDocument {
        try PenParser.parse(Self.json(content: content, height: height, type: type))
    }

    private func card(in document: PenDocument) throws -> PenNode {
        guard case let .frame(frame) = document.children.first?.kind else { throw CocoaError(.coderInvalidValue) }
        return try #require(frame.children?.first { $0.id == "N1" })
    }

    /// The height ``RecordingTextMeasurer`` gives a text set in the card, with the card's
    /// insets.
    private func grown(_ text: String, in card: PenNode, width: Double = 160) throws -> Double {
        let insets = try #require(PenPostIt.bodyInsets(of: card))
        let natural = Double(text.count) * RecordingTextMeasurer.characterWidth
        let lines = (natural / (width - insets.horizontal)).rounded(.up)
        return lines * RecordingTextMeasurer.lineHeight + insets.vertical
    }

    // MARK: - The height

    @Test("A card named raw grows to fit its raw text", arguments: ["note", "prompt", "context"])
    func rawCardGrows(type: String) throws {
        let document = try document(type: type)
        let card = try card(in: document)
        let rawRect = try #require(PenLayoutEngine.layout(document, textMeasurer: measurer, options: Self.raw)["N1"])
        let styled = try #require(PenLayoutEngine.layout(document, textMeasurer: measurer)["N1"])

        #expect(rawRect.width == 160)
        #expect(try rawRect.height == grown(Self.source, in: card))
        #expect(rawRect.height > styled.height)
    }

    @Test("Without the card named raw, layout is unchanged")
    func unnamedIsUnchanged() throws {
        let document = try document()
        let card = try card(in: document)
        let plain = PenLayoutEngine.layout(document, textMeasurer: measurer)
        #expect(PenLayoutEngine.layout(document, textMeasurer: measurer, options: PenLayoutOptions()) == plain)
        #expect(PenLayoutEngine.layout(document, textMeasurer: measurer, options: PenLayoutOptions(rawBodies: ["title"])) == plain)
        #expect(try plain["N1"]?.height == max(40, grown("a b c d e f g h i j", in: card)))
    }

    @Test("The raw text is measured verbatim in the card's style, with no runs and no indents")
    func rawRequestIsVerbatim() throws {
        let document = try document(content: "- **bold** item\n  - nested")
        let card = try card(in: document)
        let requests = Mutex<[PenTextMeasureRequest]>([])
        let base = measurer
        _ = PenLayoutEngine.layout(document, textMeasurer: { request in
            requests.withLock { $0.append(request) }
            return base(request)
        }, options: Self.raw)

        let style = try #require(card.noteTextStyle)
        let insets = try #require(PenPostIt.bodyInsets(of: card))
        let raw = try #require(requests.withLock { $0 }.first { $0.text == "- **bold** item\n  - nested" })
        #expect(raw.runs.isEmpty)
        #expect(raw.indents.isEmpty)
        #expect(raw.fontSize == style.fontSize)
        #expect(raw.lineHeight == style.lineHeight)
        #expect(raw.maxWidth == 160 - insets.horizontal)
    }

    @Test("A styled text taller than the raw keeps the styled height")
    func styledTallerWins() throws {
        let document = try document(content: "**bold** words")
        let card = try card(in: document)
        let insets = try #require(PenPostIt.bodyInsets(of: card))
        // Styled text (it has runs) measures 200 tall; raw text one line.
        let tallStyled: TextMeasurer = { request in (40, request.runs.isEmpty ? 16 : 200) }
        let rect = try #require(PenLayoutEngine.layout(document, textMeasurer: tallStyled, options: Self.raw)["N1"])
        #expect(rect.height == 200 + insets.vertical)
    }

    @Test("A set height taller than both texts is kept")
    func setHeightWins() throws {
        let document = try document(height: 400)
        let rect = try #require(PenLayoutEngine.layout(document, textMeasurer: measurer, options: Self.raw)["N1"])
        #expect(rect.height == 400)
    }

    // MARK: - Every entry point

    @Test("Every layout entry point grows a card named raw")
    func everyEntryPoint() throws {
        let document = try document()
        let expected = PenLayoutEngine.layout(document, textMeasurer: measurer, options: Self.raw)
        let styled = PenLayoutEngine.layout(document, textMeasurer: measurer)
        #expect(expected["N1"] != styled["N1"])

        #expect(PenLayoutEngine.layoutIncremental(
            document, previousRects: styled, dirtyNodeIDs: ["N1"], textMeasurer: measurer, options: Self.raw
        ) == expected)
        var cache: [String: PenLayoutEngine.MeasurementCacheEntry] = [:]
        #expect(PenLayoutEngine.layoutIncremental(
            document, previousRects: styled, dirtyNodeIDs: ["N1"], textMeasurer: measurer, options: Self.raw,
            measurementCache: &cache
        ) == expected)
        var other: [String: PenLayoutEngine.MeasurementCacheEntry] = [:]
        #expect(PenLayoutEngine.layoutIncremental(
            document, previousRects: styled, invalidation: PenLayoutInvalidation(nodes: ["N1"]),
            textMeasurer: measurer, options: Self.raw, measurementCache: &other
        ) == expected)
        let subtree = PenLayoutEngine.layoutSubtree(
            rootID: "B", in: document, existingRects: styled, textMeasurer: measurer, options: Self.raw
        )
        #expect(subtree["N1"] == expected["N1"])
        var subtreeCache: [String: PenLayoutEngine.MeasurementCacheEntry] = [:]
        let cached = PenLayoutEngine.layoutSubtree(
            rootID: "B", in: document, existingRects: styled, textMeasurer: measurer, options: Self.raw,
            measurementCache: &subtreeCache
        )
        #expect(cached["N1"] == expected["N1"])
        #expect(PenLayoutState(document: document, textMeasurer: measurer, options: Self.raw).rects == expected)
    }

    // MARK: - Toggling

    @Test("Toggling a card raw and back on a state lays it out each way, as a full layout would")
    func stateTogglesRawness() throws {
        let document = try document()
        var state = PenLayoutState(document: document, textMeasurer: measurer)
        let styled = state.rects

        let toRaw = state.update(to: document, invalidation: PenLayoutInvalidation(), options: Self.raw)
        #expect(state.options == Self.raw)
        #expect(state.rects == PenLayoutEngine.layout(document, textMeasurer: measurer, options: Self.raw))
        #expect(toRaw.resized == ["N1", "B"])
        #expect(toRaw.moved == ["footer"])
        #expect(toRaw.affectedRoots == ["B"])

        let back = state.update(to: document, invalidation: PenLayoutInvalidation(), options: PenLayoutOptions())
        #expect(state.rects == styled)
        #expect(back.resized == ["N1", "B"])

        // An update that does not name options keeps the state's.
        _ = state.update(to: document, invalidation: PenLayoutInvalidation(), options: Self.raw)
        _ = state.update(to: document, invalidation: PenLayoutInvalidation(nodes: ["title"]))
        #expect(state.rects == PenLayoutEngine.layout(document, textMeasurer: measurer, options: Self.raw))
    }

    @Test("A hypothetical on a raw state keeps the card raw")
    func hypotheticalKeepsRawness() throws {
        let document = try document()
        let state = PenLayoutState(document: document, textMeasurer: measurer, options: Self.raw)
        #expect(state.rects["N1"] != PenLayoutEngine.layout(document, textMeasurer: measurer)["N1"])
        let change = state.hypothetical([.move("footer", toIndex: 0)])
        #expect(change.rects["N1"] == nil || change.rects["N1"]?.height == state.rects["N1"]?.height)
        #expect(change.applied(to: state.rects)["N1"]?.height == state.rects["N1"]?.height)
    }

    @Test("A rawness change is an invalidation a host with its own measurement cache passes")
    func rawnessChangeIsAnInvalidation() throws {
        let document = try document()
        let invalidation = Self.raw.invalidation(from: PenLayoutOptions())
        #expect(invalidation == PenLayoutInvalidation(nodes: ["N1"]))
        #expect(PenLayoutOptions().invalidation(from: Self.raw) == invalidation)
        #expect(Self.raw.invalidation(from: Self.raw).isEmpty)

        let full = PenLayoutEngine.layout(document, textMeasurer: measurer)
        var cache: [String: PenLayoutEngine.MeasurementCacheEntry] = [:]
        // A first incremental pass fills the cache, as a host's pipeline does.
        let styled = PenLayoutEngine.layoutIncremental(
            document, previousRects: full, invalidation: PenLayoutInvalidation(roots: ["B"]),
            textMeasurer: measurer, measurementCache: &cache
        )
        let raw = PenLayoutEngine.layoutIncremental(
            document, previousRects: styled, invalidation: invalidation,
            textMeasurer: measurer, options: Self.raw, measurementCache: &cache
        )
        #expect(raw == PenLayoutEngine.layout(document, textMeasurer: measurer, options: Self.raw))
        #expect(raw != styled)
        let back = PenLayoutEngine.layoutIncremental(
            document, previousRects: raw, invalidation: PenLayoutOptions().invalidation(from: Self.raw),
            textMeasurer: measurer, measurementCache: &cache
        )
        #expect(back == full)
    }

    @Test("A renderer's drawing options give layout the same raw cards")
    func drawingOptionsCarryRawness() {
        #expect(PenPostIt.DrawingOptions(rawBodies: ["N1"]).layoutOptions == Self.raw)
        #expect(Self.raw.bodyText(for: "N1") == .raw)
        #expect(Self.raw.bodyText(for: "title") == .styled)
    }
}
