//
//  DocumentLinterCodegenTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The three codegen-readiness checks: `codegen-prop-path`, `codegen-role` and
/// `codegen-unmapped-override`.
///
/// Each asks what `generate react` will choke on and says so before the emitter runs.
/// The findings are matched by raw id rather than by case, so this suite says what the
/// *published* ids are — the string an agent passes to `--exclude` — and not merely
/// which Swift case fired.
@MainActor
struct DocumentLinterCodegenTests {
    // MARK: - Helpers

    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    private func document(_ name: String) throws -> EditableDocument {
        guard let url = Bundle.module.url(
            forResource: (name as NSString).deletingPathExtension,
            withExtension: "pen",
            subdirectory: "Fixtures/lint"
        ) else {
            throw FixtureLoadError.notFound(name)
        }
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    private func findings(_ name: String, check: String) throws -> [LintFinding] {
        try DocumentLinter.findings(in: document(name)).filter { $0.check.rawValue == check }
    }

    // MARK: - codegen-prop-path

    @Test("A _props entry whose path resolves is not a finding")
    func resolvingPropPathIsClean() throws {
        #expect(try findings("codegen-prop-path-clean.pen", check: "codegen-prop-path").isEmpty)
        #expect(try DocumentLinter.findings(in: document("codegen-prop-path-clean.pen")).isEmpty)
    }

    @Test("A _props path that names no descendant is a finding on the definition")
    func unresolvedPropPathTrips() throws {
        let tripped = try findings("codegen-prop-path-trips.pen", check: "codegen-prop-path")
        let title = tripped.first { $0.message.contains("`title`") }
        #expect(title?.nodeID == "Cmp01")
        #expect(title?.path == "Card")
        #expect(title?.severity == .error)
        #expect(title?.message.contains("Nope") == true)
        // The remedy names the deep metadata key `set` takes.
        #expect(title?.message.contains("common.metadata._props.title=") == true)
        // It lists the descendants that *do* answer to a path.
        #expect(title?.message.contains("Row/Tag") == true)
    }

    @Test("A nested _props path that breaks at its last segment is a finding")
    func unresolvedNestedPropPathTrips() throws {
        let tripped = try findings("codegen-prop-path-trips.pen", check: "codegen-prop-path")
        let tag = tripped.first { $0.message.contains("`tag`") }
        #expect(tag != nil)
        #expect(tag?.message.contains("Row/Missing") == true)
    }

    @Test("A _props value that is not a string is a finding naming the shape it needs")
    func nonStringPropValueTrips() throws {
        let tripped = try findings("codegen-prop-path-trips.pen", check: "codegen-prop-path")
        let count = tripped.first { $0.message.contains("`count`") }
        #expect(count?.nodeID == "Cmp01")
        #expect(count?.message.contains("path") == true)
        #expect(count?.message.contains("common.metadata._props.count=") == true)
    }

    @Test("One finding per faulty _props entry, in prop-name order")
    func onePropPathFindingPerEntry() throws {
        let tripped = try findings("codegen-prop-path-trips.pen", check: "codegen-prop-path")
        #expect(tripped.count == 3)
    }

    @Test("Lint and the analyzer resolve a _props path the same way")
    func lintAgreesWithTheAnalyzer() throws {
        let doc = try document("codegen-prop-path-trips.pen")
        let components = ComponentAnalyzer.analyze(doc.materialize())
        let unwired = Set(components.flatMap(\.props).filter { $0.targetNodeID == nil }.map(\.name))
        let reported = try Set(
            findings("codegen-prop-path-trips.pen", check: "codegen-prop-path")
                .compactMap { finding -> String? in
                    ["title", "tag", "count"].first { finding.message.contains("`\($0)`") }
                }
        )
        // `count` never reaches the analyzer at all — a non-string value is dropped
        // before a path is resolved — so lint reports it and the analyzer's props do not.
        #expect(unwired == ["title", "tag"])
        #expect(reported == ["title", "tag", "count"])
    }

    // MARK: - codegen-prop-path: two props on one descendant

    @Test("Two _props entries reading the same field of one descendant are a finding")
    func ambiguousPropPathTrips() throws {
        let tripped = try findings("codegen-prop-path-ambiguous.pen", check: "codegen-prop-path")
        let ambiguous = try #require(tripped.first { $0.message.contains("`label`") })
        #expect(ambiguous.nodeID == "Cmp01")
        #expect(ambiguous.path == "Card")
        #expect(ambiguous.severity == .error)
        // Both props are named, and so is the descendant they share.
        #expect(ambiguous.message.contains("`width`"))
        #expect(ambiguous.message.contains("Label"))
        #expect(ambiguous.message.contains("Lbl01"))
        // The remedy points the *other* prop somewhere else, with the deep metadata key.
        #expect(ambiguous.message.contains("common.metadata._props.width="))
    }

    @Test("The ambiguity is one finding for the pair, and the resolving prop is clean")
    func ambiguousPropPathIsOneFinding() throws {
        let tripped = try findings("codegen-prop-path-ambiguous.pen", check: "codegen-prop-path")
        #expect(tripped.count == 1)
        // `tag` resolves to a descendant nothing else names, so it is not in the finding.
        #expect(tripped.first?.message.contains("`tag`") == false)
    }

    @Test("Two _props entries on one descendant are not a broken path")
    func ambiguousPropPathsStillResolve() throws {
        let doc = try document("codegen-prop-path-ambiguous.pen")
        let components = ComponentAnalyzer.analyze(doc.materialize())
        let unwired = components.flatMap(\.props).filter { $0.targetNodeID == nil }
        #expect(unwired.isEmpty)
    }

    @Test("Lint reports exactly the prop the emitter drops")
    func lintNamesThePropTheEmitterDrops() throws {
        let doc = try document("codegen-prop-path-ambiguous.pen")
        let component = try #require(ComponentAnalyzer.analyze(doc.materialize()).first)
        let shared = try #require(component.propsByNodeID["Lbl01"])
        // The emitter keeps the first by prop name; lint's remedy moves the others.
        #expect(shared.map(\.name) == ["label", "width"])
        let tripped = try findings("codegen-prop-path-ambiguous.pen", check: "codegen-prop-path")
        #expect(tripped.first?.message.contains("common.metadata._props.label=") == false)
    }

    // MARK: - codegen-role

    @Test("A _role the emitter knows is not a finding, on a root or a descendant")
    func knownRolesAreClean() throws {
        #expect(try findings("codegen-role-clean.pen", check: "codegen-role").isEmpty)
        #expect(try DocumentLinter.findings(in: document("codegen-role-clean.pen")).isEmpty)
    }

    @Test("A _role outside ComponentRole is a finding listing the valid roles")
    func unknownRoleOnDefinitionTrips() throws {
        let tripped = try findings("codegen-role-trips.pen", check: "codegen-role")
        let root = tripped.first { $0.nodeID == "Cmp01" }
        #expect(root?.severity == .error)
        #expect(root?.message.contains("buton") == true)
        for role in ["button", "link", "toggle", "textInput", "select", "tabBar"] {
            #expect(root?.message.contains(role) == true)
        }
        #expect(root?.message.contains("common.metadata._role=") == true)
    }

    @Test("An unknown _role on a descendant of a definition is a finding on that descendant")
    func unknownRoleOnDescendantTrips() throws {
        let tripped = try findings("codegen-role-trips.pen", check: "codegen-role")
        let row = tripped.first { $0.nodeID == "Row01" }
        #expect(row?.path == "Card/Row")
        #expect(row?.message.contains("clickable") == true)
    }

    @Test("A _role outside every reusable subtree is not a finding: codegen never reads it")
    func unknownRoleOnAPageIsNotAFinding() throws {
        let tripped = try findings("codegen-role-trips.pen", check: "codegen-role")
        #expect(tripped.map(\.nodeID) == ["Cmp01", "Row01"])
        #expect(!tripped.contains { $0.message.contains("screen") })
    }

    // MARK: - codegen-unmapped-override

    @Test("An override a declared prop covers is not a finding")
    func mappedOverrideIsClean() throws {
        #expect(try findings("codegen-unmapped-override-clean.pen", check: "codegen-unmapped-override").isEmpty)
    }

    @Test("A definition that declares no _props is not a finding, whatever an instance overrides")
    func definitionWithoutPropsIsNotAFinding() throws {
        let all = try DocumentLinter.findings(in: document("codegen-unmapped-override-clean.pen"))
        #expect(all.isEmpty)
    }

    @Test("An override no declared prop covers is a finding naming the key and the fix")
    func unmappedOverrideTrips() throws {
        let tripped = try findings("codegen-unmapped-override-trips.pen", check: "codegen-unmapped-override")
        #expect(tripped.count == 1)
        let finding = tripped.first
        #expect(finding?.nodeID == "Rf001")
        #expect(finding?.path == "Root/Chip")
        #expect(finding?.message.contains("Sub01") == true)
        // The mapped key is not named — only the ones that force the inline.
        #expect(finding?.message.contains("Lbl01") == false)
        #expect(finding?.message.contains("common.metadata._props.subtitle=Subtitle") == true)
        #expect(finding?.message.contains("Cmp01") == true)
    }

    @Test("An override of an unnamed descendant is a finding that says to name it first")
    func unmappedOverrideOfAnUnnamedDescendantTrips() throws {
        let tripped = try findings("codegen-unmapped-override-unnamed.pen", check: "codegen-unmapped-override")
        #expect(tripped.count == 1)
        let finding = tripped.first
        #expect(finding?.nodeID == "Rf001")
        #expect(finding?.message.contains("Unn01") == true)
        // A _props path is a run of names, so an unnamed descendant needs a name first.
        #expect(finding?.message.contains("has no name") == true)
        #expect(finding?.message.contains("woodcase set <file> Unn01 common.name=") == true)
    }

    @Test("An override key naming no descendant at all is left to override-target-not-found")
    func aKeyNamingNothingIsNotThisFinding() throws {
        let all = try DocumentLinter.findings(in: document("codegen-unmapped-override-foreign-key.pen"))
        #expect(all.contains { $0.check == .overrideTargetNotFound })
        #expect(!all.contains { $0.check.rawValue == "codegen-unmapped-override" })
    }

    @Test("The finding fires on exactly the refs the emitter inlines")
    func lintAgreesWithTheEmitter() throws {
        let penDocument = try document("codegen-unmapped-override-trips.pen").materialize()
        let diagnostics = PenDiagnosticCollector()
        _ = ReactEmitter.emit(
            document: penDocument,
            components: ComponentAnalyzer.analyze(penDocument),
            pages: PageAnalyzer.analyze(penDocument),
            theme: ThemeAnalyzer.analyze(penDocument),
            options: ReactEmitter.Options(strict: false),
            diagnostics: diagnostics
        )
        let inlined = diagnostics.diagnostics.filter { $0.message.contains("Inlined component") }
        #expect(inlined.map(\.nodeID) == ["Rf001"])
        let tripped = try findings("codegen-unmapped-override-trips.pen", check: "codegen-unmapped-override")
        #expect(tripped.map(\.nodeID) == inlined.map(\.nodeID))
    }
}
