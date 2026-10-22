//
//  CodeGenCorpusDump.swift
//  WoodcaseBench
//

import Foundation
import Woodcase
import WoodcasePerfFixtures

/// Everything code generation writes for every `.pen` under `Tests/`, dumped to a
/// directory so two builds' output can be compared byte for byte with `diff -r`.
///
/// A record, not a check: it is how the iterative emitters (issue `g5SACU`) were shown to
/// write what the recursive ones wrote. For each fixture that parses it writes the whole
/// React and SwiftUI emit, each run's diagnostics, and ``CodeGeneration``'s code for every
/// component and root of the document.
///
/// ```sh
/// swift run -c release WoodcaseBench codegen-dump /path/to/after
/// diff -r /path/to/before /path/to/after
/// ```
enum CodeGenCorpusDump {
    /// The bench.
    static let bench = Bench(
        name: "codegen-dump",
        summary: "Dump every Tests/ fixture's generated React, SwiftUI and selection code, for diff -r",
        arguments: "<directory>",
        run: { arguments in
            guard let destination = arguments.first else {
                throw Bench.UsageError(description: "usage: WoodcaseBench codegen-dump <directory>")
            }
            try run(to: URL(fileURLWithPath: destination))
        }
    )

    private static func run(to destination: URL) throws {
        let tests = PerfFixtureFile.testsDirectory
        let fixtures = fixtures(under: tests)
        var dumped = 0
        for fixture in fixtures {
            guard let document = try? PenParser.parse(Data(contentsOf: fixture)) else { continue }
            let relative = String(fixture.path.dropFirst(tests.path.count + 1))
            try dump(document, to: destination.appendingPathComponent(relative))
            dumped += 1
        }
        print("PROBE codegen corpus: \(dumped) of \(fixtures.count) fixtures dumped to \(destination.path)")
    }

    /// Every `.pen` under `directory`, in path order.
    private static func fixtures(under directory: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        var found: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "pen" { found.append(url) }
        }
        return found.sorted { $0.path < $1.path }
    }

    /// Writes one document's generated code under `directory`.
    private static func dump(_ document: PenDocument, to directory: URL) throws {
        let components = ComponentAnalyzer.analyze(document)
        let pages = PageAnalyzer.analyze(document)
        let theme = ThemeAnalyzer.analyze(document)
        let ids = components.map(\.id) + document.children.map(\.id)

        let reactDiagnostics = PenDiagnosticCollector()
        let react = ReactEmitter.emit(
            document: document, components: components, pages: pages, theme: theme, diagnostics: reactDiagnostics
        )
        try write(react.files, diagnostics: reactDiagnostics, to: directory.appendingPathComponent("react"))

        let swiftUIDiagnostics = PenDiagnosticCollector()
        let swiftUI = try SwiftUIEmitter.emit(
            document: document, components: components, pages: pages, theme: theme, diagnostics: swiftUIDiagnostics
        )
        try write(swiftUI.files, diagnostics: swiftUIDiagnostics, to: directory.appendingPathComponent("swiftui"))

        for language in CodeLanguage.allCases {
            let diagnostics = PenDiagnosticCollector()
            let code = try CodeGeneration.code(for: ids, in: document, language: language, diagnostics: diagnostics)
            let files = code.map { GeneratedFile(path: "\($0.role.rawValue)-\($0.id)-\($0.typeName)", content: $0.file.path + "\n" + $0.file.content) }
            try write(files, diagnostics: diagnostics, to: directory.appendingPathComponent("selection-\(language.rawValue)"))
        }
    }

    /// Writes `files` and the diagnostics' messages under `directory`.
    private static func write(_ files: [GeneratedFile], diagnostics: PenDiagnosticCollector, to directory: URL) throws {
        let fileManager = FileManager.default
        for file in files {
            let url = directory.appendingPathComponent(file.path.replacingOccurrences(of: "..", with: "_"))
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.content.write(to: url, atomically: true, encoding: .utf8)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let messages = diagnostics.diagnostics.map { "\($0.severity) \($0.nodeID ?? "-") \($0.message)" }
        try (messages.joined(separator: "\n") + "\n").write(
            to: directory.appendingPathComponent("_diagnostics.txt"), atomically: true, encoding: .utf8
        )
    }
}
