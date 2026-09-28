//
//  SwiftUIFixtures.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// The fixtures the SwiftUI emitter's goldens and render test run over, and the one way
/// both suites turn a fixture into emitted files.
///
/// Every `layout-*.pen` and `render-text.pen`: each holds one top-level frame, which
/// `PageAnalyzer` finds as a page, so every fixture emits exactly one page file.
enum SwiftUIFixtures {
    /// The directory holding the fixtures, in the source tree.
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Every fixture name, without `.pen`, in name order.
    static let names: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let layout = files.filter { $0.hasPrefix("layout-") && $0.hasSuffix(".pen") && !$0.contains(".pen-") }
        return (layout + ["render-text.pen"]).map { String($0.dropLast(4)) }.sorted()
    }()

    /// The fixtures Pen exported a PNG for, which the render test compares against.
    static let rendered: [String] = names.filter {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("\($0).png").path)
    }

    /// Parse a fixture.
    static func document(_ name: String) throws -> PenDocument {
        try PenParser.parse(Data(contentsOf: directory.appendingPathComponent("\(name).pen")))
    }

    /// Run a fixture through the steps `woodcase generate swiftui` runs, and return what
    /// the emitter produced.
    static func emit(
        _ name: String,
        options: SwiftUIEmitter.Options = SwiftUIEmitter.Options(),
        diagnostics: PenDiagnosticCollector? = nil
    ) throws -> EmitResult {
        let document = try document(name)
        return SwiftUIEmitter.emit(
            document: document,
            components: ComponentAnalyzer.analyze(document),
            pages: PageAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document),
            options: options,
            diagnostics: diagnostics
        )
    }

    /// The one page file a fixture emits.
    static func page(_ name: String, options: SwiftUIEmitter.Options = SwiftUIEmitter.Options()) throws -> GeneratedFile {
        let pages = try emit(name, options: options).files.filter { $0.path.contains("/Pages/") }
        #expect(pages.count == 1, "\(name) emitted \(pages.count) pages")
        return try #require(pages.first)
    }

    // MARK: - Paint fixtures

    /// The paint and stroke fixtures: several frames each, every exported frame a render board
    /// (``SwiftUIRenderBoard``) and every page pinned by one golden per fixture.
    /// `swiftui-color-scheme` holds the paints a colour scheme can move: unfilled text and
    /// icons, and a mesh of theme colours; `render-mesh-colors` a mesh per colour string
    /// Pen's mesh reads its own way.
    static let paintFixtures = [
        "render-gradients", "render-gradient-geometry", "render-text-fills", "render-per-side-strokes", "render-stroke-fills",
        "render-arc-donut", "render-fill-domains", "render-mesh-gradients", "swiftui-color-scheme", "render-mesh-colors",
    ]

    /// Every page file a fixture emits, in the emitter's order.
    static func pages(_ name: String) throws -> [GeneratedFile] {
        try emit(name).files.filter { $0.path.contains("/Pages/") }
    }
}
