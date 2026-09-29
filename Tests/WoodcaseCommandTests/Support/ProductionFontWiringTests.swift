//
//  ProductionFontWiringTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing

/// The other half of `HermeticNetworkTests`' font rule: the library never defaults a
/// document's font resolver to the shared one, so every production read must name it.
///
/// A `PenFileTransaction` opened without `fonts:` hands its body a document that
/// settles in the faces the process already has, ignoring the Google fonts cached in
/// `$WOODCASE_HOME` — so `tree` would measure Inter text in SF Pro while `shot` drew it
/// in Inter, which is the disagreement `SettledTree`'s font preparation exists to
/// prevent. This reads the command and viewer sources and requires every transaction
/// they open to say which resolver it reads with.
@Suite("Production reads name their font resolver")
struct ProductionFontWiringTests {
    /// A transaction call, from its name to the opening brace of its body.
    private static var transaction: Regex<(Substring, arguments: Substring)> {
        /PenFileTransaction\.(?:read|run)\((?<arguments>[^{]*)\{/
    }

    @Test("Every transaction the CLI and the viewer open names fonts:")
    func everyProductionTransactionNamesFonts() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
        var offenses: [String] = []
        for target in ["WoodcaseCommandCore", "WoodcaseViewer"] {
            let enumerator = try #require(FileManager.default.enumerator(
                at: sources.appendingPathComponent(target), includingPropertiesForKeys: nil
            ))
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                let code = try String(contentsOf: url, encoding: .utf8)
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                    .joined(separator: "\n")
                for match in code.matches(of: Self.transaction) where !match.arguments.contains("fonts:") {
                    offenses.append("\(target)/\(url.lastPathComponent): PenFileTransaction(\(match.arguments))")
                }
            }
        }
        #expect(offenses.isEmpty, "pass fonts: .shared (or the viewer's resolver):\n\(offenses.joined(separator: "\n"))")
    }
}
