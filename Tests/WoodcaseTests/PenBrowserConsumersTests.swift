//
//  PenBrowserConsumersTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Covers every non-drawing consumer a `browser` node passes through: the property
/// codec `set`/`get` use, the editing-layer diff and change category, the schema
/// `woodcase schema` prints, variable resolution and import-alias prefixing.
struct PenBrowserConsumersTests {
    private func browser(_ data: PenNode.BrowserData) -> PenNode {
        PenNode(id: "b1", common: PenNodeCommon(), kind: .browser(data))
    }

    // MARK: - Property codec

    @Test("Every browser field reads and writes through the property codec", arguments: [
        ("kind.url", AnyCodable.string("example.com")),
        ("kind.deviceId", .string("iphone-15")),
        ("kind.zoom", .double(0.75)),
        ("kind.scrollX", .int(10)),
        ("kind.scrollY", .int(240)),
        ("kind.cornerRadius", .int(12)),
        ("kind.width", .string("fill_container")),
        ("kind.height", .int(90)),
        ("kind.stroke", .string("#10B981")),
        ("kind.strokeWidth", .int(2)),
    ])
    func codecRoundTrips(path: String, value: AnyCodable) throws {
        let written = try NodePropertyCodec.setting(value, at: path, on: browser(PenNode.BrowserData()))
        guard case .browser = written.kind else {
            Issue.record("\(path) turned the browser into \(written.kind.typeName)")
            return
        }
        let readBack = try NodePropertyCodec.value(at: path, of: written)
        let expected = try NodePropertyCodec.value(at: path, of: NodePropertyCodec.setting(readBack, at: path, on: written))
        #expect(readBack == expected)
        #expect(readBack != .null, "\(path) read back nothing")
    }

    @Test("The codec lists exactly the browser's keys, and refuses a fill")
    func codecPaths() throws {
        let paths = Set(NodePropertyCodec.paths(for: browser(PenNode.BrowserData())).filter { $0.hasPrefix("kind.") })
        #expect(paths == [
            "kind.url", "kind.deviceId", "kind.zoom", "kind.scrollX", "kind.scrollY", "kind.cornerRadius",
            "kind.width", "kind.height", "kind.stroke", "kind.strokeWidth", "kind.strokeLinecap",
            "kind.strokeLinejoin", "kind.strokeAlignment", "kind.effects",
        ])
        #expect(throws: EditingError.self) {
            try NodePropertyCodec.setting(.string("#FF0000"), at: "kind.fills", on: browser(PenNode.BrowserData()))
        }
    }

    @Test("A zoom written as a $variable is refused: Pen's zoom is a plain number")
    func zoomRefusesVariable() {
        #expect(throws: EditingError.self) {
            try NodePropertyCodec.setting(.string("$scale"), at: "kind.zoom", on: browser(PenNode.BrowserData()))
        }
    }

    @Test("The schema table for browser is the codec's paths, each with a described shape")
    func schemaTable() {
        let table = PenSchema.table(for: .browser)
        #expect(Set(table.properties.map(\.path)) == PropertyDiff.allKindKeys(.browser))
        for field in ["url", "deviceId", "zoom", "scrollX", "scrollY"] {
            #expect(NodePropertyCodec.shape(of: field) != nil, "\(field) has no described shape")
        }
    }

    // MARK: - Diff and change category

    @Test("PropertyDiff reports every changed browser field")
    func propertyDiff() {
        let old = PenNode.BrowserData(url: "a.com", zoom: 1, width: .fixed(100))
        let new = PenNode.BrowserData(url: "b.com", zoom: 2, width: .fixed(200))
        #expect(PropertyDiff.diffKind(old: .browser(old), new: .browser(new))
            == ["kind.url", "kind.zoom", "kind.width"])
    }

    @Test("A size change is layout; a URL or scroll change is render-only")
    func changeCategory() {
        let base = PenNode.BrowserData(url: "a.com", width: .fixed(100), height: .fixed(50))
        var resized = base
        resized.height = .fixed(60)
        var repointed = base
        repointed.url = "b.com"
        repointed.scrollY = 20
        #expect(ChangeCategory.categorize(oldKind: .browser(base), newKind: .browser(resized)) == .layout)
        #expect(ChangeCategory.categorize(oldKind: .browser(base), newKind: .browser(repointed)) == .renderOnly)
    }

    // MARK: - Variables and imports

    @Test("Corner radius, size and stroke variables resolve to their literals")
    func resolvesVariables() {
        let document = PenDocument(
            version: "2.17",
            variables: [
                "radius": PenVariable(type: .number, value: .simple(.double(12))),
                "tall": PenVariable(type: .number, value: .simple(.double(90))),
                "edge": PenVariable(type: .color, value: .simple(.string("#FF0000"))),
            ],
            children: [browser(PenNode.BrowserData(
                cornerRadius: .uniform(.variable("radius")),
                height: .variable("tall"),
                stroke: .single(.shorthand("$edge"))
            ))]
        )
        let resolved = PenVariableResolver.resolve(document)
        guard case let .browser(data) = resolved.children[0].kind else {
            Issue.record("Expected .browser")
            return
        }
        #expect(data.cornerRadius == .uniform(.literal(12)))
        #expect(data.height == .fixed(90))
        #expect(data.stroke == .single(.shorthand("#FF0000")))
    }

    @Test("A $ stroke reference is prefixed with the import alias")
    func prefixesStroke() {
        let prefixed = PenImportPrefixer.prefixNode(
            browser(PenNode.BrowserData(stroke: .single(.shorthand("$edge")))), alias: "V"
        )
        guard case let .browser(data) = prefixed.kind else {
            Issue.record("Expected .browser")
            return
        }
        #expect(data.stroke == .single(.shorthand("$V:edge")))
    }
}
