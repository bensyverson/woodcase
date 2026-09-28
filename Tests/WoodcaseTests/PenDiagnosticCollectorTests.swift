import Foundation
import Testing
@testable import Woodcase

struct PenDiagnosticCollectorTests {
    @Test("Collects warnings and errors")
    func collectsDiagnostics() {
        let collector = PenDiagnosticCollector()
        collector.warn("Missing font", stage: .fontResolution)
        collector.error("Broken ref", stage: .refExpansion, nodeID: "node-1")

        #expect(collector.diagnostics.count == 2)
        #expect(collector.hasIssues)
        #expect(collector.hasErrors)
    }

    @Test("Empty collector reports no issues")
    func emptyCollector() {
        let collector = PenDiagnosticCollector()
        #expect(!collector.hasIssues)
        #expect(!collector.hasErrors)
    }

    @Test("Warning-only collector has issues but no errors")
    func warningOnly() {
        let collector = PenDiagnosticCollector()
        collector.warn("Minor issue", stage: .layout)
        #expect(collector.hasIssues)
        #expect(!collector.hasErrors)
    }

    @Test("Diagnostic description includes severity and stage")
    func diagnosticDescription() {
        let diag = PenDiagnostic(
            severity: .warning, stage: .fontResolution,
            message: "Font not found", nodeID: "abc"
        )
        #expect(diag.description == "warning: [fontResolution] Font not found (node: abc)")
    }

    @Test("Diagnostic description without node ID")
    func diagnosticDescriptionNoNode() {
        let diag = PenDiagnostic(
            severity: .error, stage: .parsing,
            message: "Invalid JSON"
        )
        #expect(diag.description == "error: [parsing] Invalid JSON")
    }
}
