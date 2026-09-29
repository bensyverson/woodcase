//
//  PenTextLayoutTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Tests for text intrinsic sizing integration in the layout engine.
///
/// Uses a deterministic stub measurer so tests run via `swift test`
/// without needing Core Text. The stub returns predictable sizes:
/// width = characterCount * 8, height = fontSize (default 16).
/// When maxWidth constrains the text, it wraps: height scales up
/// proportionally to how many lines are needed.
struct PenTextLayoutTests {
    /// Deterministic text measurer for testing.
    /// Width = character count * 8 (simulating ~8pt per character).
    /// Height = fontSize (default 16). Wraps when maxWidth is set.
    static let stubMeasurer: TextMeasurer = { text, _, fontSize, _, _, _, _, maxWidth in
        let charWidth: Double = 8
        let lineHeight = fontSize ?? 16
        let naturalWidth = Double(text.count) * charWidth

        if let maxWidth, naturalWidth > maxWidth {
            let lines = ceil(naturalWidth / maxWidth)
            return (maxWidth, lineHeight * lines)
        }
        return (naturalWidth, lineHeight)
    }

    // MARK: - Basic Text Intrinsic Sizing

    @Test("Text node with fit_content sizing has non-zero dimensions")
    func textFitContentHasSize() throws {
        let doc = PenDocument(version: "0.0.1", children: [
            PenNode(
                id: "text1",
                common: PenNodeCommon(),
                kind: .text(PenNode.TextData(
                    content: .literal("Hello World")
                ))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc, textMeasurer: Self.stubMeasurer)
        let rect = try #require(rects["text1"])
        // "Hello World" = 11 chars → width = 88, height = 16
        #expect(rect.width == 88)
        #expect(rect.height == 16)
    }

    @Test("Longer text produces wider layout rect")
    func longerTextIsWider() throws {
        let shortDoc = PenDocument(version: "0.0.1", children: [
            PenNode(
                id: "short",
                common: PenNodeCommon(),
                kind: .text(PenNode.TextData(
                    content: .literal("Hi")
                ))
            ),
        ])
        let longDoc = PenDocument(version: "0.0.1", children: [
            PenNode(
                id: "long",
                common: PenNodeCommon(),
                kind: .text(PenNode.TextData(
                    content: .literal("Hello World, this is a longer string")
                ))
            ),
        ])
        let shortRect = try #require(PenLayoutEngine.layout(shortDoc, textMeasurer: Self.stubMeasurer)["short"])
        let longRect = try #require(PenLayoutEngine.layout(longDoc, textMeasurer: Self.stubMeasurer)["long"])
        #expect(longRect.width > shortRect.width)
    }

    @Test("Larger font size produces taller text rect")
    func largerFontProducesTallerRect() throws {
        let smallDoc = PenDocument(version: "0.0.1", children: [
            PenNode(
                id: "small",
                common: PenNodeCommon(),
                kind: .text(PenNode.TextData(
                    content: .literal("Hello"),
                    fontSize: .literal(12)
                ))
            ),
        ])
        let largeDoc = PenDocument(version: "0.0.1", children: [
            PenNode(
                id: "large",
                common: PenNodeCommon(),
                kind: .text(PenNode.TextData(
                    content: .literal("Hello"),
                    fontSize: .literal(48)
                ))
            ),
        ])
        let smallRect = try #require(PenLayoutEngine.layout(smallDoc, textMeasurer: Self.stubMeasurer)["small"])
        let largeRect = try #require(PenLayoutEngine.layout(largeDoc, textMeasurer: Self.stubMeasurer)["large"])
        // Same text, so same width (stub doesn't scale width by font size)
        #expect(smallRect.width == largeRect.width)
        // But taller: 12 vs 48
        #expect(largeRect.height == 48)
        #expect(smallRect.height == 12)
    }

    // MARK: - Fixed Width + Wrapping

    @Test("Text with fixed width and fit_content height wraps and grows taller")
    func fixedWidthWrapsText() throws {
        // "Hello World" = 11 chars → natural width = 88
        // Fixed width = 40 → wraps to ceil(88/40) = 3 lines → height = 48
        let doc = PenDocument(version: "0.0.1", children: [
            PenNode(
                id: "text1",
                common: PenNodeCommon(),
                kind: .text(PenNode.TextData(
                    width: .fixed(40),
                    content: .literal("Hello World")
                ))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc, textMeasurer: Self.stubMeasurer)
        let rect = try #require(rects["text1"])
        #expect(rect.width == 40, "Fixed width should be respected")
        #expect(rect.height == 48, "Text should wrap to 3 lines at 16pt each")
    }

    @Test("Text with fixed width and fixed height ignores text measurement")
    func fixedWidthAndHeightIgnoresText() throws {
        let doc = PenDocument(version: "0.0.1", children: [
            PenNode(
                id: "fixed",
                common: PenNodeCommon(),
                kind: .text(PenNode.TextData(
                    width: .fixed(200),
                    height: .fixed(50),
                    content: .literal("This text is very long but the box is fixed")
                ))
            ),
        ])
        let rect = try #require(PenLayoutEngine.layout(doc, textMeasurer: Self.stubMeasurer)["fixed"])
        #expect(rect.width == 200)
        #expect(rect.height == 50)
    }

    // MARK: - textGrowth Modes

    @Test("textGrowth fixedWidth uses explicit width, measures height")
    func textGrowthFixedWidth() throws {
        // "Hello World Test" = 16 chars → natural width = 128
        // Fixed width = 50 → wraps to ceil(128/50) = 3 lines → height = 48
        let doc = PenDocument(version: "0.0.1", children: [
            PenNode(
                id: "text1",
                common: PenNodeCommon(),
                kind: .text(PenNode.TextData(
                    width: .fixed(50),
                    content: .literal("Hello World Test"),
                    textGrowth: .fixedWidth
                ))
            ),
        ])
        let rect = try #require(PenLayoutEngine.layout(doc, textMeasurer: Self.stubMeasurer)["text1"])
        #expect(rect.width == 50, "fixedWidth textGrowth should use the explicit width")
        #expect(rect.height == 48, "Height should be measured from wrapped text content")
    }

    @Test("textGrowth fixedWidthHeight uses explicit dimensions, no measurement")
    func textGrowthFixedWidthHeight() throws {
        let doc = PenDocument(version: "0.0.1", children: [
            PenNode(
                id: "text1",
                common: PenNodeCommon(),
                kind: .text(PenNode.TextData(
                    width: .fixed(200),
                    height: .fixed(100),
                    content: .literal("Text content"),
                    textGrowth: .fixedWidthHeight
                ))
            ),
        ])
        let rect = try #require(PenLayoutEngine.layout(doc, textMeasurer: Self.stubMeasurer)["text1"])
        #expect(rect.width == 200)
        #expect(rect.height == 100)
    }

    // MARK: - Text Pushing Parent Layout

    @Test("fit_content frame sizes to its text child")
    func frameSizesToTextChild() throws {
        // "Hello" = 5 chars → width = 40, height = 16
        let doc = PenDocument(version: "0.0.1", children: [
            PenNode(
                id: "frame1",
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData(
                    children: [
                        PenNode(
                            id: "text1",
                            common: PenNodeCommon(),
                            kind: .text(PenNode.TextData(
                                content: .literal("Hello")
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc, textMeasurer: Self.stubMeasurer)
        let frameRect = try #require(rects["frame1"])
        let textRect = try #require(rects["text1"])

        #expect(textRect.width == 40)
        #expect(textRect.height == 16)
        #expect(frameRect.width == 40, "Frame fit_content width should match text width")
        #expect(frameRect.height == 16, "Frame fit_content height should match text height")
    }

    @Test("fit_content frame with padding sizes to text plus padding")
    func frameSizesToTextWithPadding() throws {
        let padding: Double = 16
        // "Hello" = 5 chars → width = 40, height = 16
        let doc = PenDocument(version: "0.0.1", children: [
            PenNode(
                id: "frame1",
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData(
                    padding: .uniform(.literal(padding)),
                    children: [
                        PenNode(
                            id: "text1",
                            common: PenNodeCommon(),
                            kind: .text(PenNode.TextData(
                                content: .literal("Hello")
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc, textMeasurer: Self.stubMeasurer)
        let frameRect = try #require(rects["frame1"])
        let textRect = try #require(rects["text1"])

        #expect(textRect.width == 40)
        #expect(frameRect.width == 40 + padding * 2)
        #expect(frameRect.height == 16 + padding * 2)
    }

    @Test("Multiple text children in horizontal frame each get measured")
    func multipleTextChildrenHorizontal() throws {
        // "First" = 5 chars → 40, "Second" = 6 chars → 48
        let doc = PenDocument(version: "0.0.1", children: [
            PenNode(
                id: "frame1",
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData(
                    layout: .horizontal,
                    children: [
                        PenNode(
                            id: "text1",
                            common: PenNodeCommon(),
                            kind: .text(PenNode.TextData(
                                content: .literal("First")
                            ))
                        ),
                        PenNode(
                            id: "text2",
                            common: PenNodeCommon(),
                            kind: .text(PenNode.TextData(
                                content: .literal("Second")
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc, textMeasurer: Self.stubMeasurer)
        let text1 = try #require(rects["text1"])
        let text2 = try #require(rects["text2"])
        let frame = try #require(rects["frame1"])

        #expect(text1.width == 40)
        #expect(text2.width == 48)
        #expect(text2.x == 40, "Second text starts after first")
        #expect(frame.width == 88, "Frame width is sum of text widths")
    }

    @Test("Text with gap between children")
    func textChildrenWithGap() throws {
        let doc = PenDocument(version: "0.0.1", children: [
            PenNode(
                id: "frame1",
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData(
                    layout: .horizontal,
                    gap: .literal(10),
                    children: [
                        PenNode(
                            id: "text1",
                            common: PenNodeCommon(),
                            kind: .text(PenNode.TextData(
                                content: .literal("Hello")
                            ))
                        ),
                        PenNode(
                            id: "text2",
                            common: PenNodeCommon(),
                            kind: .text(PenNode.TextData(
                                content: .literal("World")
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc, textMeasurer: Self.stubMeasurer)
        let text2 = try #require(rects["text2"])
        let frame = try #require(rects["frame1"])

        #expect(text2.x == 50, "Second text starts after first (40) + gap (10)")
        #expect(frame.width == 90, "Frame width = 40 + 10 + 40")
    }

    // MARK: - Edge Cases

    @Test("An unresolved variable reference measures as empty text, not as its name")
    func variableContentMeasuresAsEmpty() throws {
        let doc = PenDocument(version: "0.0.1", children: [
            PenNode(
                id: "text1",
                common: PenNodeCommon(),
                kind: .text(PenNode.TextData(content: .variable("headline")))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc, textMeasurer: Self.stubMeasurer)
        let rect = try #require(rects["text1"])
        #expect(rect.width == 0, "The variable name itself must not be measured")
        // Empty text still gets one line height (matching Pen's behavior)
        #expect(rect.height == 16)
    }

    @Test("Empty text content produces zero-size rect")
    func emptyTextContent() throws {
        let doc = PenDocument(version: "0.0.1", children: [
            PenNode(
                id: "text1",
                common: PenNodeCommon(),
                kind: .text(PenNode.TextData(
                    content: .literal("")
                ))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc, textMeasurer: Self.stubMeasurer)
        let rect = try #require(rects["text1"])
        #expect(rect.width == 0)
        // Empty text still gets one line height (matching Pencil behavior)
        #expect(rect.height == 16)
    }

    @Test("Text node with no content gets one line height")
    func noTextContent() throws {
        let doc = PenDocument(version: "0.0.1", children: [
            PenNode(
                id: "text1",
                common: PenNodeCommon(),
                kind: .text(PenNode.TextData())
            ),
        ])
        let rects = PenLayoutEngine.layout(doc, textMeasurer: Self.stubMeasurer)
        let rect = try #require(rects["text1"])
        #expect(rect.width == 0)
        // Empty text still gets one line height (matching Pencil behavior)
        #expect(rect.height == 16)
    }

    @Test("Text with fill_container width inside fixed frame uses parent width for wrapping")
    func fillContainerWidthUsesParentForWrapping() throws {
        // "Hello World Test!!" = 18 chars → natural width = 144
        // Parent width = 80, fill_container → text width = 80
        // Wraps: ceil(144/80) = 2 lines → height = 32
        let doc = PenDocument(version: "0.0.1", children: [
            PenNode(
                id: "frame1",
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData(
                    width: .fixed(80),
                    height: .fitContent(fallback: nil),
                    children: [
                        PenNode(
                            id: "text1",
                            common: PenNodeCommon(),
                            kind: .text(PenNode.TextData(
                                width: .fillContainer(fallback: nil),
                                content: .literal("Hello World Test!!")
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc, textMeasurer: Self.stubMeasurer)
        let textRect = try #require(rects["text1"])
        let frameRect = try #require(rects["frame1"])

        #expect(textRect.width == 80, "fill_container text should use parent width")
        #expect(textRect.height == 32, "Text should wrap to 2 lines")
        #expect(frameRect.height == 32, "Frame should fit to wrapped text height")
    }

    @Test("Nested frames with text: outer fit_content sizes to inner content")
    func nestedFramesWithText() throws {
        // "Test" = 4 chars → width = 32, height = 16
        let doc = PenDocument(version: "0.0.1", children: [
            PenNode(
                id: "outer",
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData(
                    padding: .uniform(.literal(10)),
                    children: [
                        PenNode(
                            id: "inner",
                            common: PenNodeCommon(),
                            kind: .frame(PenNode.FrameData(
                                padding: .uniform(.literal(5)),
                                children: [
                                    PenNode(
                                        id: "text1",
                                        common: PenNodeCommon(),
                                        kind: .text(PenNode.TextData(
                                            content: .literal("Test")
                                        ))
                                    ),
                                ]
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc, textMeasurer: Self.stubMeasurer)
        let textRect = try #require(rects["text1"])
        let innerRect = try #require(rects["inner"])
        let outerRect = try #require(rects["outer"])

        #expect(textRect.width == 32)
        #expect(innerRect.width == 32 + 10, "Inner frame = text + padding*2")
        #expect(outerRect.width == 32 + 10 + 20, "Outer frame = inner + padding*2")
    }
}
