//
//  PenShaderEffectTargetTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Every target draws a node with a shader effect unprocessed — exactly as it draws the
/// node without the effect — since Woodcase has no shader runtime, and says so: the render
/// warning and the code generators' warnings name an enabled shader effect, and a disabled
/// one draws nothing in Pen either, so it earns no warning.
@MainActor
struct PenShaderEffectTargetTests {
    // MARK: - Helpers

    private static let shadow = ##"{"type":"shadow","offset":{"x":0,"y":2},"blur":4,"color":"#00000040"}"##
    private static let enabledShader = ##"{"type":"shader","url":"./post.frag","uniforms":{"u_strength":0.5}}"##
    private static let disabledShader = ##"{"type":"shader","enabled":false,"url":"./post.frag"}"##

    /// A 2.21 document: a reusable card frame holding one rectangle with `effects`.
    private func document(effects: [String]) throws -> PenDocument {
        try PenParser.parse("""
        {"version": "2.21", "children": [
          {"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "x": 0, "y": 0,
           "width": 80, "height": 80, "layout": "none", "fill": "#FFFFFF", "children": [
            {"type": "rectangle", "id": "R1", "name": "Glow", "x": 20, "y": 20, "width": 40, "height": 40,
             "fill": "#3366FF", "effect": [\(effects.joined(separator: ","))]}
          ]}
        ]}
        """)
    }

    private func pixels(_ document: PenDocument) throws -> [UInt8] {
        let rects = PenLayoutEngine.layout(document)
        let image = try #require(PenRenderer.render(document, layoutRects: rects, size: CGSize(width: 80, height: 80)))
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: 80, height: 80, bitsPerComponent: 8, bytesPerRow: 320, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 80, height: 80))
        let data = try #require(context.data)
        return Array(UnsafeBufferPointer(start: data.bindMemory(to: UInt8.self, capacity: 80 * 80 * 4), count: 80 * 80 * 4))
    }

    private func svg(_ document: PenDocument) throws -> String {
        try #require(SVGExporter.string(
            document, layoutRects: PenLayoutEngine.layout(document), rootNodeIDs: ["Card1"]
        ))
    }

    private func react(_ document: PenDocument, diagnostics: PenDiagnosticCollector? = nil) throws -> String {
        let files = ReactEmitter.emit(
            document: document,
            components: ComponentAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document),
            diagnostics: diagnostics
        ).files
        return try #require(files.first { $0.path == "components/Card.tsx" }).content
    }

    private func swiftUI(_ document: PenDocument, diagnostics: PenDiagnosticCollector? = nil) throws -> String {
        let result = try SwiftUIEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document), pages: [],
            theme: ThemeAnalyzer.analyze(document), diagnostics: diagnostics
        )
        return try #require(result.files.first { $0.path == "Sources/PenUI/Components/Card.swift" }).content
    }

    // MARK: - Drawn unprocessed

    @Test("The renderer draws a node with a shader effect as it draws the node without one")
    func rendererDrawsUnprocessed() throws {
        let plain = try pixels(document(effects: [Self.shadow]))
        #expect(try pixels(document(effects: [Self.shadow, Self.enabledShader])) == plain)
        #expect(try pixels(document(effects: [Self.disabledShader, Self.shadow])) == plain)
    }

    @Test("The SVG writer draws a node with a shader effect as it draws the node without one")
    func svgDrawsUnprocessed() throws {
        let plain = try svg(document(effects: [Self.shadow]))
        #expect(try svg(document(effects: [Self.shadow, Self.enabledShader])) == plain)
    }

    @Test("React writes a node with a shader effect as it writes the node without one")
    func reactWritesUnprocessed() throws {
        let plain = try react(document(effects: [Self.shadow]))
        #expect(try react(document(effects: [Self.shadow, Self.enabledShader])) == plain)
    }

    @Test("SwiftUI writes a node with a shader effect as it writes the node without one")
    func swiftUIWritesUnprocessed() throws {
        let plain = try swiftUI(document(effects: [Self.shadow]))
        #expect(try swiftUI(document(effects: [Self.shadow, Self.enabledShader])) == plain)
    }

    // MARK: - Warnings

    @Test("The render warning names a node with an enabled shader effect, and calls it an effect")
    func renderWarning() throws {
        let doc = try document(effects: [Self.enabledShader])
        let warning = try #require(ShaderFills.diagnostic(under: doc.children))
        #expect(warning.message.contains("Glow (R1)"), "\(warning.message)")
        #expect(warning.message.contains("effect"), "\(warning.message)")
    }

    @Test("A disabled shader effect earns no render warning")
    func disabledEarnsNoRenderWarning() throws {
        #expect(try ShaderFills.diagnostic(under: document(effects: [Self.disabledShader]).children) == nil)
    }

    @Test("React warns once for a node whose enabled shader effect it leaves out, and not for a disabled one")
    func reactWarning() throws {
        let on = PenDiagnosticCollector()
        _ = try react(document(effects: [Self.enabledShader]), diagnostics: on)
        #expect(on.diagnostics.count { $0.nodeID == "R1" && $0.message.contains("shader") } == 1, "\(on.diagnostics)")

        let off = PenDiagnosticCollector()
        _ = try react(document(effects: [Self.disabledShader]), diagnostics: off)
        #expect(!off.diagnostics.contains { $0.message.contains("shader") }, "\(off.diagnostics)")
    }

    @Test("SwiftUI warns for a node whose enabled shader effect it leaves out, and not for a disabled one")
    func swiftUIWarning() throws {
        let on = PenDiagnosticCollector()
        _ = try swiftUI(document(effects: [Self.enabledShader]), diagnostics: on)
        #expect(on.diagnostics.contains { $0.nodeID == "R1" && $0.message.contains("shader effects") }, "\(on.diagnostics)")

        let off = PenDiagnosticCollector()
        _ = try swiftUI(document(effects: [Self.disabledShader]), diagnostics: off)
        #expect(!off.diagnostics.contains { $0.message.contains("shader") }, "\(off.diagnostics)")
    }
}
