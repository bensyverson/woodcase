//
//  BankingImportsLintTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// `banking.pen` imports `V` from the `kit.lib.pen` beside it. Read with its library,
/// every `V:` instance resolves, so lint reports no broken ref and no override that
/// misses its target.
///
/// The two theme-variant instances of `nSNTs` (`#YGJ0d`, `#8ruxp`) carry overrides keyed
/// `2592p`, `G6llC`, `T2IOh` and `WKey6`: the icons that `nSNTs`' own transaction rows
/// (`ALu8G` and its siblings) inject into their `URnQO` slot. Pen resolves a bare key to
/// any node the component itself wrote, slot content included, so these apply — and
/// lint accepts them. See `project/2026-09-26-slot-override-keys.md`.
struct BankingImportsLintTests {
    static func findings() async throws -> [LintFinding] {
        let url = try #require(Bundle.module.url(forResource: "banking", withExtension: "pen", subdirectory: "Fixtures"))
        return try await DocumentLinterImportsTests.lint(url)
    }

    @Test("No instance of an imported component is reported broken")
    func noBrokenRefs() async throws {
        let findings = try await Self.findings()

        #expect(!findings.contains { $0.check == .brokenRef }, "\(LintFormatter.text(findings))")
        #expect(!findings.contains { $0.check == .importNotFound })
    }

    @Test("Every override reaches its target, the bare slot-content keys included")
    func everyOverrideReachesItsTarget() async throws {
        let missed = try await Self.findings().filter { $0.check == .overrideTargetNotFound }

        #expect(missed.isEmpty, "\(LintFormatter.text(missed))")
    }
}
