//
//  ReactEmitterMaterialWeightTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// React draws a Material Symbols icon at Pen's weight: the node's `weight`, else 200, the
/// weight Pen's `getIconPath` sets when the node names none (leaf AyTAji). The package,
/// `@nine-thirty-five/material-symbols-react`, takes no weight prop: each weight is its own
/// import path, `…/{style}[/{weight}]`, in steps of 100 from 100 to 700, the bare path
/// being 400 (its README, version 2.4.4).
struct ReactEmitterMaterialWeightTests {
    private static let package = "@nine-thirty-five/material-symbols-react"

    /// The `Home` page holding `icons`, each a small `icon` JSON object.
    private func page(_ icons: [String], diagnostics: PenDiagnosticCollector? = nil) throws -> String {
        let json = ##"{"version": "2.17", "children": [{"type": "frame", "id": "P", "name": "Home", "width": 100, "height": 100, "##
            + ##""children": [\##(icons.joined(separator: ", "))]}]}"##
        let doc = try PenParser.parse(Data(json.utf8))
        let files = ReactEmitter.emit(
            document: doc, components: ComponentAnalyzer.analyze(doc), pages: PageAnalyzer.analyze(doc),
            theme: ThemeAnalyzer.analyze(doc), diagnostics: diagnostics
        ).files
        return try #require(files.first { $0.path == "pages/Home.tsx" }).content
    }

    /// An icon node `id` drawing `vpn_lock` from `library`, with `weight` when given.
    private func icon(_ id: String, _ library: String = "Material Symbols Outlined", weight: Double? = nil) -> String {
        let weightKey = weight.map { ##", "weight": \##($0)"## } ?? ""
        return ##"{"type": "icon", "id": "\##(id)", "icon": "vpn_lock", "library": "\##(library)", "width": 24, "height": 24, "##
            + ##""fill": "#000000"\##(weightKey)}"##
    }

    // MARK: - Mapping

    @Test("A Material icon with no weight resolves to the 200 path, Pen's default")
    func defaultWeightPath() {
        let result = IconLibraryMapping.resolve(family: "Material Symbols Rounded", iconName: "vpn_lock")
        #expect(result?.importPath == "\(Self.package)/rounded/200")
    }

    @Test("A Material weight resolves to the package's nearest path; 400 is its bare path", arguments: [
        (100.0, "/outlined/100"), (400.0, "/outlined"), (700.0, "/outlined/700"), (650.0, "/outlined/700"),
        (240.0, "/outlined/200"), (50.0, "/outlined/100"), (900.0, "/outlined/700"),
    ])
    func weightPath(weight: Double, suffix: String) {
        let result = IconLibraryMapping.resolve(family: "Material Symbols Outlined", iconName: "vpn_lock", weight: weight)
        #expect(result?.importPath == Self.package + suffix)
    }

    /// Green on its first run: a guard on what the change must leave alone.
    @Test("A weight means nothing to a family other than Material Symbols")
    func weightIgnoredElsewhere() {
        #expect(IconLibraryMapping.resolve(family: "lucide", iconName: "bell", weight: 700)?.importPath == "lucide-react")
    }

    @Test("A weighted Material path names its family and its weight; the bare path is 400", arguments: [
        ("/outlined/200", "Material Symbols Outlined", 200),
        ("/rounded/700", "Material Symbols Rounded", 700),
        ("/sharp", "Material Symbols Sharp", 400),
    ])
    func weightedPathLookup(suffix: String, family: String, weight: Int) {
        #expect(IconLibraryMapping.family(forImportPath: Self.package + suffix) == family)
        #expect(IconLibraryMapping.materialWeight(forImportPath: Self.package + suffix) == weight)
    }

    /// Green on its first run: a guard on what the change must leave alone.
    @Test("A path the package does not export names no family", arguments: ["/outlined/250", "/outlined/800", "/bold"])
    func unknownWeightPath(suffix: String) {
        #expect(IconLibraryMapping.family(forImportPath: Self.package + suffix) == nil)
    }

    // MARK: - Emitted imports

    @Test("An icon with no weight is imported from the 200 path")
    func emittedDefault() throws {
        let content = try page([icon("i")])
        #expect(content.contains(##"import { VpnLock } from "\##(Self.package)/outlined/200";"##), "\(content)")
    }

    /// Green on its first run: a guard on what the change must leave alone.
    @Test("An icon's own weight picks its path")
    func emittedOwnWeight() throws {
        let content = try page([icon("i", weight: 400)])
        #expect(content.contains(##"import { VpnLock } from "\##(Self.package)/outlined";"##), "\(content)")
    }

    @Test("One icon at two weights of one style is imported once plainly and once under its weight")
    func twoWeights() throws {
        let content = try page([icon("a"), icon("b", weight: 700)])
        #expect(content.contains(##"import { VpnLock } from "\##(Self.package)/outlined/200";"##), "\(content)")
        #expect(content.contains(##"import { VpnLock as VpnLock700 } from "\##(Self.package)/outlined/700";"##), "\(content)")
        #expect(content.contains("<VpnLock700 "), "\(content)")
    }

    @Test("A weight the package has no path for is drawn at the nearest one, with a warning")
    func roundedWeightWarns() throws {
        let collector = PenDiagnosticCollector()
        _ = try page([icon("i", weight: 250), icon("j", weight: 300)], diagnostics: collector)
        let warnings = collector.diagnostics.filter { $0.message.contains("Material Symbols") }
        #expect(warnings.map(\.nodeID) == ["i"], "\(collector.diagnostics)")
        #expect(warnings.first?.message == "React draws this Material Symbols icon at weight 300: the package has weights in steps of 100")
    }
}
