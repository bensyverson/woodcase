//
//  LintFormatterTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

struct LintFormatterTests {
    private let nodeFinding = LintFinding(
        check: .clipped,
        severity: .warning,
        nodeID: "Ovr01",
        path: "Root/Overflows",
        message: "160,20 80×40 sits partly outside Root (200×100)"
    )

    private let documentFinding = LintFinding(
        check: .pipeline,
        severity: .error,
        nodeID: nil,
        path: nil,
        message: "[migration] Format version 2.13 has never been observed"
    )

    @Test("A finding is one line: severity, check, path, id, message")
    func textNamesTheNode() {
        #expect(
            LintFormatter.text([nodeFinding])
                == "warning clipped  Root/Overflows (Ovr01)  160,20 80×40 sits partly outside Root (200×100)"
        )
    }

    @Test("A document-level finding says so where the path would be")
    func textOfDocumentFinding() {
        #expect(
            LintFormatter.text([documentFinding])
                == "error pipeline  document  [migration] Format version 2.13 has never been observed"
        )
    }

    @Test("Findings are one per line, in the order given")
    func textJoinsLines() {
        let text = LintFormatter.text([documentFinding, nodeFinding])
        #expect(text.components(separatedBy: "\n").count == 2)
        #expect(text.hasPrefix("error pipeline"))
        #expect(!text.hasSuffix("\n"))
    }

    @Test("No findings is no output at all")
    func textOfNothing() {
        #expect(LintFormatter.text([]).isEmpty)
    }

    @Test("The JSON form is the findings array, and decodes back to the same findings")
    func jsonRoundTrips() throws {
        let json = try LintFormatter.json([documentFinding, nodeFinding])
        let decoded = try JSONDecoder().decode([LintFinding].self, from: Data(json.utf8))
        #expect(decoded == [documentFinding, nodeFinding])
        #expect(json.hasPrefix("["))
    }

    @Test("No findings is an empty JSON array")
    func jsonOfNothing() throws {
        #expect(try LintFormatter.json([]) == "[]")
    }

    @Test("Every check has a stable id and a summary a reader can act on")
    func checksAreNamed() {
        #expect(LintCheck.allCases.map(\.rawValue).sorted() == [
            "artboard-overlap",
            "broken-ref",
            "clipped",
            "codegen-prop-path",
            "codegen-role",
            "codegen-unmapped-override",
            "collapsed-absolute-frame",
            "collapsed-text",
            "duplicate-name",
            "empty-fit-content",
            "fill-in-fit-parent",
            "import-not-followed",
            "import-not-found",
            "import-unreadable",
            "mesh-gradient-distorted",
            "mesh-gradient-dropped",
            "override-key-unread",
            "override-target-not-found",
            "override-value-rejected",
            "per-side-stroke-on-shape",
            "pipeline",
            "shader-not-drawn",
            "text-overflow",
            "text-style-stripped",
            "text-without-fill",
            "unknown-icon",
            "unknown-icon-library",
            "unresolved-variable",
        ])
        for check in LintCheck.allCases {
            #expect(!check.summary.isEmpty)
        }
    }
}
