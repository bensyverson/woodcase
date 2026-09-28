//
//  SwiftUIEmitterThemeReadTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How emitted views read the document's variables: through the `PenTheme` in the
/// environment (`theme.bgPage`), a context node setting its axes for its subtree
/// (`.penTheme(mode: .dark)`), and props and instances whose values are variables.
/// ``SwiftUIEmitterThemeTests`` covers the theme file itself.
struct SwiftUIEmitterThemeReadTests {
    private static let themes = ##"{"mode": ["light", "dark"], "density": ["default", "compact"]}"##
    private static let variables = ##"""
    {"bg": {"type": "color", "value": [{"theme": {"mode": "light"}, "value": "#FFFFFF"}, {"theme": {"mode": "dark"}, "value": "#1A1A1A"}]},
     "veil": {"type": "color", "value": [{"theme": {"mode": "light"}, "value": "#00000020"}, {"theme": {"mode": "dark"}, "value": "#FFFFFF20"}]},
     "ink": {"type": "color", "value": "#222222"},
     "space": {"type": "number", "value": [{"theme": {"density": "default"}, "value": 16}, {"theme": {"density": "compact"}, "value": 10}]},
     "size": {"type": "number", "value": 14},
     "family": {"type": "string", "value": "Inter"},
     "greeting": {"type": "string", "value": "Hello"}}
    """##

    // MARK: - Reads

    @Test("A page that reads a variable declares the environment's theme and reads it by name")
    func pageReadsTheme() throws {
        let page = try Self.page(SwiftUIFixtures.emit("parser-themed-variables"), named: "Container")
        #expect(page.contains("    @Environment(\\.penTheme) private var theme\n"))
        #expect(page.contains(".background(theme.bgColor)"))
        #expect(page.contains(".penFont(size: theme.textSize)"))
    }

    @Test("A page that reads no variable declares no theme")
    func noReads() throws {
        let page = try SwiftUIFixtures.page("layout-gap")
        #expect(!page.content.contains("penTheme"))
    }

    @Test("Colour variables paint fills, strokes, text, gradient stops and shadows")
    func colours() throws {
        let child = ##"""
        {"type": "rectangle", "id": "r", "width": 20, "height": 20, "fill": "$bg", "stroke": "$ink", "strokeWidth": 1, "strokeAlignment": "center",
         "effect": {"type": "shadow", "color": "$veil", "blur": 4}},
        {"type": "rectangle", "id": "g", "width": 20, "height": 20,
         "fill": {"type": "gradient", "gradientType": "linear", "colors": [{"color": "$bg", "position": 0}, {"color": "#FF0000", "position": 1}]}},
        {"type": "text", "id": "t", "content": "Hi", "fill": "$ink"}
        """##
        let diagnostics = PenDiagnosticCollector()
        let page = try Self.board(child, diagnostics: diagnostics)
        #expect(page.contains(".fill(theme.bg)"))
        #expect(page.contains(".stroke(theme.ink, lineWidth: 1)"))
        #expect(page.contains(".penDropShadow(PenSilhouette(Rectangle(), stroke: Rectangle().penStroke(.center, lineWidth: 1)), color: theme.veil, radius: 2"))
        #expect(page.contains(".init(color: theme.bg, location: 0)"))
        #expect(page.contains(".foregroundStyle(theme.ink)"))
        #expect(!diagnostics.diagnostics.contains { $0.message.contains("variable") })
    }

    @Test("A translucent themed colour keeps the fills under it; an opaque one covers them")
    func themedOpacity() throws {
        let covered = try Self.board(##"{"type": "rectangle", "id": "r", "width": 20, "height": 20, "fill": ["#FF0000", "$bg"]}"##)
        #expect(covered.contains(".fill(theme.bg)") && !covered.contains("0xFF0000"))
        let veiled = try Self.board(##"{"type": "rectangle", "id": "r", "width": 20, "height": 20, "fill": ["#FF0000", "$veil"]}"##)
        #expect(veiled.contains(".fill(theme.veil)") && veiled.contains(".background(Color(hex: 0xFF0000)"))
    }

    @Test("Number and string variables set gaps, padding, radii, stroke widths and fonts")
    func numbersAndStrings() throws {
        let child = ##"""
        {"type": "frame", "id": "f", "layout": "vertical", "gap": "$space", "padding": ["$space", 4], "cornerRadius": "$space",
         "fill": "#EEEEEE", "stroke": "#000000", "strokeWidth": "$size", "strokeAlignment": "center",
         "children": [{"type": "text", "id": "t", "content": "Hi", "fontFamily": "$family", "fontSize": "$size", "letterSpacing": "$size", "fill": "#000000"},
                      {"type": "text", "id": "u", "content": "Yo", "fill": "#000000"}]}
        """##
        let diagnostics = PenDiagnosticCollector()
        let page = try Self.board(child, diagnostics: diagnostics)
        #expect(page.contains("VStack(alignment: .leading, spacing: theme.space) {"))
        #expect(page.contains(".padding(.horizontal, 4)\n") && page.contains(".padding(.vertical, theme.space)\n"))
        #expect(page.contains(".rect(cornerRadius: theme.space, style: .circular)"))
        #expect(page.contains("lineWidth: theme.size"))
        #expect(page.contains(".penFont(theme.family, size: theme.size)"))
        #expect(page.contains(".tracking(theme.size)"))
        #expect(!diagnostics.diagnostics.contains { $0.message.contains("variable") })
    }

    @Test("A shadow's blur and offset, a layer blur and a background blur read their number variables through PenTheme")
    func effectVariables() throws {
        let child = ##"""
        {"type": "rectangle", "id": "r", "width": 20, "height": 20, "fill": "#FF0000",
         "effect": {"type": "shadow", "color": "#000000", "blur": "$space", "offset": {"x": "$size", "y": "$size"}}},
        {"type": "rectangle", "id": "b", "width": 20, "height": 20, "fill": "#FF0000", "effect": {"type": "blur", "radius": "$space"}},
        {"type": "rectangle", "id": "g", "width": 20, "height": 20, "fill": "#FFFFFF33", "effect": {"type": "background_blur", "radius": "$space"}}
        """##
        let diagnostics = PenDiagnosticCollector()
        let page = try Self.board(child, diagnostics: diagnostics)
        #expect(page.contains(".penDropShadow(Rectangle(), color: Color(hex: 0x000000), radius: theme.space / 2, x: theme.size, y: theme.size)"))
        #expect(page.contains(".blur(radius: theme.space / 2)"))
        #expect(page.contains(".penBackgroundBlur(Rectangle(), radius: theme.space)"))
        #expect(!diagnostics.diagnostics.contains { $0.message.contains("variable") })
    }

    @Test("A rotation variable is read through PenTheme, and a fixed-size stack child's turned frame is computed at runtime")
    func rotationVariable() throws {
        let diagnostics = PenDiagnosticCollector()
        let child = ##"{"type": "rectangle", "id": "r", "width": 20, "height": 20, "fill": "#FF0000", "rotation": "$space"}"##
        let page = try Self.board(child, diagnostics: diagnostics)
        #expect(page.contains(".rotationEffect(.degrees(-theme.space))"))
        #expect(page.contains(
            ".frame(width: abs(cos((theme.space * Double.pi / 180))) * 20 + abs(sin((theme.space * Double.pi / 180))) * 20, "
                + "height: abs(sin((theme.space * Double.pi / 180))) * 20 + abs(cos((theme.space * Double.pi / 180))) * 20)"
        ))
        #expect(!diagnostics.diagnostics.contains { $0.message.contains("variable") })
    }

    @Test("A gradient stop's position variable is read through PenTheme")
    func gradientStopPositionVariable() throws {
        let diagnostics = PenDiagnosticCollector()
        let child = ##"""
        {"type": "rectangle", "id": "r", "width": 20, "height": 20,
         "fill": {"type": "gradient", "gradientType": "linear", "colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FF", "position": "$space"}]}}
        """##
        let page = try Self.board(child, diagnostics: diagnostics)
        #expect(page.contains(".init(color: Color(hex: 0x0000FF), location: theme.space)"))
        #expect(!diagnostics.diagnostics.contains { $0.message.contains("variable") })
    }

    @Test("A per-side stroke width variable is read through PenTheme")
    func perSideStrokeWidthVariable() throws {
        let diagnostics = PenDiagnosticCollector()
        let child = ##"""
        {"type": "rectangle", "id": "r", "width": 20, "height": 20, "fill": "#FFFFFF", "stroke": "#000000",
         "strokeWidth": {"top": "$space", "right": 2, "bottom": 2, "left": 2}}
        """##
        let page = try Self.board(child, diagnostics: diagnostics)
        #expect(page.contains("EdgeInsets(top: theme.space, leading: 2, bottom: 2, trailing: 2)"))
        #expect(!diagnostics.diagnostics.contains { $0.message.contains("variable") })
    }

    @Test("Text content reads a string variable; a name no variable has is the literal it was")
    func textContent() throws {
        let page = try Self.board(##"{"type": "text", "id": "t", "content": "$greeting"}, {"type": "text", "id": "u", "content": "$186"}"##)
        #expect(page.contains("Text(theme.greeting)"))
        #expect(page.contains("Text(\"$186\")"))
    }

    @Test("A variable of the wrong type is reported and left out")
    func wrongType() throws {
        let diagnostics = PenDiagnosticCollector()
        let page = try Self.board(##"{"type": "rectangle", "id": "r", "width": 20, "height": 20, "fill": "$space"}"##, diagnostics: diagnostics)
        #expect(!page.contains("theme.space"))
        #expect(diagnostics.diagnostics.contains { $0.message.contains("the number variable $space as a colour") })
    }

    // MARK: - Context nodes

    @Test("A context node sets its axes for its subtree")
    func contextNode() throws {
        let page = try Self.page(SwiftUIFixtures.emit("render-theme-axis"), named: "Special")
        #expect(page.contains(".penTheme(mode: .dark)"))
        #expect(!page.contains("PenThemeReader"))
    }

    @Test("A context node whose subtree reads the theme reads it through a PenThemeReader under its axes")
    func contextReader() throws {
        let child = ##"""
        {"type": "frame", "id": "d", "theme": {"mode": "dark", "density": "compact"}, "width": 20, "height": 20, "fill": "$bg",
         "children": [{"type": "text", "id": "t", "content": "Hi", "fill": "$ink"}]}
        """##
        let page = try Self.board(child)
        #expect(page.contains("PenThemeReader { theme in\n"))
        #expect(page.contains("}\n            .penTheme(density: .compact, mode: .dark)\n"))
        // Every read is inside the reader, so the page itself declares no theme.
        #expect(!page.contains("@Environment(\\.penTheme)"))
    }

    @Test("A context node naming an axis the document lacks is reported and ignored")
    func unknownAxis() throws {
        let diagnostics = PenDiagnosticCollector()
        let page = try Self.board(##"{"type": "frame", "id": "d", "theme": {"tint": "sand"}, "width": 20, "height": 20}"##, diagnostics: diagnostics)
        // The view's body, not its previews, which set every theme variant on purpose.
        let body = try #require(page.components(separatedBy: "#Preview").first)
        #expect(!body.contains(".penTheme("))
        #expect(diagnostics.diagnostics.contains { $0.message.contains("tint") })
    }

    // MARK: - Components

    @Test("A colour prop that defaults to a variable is optional, and the paint falls back to the theme")
    func themedPropDefault() throws {
        let swatch = ##"""
        {"type": "frame", "id": "W", "name": "Swatch", "reusable": true, "metadata": {"_props": {"tint": "Dot"}},
         "children": [{"type": "rectangle", "id": "D", "name": "Dot", "width": 10, "height": 10, "fill": "$bg"}]}
        """##
        let result = try SwiftUIEmitterThemeTests.emit(themes: Self.themes, variables: Self.variables, children: swatch)
        let file = try #require(result.files.first { $0.path.hasSuffix("Components/Swatch.swift") }).content
        #expect(file.contains("    public let tint: Color?\n"))
        #expect(file.contains("public init(tint: Color? = nil)"))
        #expect(file.contains(".fill(tint ?? theme.bg)"))
    }

    @Test("An instance passes a variable as the caller's theme reads it, and a themed instance sets its axes")
    func themedInstance() throws {
        let swatch = ##"""
        {"type": "frame", "id": "W", "name": "Swatch", "reusable": true, "metadata": {"_props": {"tint": "Dot"}},
         "children": [{"type": "rectangle", "id": "D", "name": "Dot", "width": 10, "height": 10, "fill": "#FF0000"}]}
        """##
        let board = ##"""
        {"type": "frame", "id": "root", "name": "Board", "width": 100, "height": 100, "children": [
          {"type": "ref", "id": "i1", "ref": "W", "descendants": {"D": {"fill": "$ink"}}},
          {"type": "ref", "id": "i2", "ref": "W", "theme": {"mode": "dark"}}]}
        """##
        let result = try SwiftUIEmitterThemeTests.emit(themes: Self.themes, variables: Self.variables, children: "\(swatch), \(board)")
        let page = try Self.page(result, named: "Board")
        #expect(page.contains("Swatch(tint: theme.ink)"))
        #expect(page.contains("Swatch()\n                .penTheme(mode: .dark)"))
    }

    @Test("woodcase-app's components read every variable they use")
    func woodcaseApp() throws {
        let diagnostics = PenDiagnosticCollector()
        _ = try SwiftUIFixtures.emit("woodcase-app", diagnostics: diagnostics)
        let variables = diagnostics.diagnostics.filter { $0.message.contains("variable") }
        #expect(variables.isEmpty, "\(variables.map(\.message))")
    }

    // MARK: - Helpers

    /// The page `Board` holding `children` (comma-separated node objects), over this suite's
    /// themes and variables.
    private static func board(_ children: String, diagnostics: PenDiagnosticCollector? = nil) throws -> String {
        let board = ##"{"type": "frame", "id": "root", "name": "Board", "layout": "vertical", "width": 200, "height": 200, "children": [\##(children)]}"##
        let result = try SwiftUIEmitterThemeTests.emit(themes: themes, variables: variables, children: board, diagnostics: diagnostics)
        return try page(result, named: "Board")
    }

    private static func page(_ result: EmitResult, named name: String) throws -> String {
        try #require(result.files.first { $0.path.hasSuffix("Pages/\(name).swift") }).content
    }
}
