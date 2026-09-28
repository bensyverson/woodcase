//
//  SwiftUIEmitterComponentGoldenTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Golden coverage for the SwiftUI emitter's components and pages: every file under
/// `Components/` and `Pages/` that `woodcase-app.pen`, `pages.pen`, `codegen-states.pen` and `codegen-slots.pen` emit, pinned whole,
/// one golden per file under `golden/swiftui/<fixture>/`, with the list of files pinned
/// beside them so a file that stops being emitted fails too.
///
/// Foundation-only, like ``SwiftUIEmitterGoldenTests``. Regenerate with
/// `UPDATE_GOLDEN=1 swift test --filter SwiftUIEmitterComponentGoldenTests`, then read the diff.
struct SwiftUIEmitterComponentGoldenTests {
    /// The fixtures with components and pages.
    static let fixtures = ["woodcase-app", "pages", "codegen-states", "codegen-slots"]

    @Test("Each fixture emits the files its index lists", arguments: fixtures)
    func fileListMatchesGolden(fixture: String) throws {
        let paths = try Self.viewFiles(fixture).map(\.path)
        try GoldenFile.assert(paths.joined(separator: "\n") + "\n", name: "index", subdirectory: "swiftui/\(fixture)")
    }

    @Test("Each emitted component and page matches its golden", arguments: fixtures)
    func filesMatchGoldens(fixture: String) throws {
        let files = try Self.viewFiles(fixture)
        #expect(!files.isEmpty)
        for file in files {
            let name = URL(fileURLWithPath: file.path).lastPathComponent
            let folder = file.path.contains("/Components/") ? "Components" : "Pages"
            try GoldenFile.assert(file.content, name: name, subdirectory: "swiftui/\(fixture)/\(folder)")
        }
    }

    @Test("pages.pen's Home page calls its Card with the label it overrides")
    func pagesCallTheCard() throws {
        let files = try Self.viewFiles("pages")
        let home = try #require(files.first { $0.path.hasSuffix("/Pages/Home.swift") })
        #expect(home.content.contains("Card(label: \"Revenue\")"))
        #expect(files.contains { $0.path.hasSuffix("/Components/Card.swift") })
    }

    /// The fixture's component and page files, in path order.
    static func viewFiles(_ fixture: String) throws -> [GeneratedFile] {
        try SwiftUIFixtures.emit(fixture).files
            .filter { $0.path.contains("/Components/") || $0.path.contains("/Pages/") }
            .sorted { $0.path < $1.path }
    }
}
