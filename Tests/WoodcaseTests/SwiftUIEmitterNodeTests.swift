//
//  SwiftUIEmitterNodeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What one node becomes in emitted SwiftUI, over small synthetic documents. The
/// fixture goldens (``SwiftUIEmitterGoldenTests``) pin whole files; these pin the
/// individual decisions and the cases no fixture carries.
struct SwiftUIEmitterNodeTests {
    // MARK: - Layout

    @Test("A horizontal frame is an HStack aligned to Pen's default start, spaced by its gap")
    func horizontalStack() throws {
        let code = try body(frame: ##""gap": 8, "children": [\##(rect)]"##)
        #expect(code.contains("HStack(alignment: .top, spacing: 8) {"))
    }

    @Test("A vertical frame is a VStack; alignItems end is trailing")
    func verticalStack() throws {
        let code = try body(frame: ##""layout": "vertical", "alignItems": "end", "children": [\##(rect)]"##)
        #expect(code.contains("VStack(alignment: .trailing, spacing: 0) {"))
    }

    @Test("space_between puts a zero-minimum Spacer between children, and only between")
    func spaceBetween() throws {
        let code = try body(frame: ##""width": 300, "justifyContent": "space_between", "children": [\##(rect), \##(rect)]"##)
        #expect(code.components(separatedBy: "Spacer(minLength: 0)").count == 2)
    }

    @Test("A layout-none frame is a top-leading ZStack whose children are offset by x and y")
    func absoluteLayout() throws {
        let child = ##"{"type": "rectangle", "id": "c", "width": 10, "height": 10, "x": 20, "y": 30, "fill": "#FF0000"}"##
        let code = try body(frame: ##""layout": "none", "width": 100, "height": 100, "children": [\##(child)]"##)
        #expect(code.contains("ZStack(alignment: .topLeading) {"))
        #expect(code.contains(".offset(x: 20, y: 30)"))
    }

    @Test("A layout-none frame with no size is framed at 0×0, its children overhanging from its corner")
    func sizelessAbsoluteFrameIsZero() throws {
        // Pen settles it at 0×0 whatever it holds (leaf Jg0BOv); left unframed, the ZStack
        // would size itself to its children.
        let child = ##"{"type": "rectangle", "id": "c", "width": 80, "height": 40, "x": 10, "y": 10, "fill": "#FF00FF"}"##
        let inner = ##"{"type": "frame", "id": "f", "layout": "none", "fill": "#808080", "children": [\##(child)]}"##
        let code = try body(frame: ##""width": 300, "height": 300, "children": [\##(inner)]"##)
        #expect(code.contains(".frame(width: 0, height: 0, alignment: .topLeading)"))
    }

    @Test("fit_content(N) on a layout-none frame is exactly N, not at least N")
    func absoluteFrameFitContentIsItsFallback() throws {
        let child = ##"{"type": "rectangle", "id": "c", "width": 80, "height": 40, "x": 10, "y": 10, "fill": "#FF00FF"}"##
        let inner = ##"{"type": "frame", "id": "f", "layout": "none", "width": "fit_content(30)", "height": 20, "children": [\##(child)]}"##
        let code = try body(frame: ##""width": 300, "height": 300, "children": [\##(inner)]"##)
        #expect(code.contains(".frame(width: 30, height: 20, alignment: .topLeading)"))
        #expect(!code.contains("minWidth: 30"))
    }

    @Test("fill_container is a zero minimum and an infinite maximum; fixed sizes are a frame")
    func sizing() throws {
        let child = ##"{"type": "rectangle", "id": "c", "width": "fill_container", "height": 40, "fill": "#FF0000"}"##
        let code = try body(frame: ##""width": 200, "height": 50, "children": [\##(child)]"##)
        #expect(code.contains(".frame(minWidth: 0, maxWidth: .infinity)"))
        #expect(code.contains(".frame(height: 40)"))
        #expect(code.contains(".frame(width: 200, height: 50, alignment: .topLeading)"))
    }

    @Test("A fill_container stack shrinks below its content, as Pen's flex item does, on both axes")
    func fillShrinksBelowItsContent() throws {
        let wide = ##"{"type": "rectangle", "id": "w", "width": 300, "height": 300, "fill": "#FF0000"}"##
        let fill = ##"{"type": "frame", "id": "f", "width": "fill_container", "height": "fill_container", "children": [\##(wide)]}"##
        let code = try body(frame: ##""layout": "vertical", "width": 100, "height": 100, "children": [\##(fill)]"##)
        #expect(code.contains(".frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)"))
    }

    @Test("Padding of four values is EdgeInsets in top, leading, bottom, trailing order")
    func padding() throws {
        let code = try body(frame: ##""padding": [1, 2, 3, 4], "children": [\##(rect)]"##)
        #expect(code.contains(".padding(EdgeInsets(top: 1, leading: 4, bottom: 3, trailing: 2))"))
    }

    @Test("A clipped frame with a radius clips to a circular rounded rect and paints in it")
    func clipAndRadius() throws {
        let code = try body(frame: ##""clip": true, "cornerRadius": 8, "fill": "#00FF0080", "children": [\##(rect)]"##)
        #expect(code.contains(".background(Color(hex: 0x00FF00, opacity: 0.502), in: .rect(cornerRadius: 8, style: .circular))"))
        #expect(code.contains(".clipShape(.rect(cornerRadius: 8, style: .circular))"))
    }

    // MARK: - Shapes

    @Test("An ellipse is an Ellipse filled with its color")
    func ellipse() throws {
        let child = ##"{"type": "ellipse", "id": "e", "width": 30, "height": 20, "fill": "#0000FF"}"##
        let code = try body(frame: ##""children": [\##(child)]"##)
        #expect(code.contains("Ellipse()"))
        #expect(code.contains(".fill(Color(hex: 0x0000FF))"))
    }

    @Test("A shape with no size is zero-sized, not greedy as a bare Shape is; an empty group has no box to size")
    func sizelessIsZero() throws {
        let child = ##"{"type": "rectangle", "id": "r", "fill": "#FF0000"}"##
        let group = ##"{"type": "group", "id": "g", "children": []}"##
        let code = try body(frame: ##""children": [\##(child), \##(group)]"##)
        #expect(code.components(separatedBy: ".frame(width: 0, height: 0)").count == 2)
        // The frame is a horizontal stack, where a group sizes to its children's union
        // (`PenGroupFlow`, leaf cqBw2i; it was a `ZStack` before); with none, it is empty.
        #expect(code.contains("PenGroupFlow(offsets: []) {}"))
    }

    @Test("A disabled node is not emitted")
    func disabledNode() throws {
        let child = ##"{"type": "ellipse", "id": "e", "enabled": false, "width": 30, "height": 20}"##
        let code = try body(frame: ##""children": [\##(child)]"##)
        #expect(!code.contains("Ellipse()"))
    }

    // MARK: - Text

    @Test("Text carries its font through penFont, weight and italic and line height included")
    func textFont() throws {
        let text = ##"{"type": "text", "id": "t", "content": "Hi", "fontFamily": "Inter", "fontSize": 24, "fontWeight": "bold", "fontStyle": "italic", "lineHeight": 1.5, "letterSpacing": 2, "fill": "#333333"}"##
        let code = try body(frame: ##""children": [\##(text)]"##)
        #expect(code.contains(##"Text("Hi")"##))
        #expect(code.contains(".tracking(2)"))
        #expect(code.contains(##".penFont("Inter", size: 24, weight: 700, italic: true, lineHeight: 1.5)"##))
        #expect(code.contains(".foregroundStyle(Color(hex: 0x333333))"))
    }

    @Test("Fixed-width centered text wraps: it centers, fills and grows vertically")
    func fixedWidthText() throws {
        let text = ##"{"type": "text", "id": "t", "content": "Hi", "textGrowth": "fixed-width", "width": "fill_container", "textAlign": "center"}"##
        let code = try body(frame: ##""layout": "vertical", "width": 200, "children": [\##(text)]"##)
        #expect(code.contains(".multilineTextAlignment(.center)"))
        #expect(code.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(code.contains(".frame(minWidth: 0, maxWidth: .infinity)\n"))
    }

    @Test("Auto-growth text never wraps: it keeps its ideal size even where its row is too narrow")
    func autoTextKeepsItsIdealSize() throws {
        let text = ##"{"type": "text", "id": "t", "content": "Hi", "fill": "#333333"}"##
        let code = try body(frame: ##""width": 40, "children": [\##(text)]"##)
        #expect(code.contains(".foregroundStyle(Color(hex: 0x333333))\n                .fixedSize()\n"))
    }

    @Test("Text content is escaped, and markdown-looking copy is verbatim")
    func textEscaping() throws {
        let text = ##"{"type": "text", "id": "t", "content": "a \"b\" \\ c\n*d*"}"##
        let code = try body(frame: ##""children": [\##(text)]"##)
        #expect(code.contains(##"Text(verbatim: "a \"b\" \\ c\n*d*")"##))
    }

    @Test("Copy SwiftUI would autolink — an email address, a URL — is verbatim")
    func autolinkedCopyIsVerbatim() throws {
        // A `LocalizedStringKey` parses Markdown, which links a bare address and tints it:
        // woodcase-app's "you@example.com" placeholder came out blue.
        for copy in ["you@example.com", "see https://pen.dev", "www.pen.dev"] {
            let text = ##"{"type": "text", "id": "t", "content": "\##(copy)"}"##
            let code = try body(frame: ##""children": [\##(text)]"##)
            #expect(code.contains("Text(verbatim: \"\(copy)\")"), "\(copy)")
        }
    }

    // MARK: - What this emitter does not write yet

    @Test("An unhandled node is a marked placeholder and a warning naming it")
    func unhandledNode() throws {
        // Paths are drawn since the shapes slice; a browser node still is not.
        let browser = ##"{"type": "browser", "id": "p1", "name": "squiggle", "width": 10, "height": 12}"##
        let diagnostics = PenDiagnosticCollector()
        let code = try body(frame: ##""children": [\##(browser)]"##, diagnostics: diagnostics)
        #expect(code.contains(##"// woodcase: browser "squiggle" is not emitted yet"##))
        #expect(code.contains("Color.clear"))
        #expect(code.contains(".frame(width: 10, height: 12)"))
        let warning = try #require(diagnostics.diagnostics.first { $0.nodeID == "p1" })
        #expect(warning.severity == .warning)
        #expect(warning.stage == .codeGen)
    }

    @Test("A property this slice does not emit is a warning, and the node is still written")
    func unemittedProperty() throws {
        let child = ##"{"type": "rectangle", "id": "r1", "width": 10, "height": 10, "rotation": "$turn", "fill": {"type": "shader", "url": "s.glsl"}}"##
        let diagnostics = PenDiagnosticCollector()
        let code = try body(frame: ##""children": [\##(child)]"##, diagnostics: diagnostics)
        // With no paint it can draw, the rectangle is its frame's empty space.
        #expect(code.contains("Color.clear"))
        #expect(code.contains(".frame(width: 10, height: 10)"))
        let warnings = diagnostics.diagnostics.filter { $0.nodeID == "r1" }
        #expect(warnings.count == 2)
    }

    @Test("A color variable is not resolved yet: a warning, and no color written")
    func colorVariable() throws {
        let child = ##"{"type": "rectangle", "id": "r1", "width": 10, "height": 10, "fill": "$brand"}"##
        let diagnostics = PenDiagnosticCollector()
        let code = try body(frame: ##""children": [\##(child)]"##, diagnostics: diagnostics)
        #expect(!code.contains("Color(hex:"))
        #expect(diagnostics.diagnostics.contains { $0.nodeID == "r1" && $0.message.contains("$brand") })
    }

    @Test("A component is emitted under Components/, without a notice")
    func componentsAreEmitted() throws {
        let json = ##"{"version": "2.17", "children": [{"type": "frame", "id": "k", "name": "Card", "reusable": true}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let diagnostics = PenDiagnosticCollector()
        let result = try SwiftUIEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document), pages: [],
            theme: ThemeAnalyzer.analyze(document), diagnostics: diagnostics
        )
        #expect(result.files.contains { $0.path == "Sources/PenUI/Components/Card.swift" })
        #expect(!diagnostics.diagnostics.contains { $0.nodeID == "k" })
    }

    // MARK: - Helpers

    private let rect = ##"{"type": "rectangle", "id": "r", "width": 10, "height": 10, "fill": "#FF0000"}"##

    /// Emit a one-page document whose root frame carries `frame`'s keys, and return the page's source.
    private func body(frame keys: String, diagnostics: PenDiagnosticCollector? = nil) throws -> String {
        let json = ##"{"version": "2.17", "children": [{"type": "frame", "id": "root", "name": "Board", \##(keys)}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let result = try SwiftUIEmitter.emit(
            document: document, components: [], pages: PageAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document), diagnostics: diagnostics
        )
        return try #require(result.files.first { $0.path.hasSuffix("Pages/Board.swift") }).content
    }
}
