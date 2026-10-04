//
//  ChangeInvalidationDocumentPropertiesTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How a root patch's keys map to document-level invalidation: modeled keys by name,
/// declared tables as tables, only `extras.`-prefixed keys as extras.
struct ChangeInvalidationDocumentPropertiesTests {
    private func invalidation(_ keys: [String]) -> ChangeInvalidation {
        ChangeInvalidation.Probe.documentProperties(keys)
    }

    @Test(
        "a table key names the declared table, not a sliced extra",
        arguments: [
            ("variables", DocumentChangeKey.Table.variables),
            ("imports", .imports),
            ("themes", .themes),
        ]
    )
    func tableKeyIsDeclaredTable(key: String, table: DocumentChangeKey.Table) {
        #expect(invalidation([key]).documentLevel == [.declaredTable(table)])
    }

    @Test("an extras key names the extra after its prefix")
    func extrasKeyIsExtra() {
        #expect(invalidation(["extras.futureKey"]).documentLevel == [.extra("futureKey")])
    }

    @Test("the modeled keys keep their own names, and fonts invalidate everything")
    func modeledKeys() {
        #expect(invalidation(["version", "fileToken"]).documentLevel == [.version, .fileToken])
        let fonts = invalidation(["fonts"])
        #expect(fonts.documentLevel == [.fonts])
        #expect(fonts.full)
    }

    @Test("a key the codec does not know is no extra, and invalidates everything to be safe")
    func unknownKeyIsNotSliced() {
        let result = invalidation(["mystery"])
        #expect(result.documentLevel.isEmpty)
        #expect(result.full)
    }
}
