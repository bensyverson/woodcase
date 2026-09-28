//
//  ViewerGolden.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
@testable import WoodcaseViewer

/// The golden-file half of the preview catalog: markup in, a fixture on disk out.
///
/// A golden file per component and state is this project's `#Preview`. It is a
/// regression test — a stray class or a lost `href` fails the run — and it is also the
/// artefact a person reads when reviewing what a component emits.
///
/// The states themselves are **not** declared here. They live in
/// `Sources/WoodcaseViewer/Components/Previews/`, as `PreviewComponent` values that
/// `PreviewCatalog` collects and `PreviewCatalogTests` walks, so the served preview
/// pages and these fixtures read one declaration.
///
/// ```swift
/// try ViewerGolden.check(rendered: state.renderFormatted(), named: "avatar/small")
/// ```
///
/// Re-bless with `UPDATE_GOLDEN=1 swift test --filter WoodcaseViewerTests`, the same
/// switch `ReactEmitterTests` uses. Read the diff before you commit it: a golden nobody
/// looked at only proves the code has not changed.
enum ViewerGolden {
    /// Where the fixtures live, relative to this file.
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/golden")

    /// Whether this run rewrites the fixtures instead of checking them.
    static var isBlessing: Bool {
        ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] == "1"
    }

    /// Compares already-rendered markup with its golden file.
    ///
    /// - Parameters:
    ///   - rendered: The markup.
    ///   - name: The fixture's path under ``directory``, without an extension —
    ///     `<component>/<state>`.
    ///   - sourceLocation: Where the check was written.
    /// - Throws: Whatever writing or reading the fixture throws.
    static func check(
        rendered: String,
        named name: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let url = directory.appendingPathComponent("\(name).html")
        let text = rendered.hasSuffix("\n") ? rendered : rendered + "\n"
        guard !isBlessing else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        guard let golden = try? String(contentsOf: url, encoding: .utf8) else {
            Issue.record(
                "No golden fixture at \(url.path). Bless it with UPDATE_GOLDEN=1 and read the result.",
                sourceLocation: sourceLocation
            )
            return
        }
        #expect(text == golden, sourceLocation: sourceLocation)
    }
}
