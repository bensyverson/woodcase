//
//  ReactEmitterShaderTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// React writes nothing for a shader fill, as every Woodcase target does, and says so: one
/// warning per node that loses one, in the wording SwiftUI's own warning uses.
struct ReactEmitterShaderTests {
    private static let shader = ##"{"type": "shader", "url": "./uv.frag"}"##

    /// The React diagnostics for a `Card` component whose children are `children`.
    private func diagnostics(_ children: [String]) throws -> [PenDiagnostic] {
        let document = try PenParser.parse("""
        {"version": "2.17",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [\(children.joined(separator: ", "))]}]}
        """)
        let collector = PenDiagnosticCollector()
        _ = ReactEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document), diagnostics: collector
        )
        return collector.diagnostics.filter { $0.message.contains("shader") }
    }

    @Test("Each node whose shader fill React drops is one warning naming the node", arguments: [
        ##"{"type": "rectangle", "id": "Nd001", "width": 10, "height": 10, "fill": \##(shader)}"##,
        ##"{"type": "frame", "id": "Nd001", "width": 10, "height": 10, "fill": ["#FF0000", \##(shader)]}"##,
        ##"{"type": "text", "id": "Nd001", "content": "Hi", "fill": \##(shader)}"##,
        ##"{"type": "icon", "id": "Nd001", "icon": "square", "library": "lucide", "width": 24, "height": 24, "fill": \##(shader)}"##,
        ##"{"type": "polygon", "id": "Nd001", "width": 10, "height": 10, "polygonCount": 5, "fill": \##(shader)}"##,
        ##"{"type": "rectangle", "id": "Nd001", "width": 10, "height": 10, "stroke": \##(shader), "strokeWidth": 2}"##,
    ])
    func warnsPerNode(node: String) throws {
        let found = try diagnostics([node])
        #expect(found.count == 1, "\(found)")
        let warning = try #require(found.first)
        #expect(warning.severity == .warning)
        #expect(warning.stage == .codeGen)
        #expect(warning.nodeID == "Nd001")
        #expect(warning.message == "React does not emit shader fills yet", "\(warning.message)")
    }

    @Test("A disabled shader is no warning: there is nothing to draw")
    func disabledIsQuiet() throws {
        let node = ##"{"type": "rectangle", "id": "Nd001", "width": 10, "height": 10, "##
            + ##""fill": {"type": "shader", "url": "./uv.frag", "enabled": false}}"##
        #expect(try diagnostics([node]).isEmpty)
    }

    @Test("Two shaders on one node are still one warning for that node")
    func oneWarningPerNode() throws {
        let node = ##"{"type": "rectangle", "id": "Nd001", "width": 10, "height": 10, "##
            + ##""fill": [\##(Self.shader), \##(Self.shader)], "stroke": \##(Self.shader), "strokeWidth": 2}"##
        #expect(try diagnostics([node]).count == 1)
    }
}
