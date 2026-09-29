//
//  PenLayoutUnknownNodeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A node of a type this build does not model is laid out as an inert box of the size
/// it declares, so the siblings a newer Pen placed around it stay where Pen put them.
struct PenLayoutUnknownNodeTests {
    private func layout(_ json: String) throws -> [String: PenRect] {
        let document = try PenParser.parse(json)
        return PenLayoutEngine.layout(document, textMeasurer: { _, _, _, _, _, _, _, _ in (0, 0) })
    }

    @Test("An unknown node with numeric width and height lays out at that size")
    func numericSize() throws {
        let rects = try layout("""
        {"version":"2.17","children":[{"id":"G","type":"gizmo","x":5,"y":6,"width":200,"height":90}]}
        """)
        #expect(rects["G"] == PenRect(x: 5, y: 6, width: 200, height: 90))
    }

    @Test("An unknown node in a fit_content column pushes its later siblings down")
    func pushesSiblings() throws {
        let rects = try layout("""
        {"version":"2.17","children":[{"id":"Col","type":"frame","layout":"vertical","gap":10,"children":[
          {"id":"A","type":"rectangle","width":100,"height":100},
          {"id":"G","type":"gizmo","width":200,"height":200},
          {"id":"B","type":"rectangle","width":100,"height":100}]}]}
        """)
        #expect(rects["Col"]?.height == 420)
        #expect(rects["B"]?.y == 320)
        #expect(rects["G"]?.width == 200)
    }

    @Test("An unknown node honors a sizing keyword")
    func sizingKeyword() throws {
        let rects = try layout("""
        {"version":"2.17","children":[{"id":"Row","type":"frame","width":300,"height":50,"layout":"horizontal","children":[
          {"id":"G","type":"gizmo","width":"fill_container","height":"fill_container"}]}]}
        """)
        #expect(rects["G"]?.width == 300)
        #expect(rects["G"]?.height == 50)
    }

    @Test("An unknown node that declares no size stays empty")
    func noSizeIsEmpty() throws {
        let rects = try layout("""
        {"version":"2.17","children":[{"id":"G","type":"gizmo","label":"x"}]}
        """)
        #expect(rects["G"]?.width == 0)
        #expect(rects["G"]?.height == 0)
    }
}
