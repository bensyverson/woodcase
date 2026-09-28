//
//  ReactEmitterPageSignatureTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// The signature an emitted `pages/*.tsx` carries.
///
/// A page's root element is emitted through the same `isRoot` path a component root
/// takes: it writes `className={cn("…", className)}` and spreads `...style` into the
/// inline style object. A page that declared neither referenced two identifiers that
/// were nowhere bound, so every emitted page failed to compile. A page therefore takes
/// the same two optional members a component root takes, from the same interface
/// emission, defaulted so a router can still render `<Home />`.
///
/// **These checks are textual.** The test harness carries React, Babel and Tailwind
/// (`Fixtures/js`) but no TypeScript compiler, so nothing here type-checks the emitted
/// file. What it does instead is name the identifiers the root emission introduces and
/// assert each one is bound in the same file — by an import, or by the function's
/// parameter destructuring — which is the failure that shipped.
struct ReactEmitterPageSignatureTests {
    // MARK: - Helpers

    /// A one-page document whose root frame has a fill, so the root takes the
    /// `className`/`style` branch of the frame emitter.
    private func pageSource(named name: String = "Home") throws -> String {
        let doc = PenDocument(version: "2.17", children: [
            PenNode(
                id: "Pag01",
                common: PenNodeCommon(name: name),
                kind: .frame(PenNode.FrameData(
                    width: .fixed(400),
                    height: .fixed(300),
                    fills: PenFills.single(.shorthand("#FFFFFF")),
                    layout: .vertical
                ))
            ),
        ])
        let files = ReactEmitter.emit(
            document: doc,
            components: [],
            pages: PageAnalyzer.analyze(doc),
            theme: ThemeAnalyzer.analyze(doc)
        ).files
        return try #require(files.first { $0.path == "pages/\(name).tsx" }).content
    }

    /// Every name the file binds at module scope, from ``EmittedSource/boundNames(in:)``.
    ///
    /// ``ReactEmitterPageGoldenTests`` asks the same question of the pages a fixture on
    /// disk emits, so the reading itself lives in one place.
    private func boundNames(in source: String) -> Set<String> {
        EmittedSource.boundNames(in: source)
    }

    // MARK: - The interface

    @Test("A page emits a props interface with the two members a component root takes")
    func pageEmitsAPropsInterface() throws {
        let source = try pageSource()

        #expect(source.contains("interface HomeProps {"))
        #expect(source.contains("  className?: string;"))
        #expect(source.contains("  style?: React.CSSProperties;"))
    }

    @Test("A page's interface carries nothing else: a page has no props of its own")
    func pageInterfaceCarriesNothingElse() throws {
        let source = try pageSource()
        let body = try #require(source.split(separator: "interface HomeProps {").last)
        let members = body.split(separator: "}")[0]
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        #expect(members == ["className?: string;", "style?: React.CSSProperties;"])
    }

    // MARK: - The signature

    @Test("A page's signature destructures className and style, and defaults to no props")
    func pageSignatureDestructuresAndDefaults() throws {
        let source = try pageSource()

        #expect(source.contains("export function Home({ className, style }: HomeProps = {}) {"))
    }

    @Test("The page name reaches both the interface and the signature")
    func pageNameReachesBoth() throws {
        let source = try pageSource(named: "Settings")

        #expect(source.contains("interface SettingsProps {"))
        #expect(source.contains("export function Settings({ className, style }: SettingsProps = {}) {"))
    }

    // MARK: - Nothing the page uses is free

    @Test("Every identifier the page root uses is bound in the same file")
    func pageRootUsesNothingUndeclared() throws {
        let source = try pageSource()
        let bound = boundNames(in: source)

        // The three the root emission introduces: the class-name helper it imports, and
        // the two members it takes from its caller.
        for name in ["cn", "className", "style"] {
            #expect(bound.contains(name), "the page uses `\(name)` but binds it nowhere")
        }
        // And the root really does use all three, so the assertion above is not vacuous.
        #expect(source.contains("className={cn("))
        #expect(source.contains("...style,"))
    }

    @Test("A page that references a component still binds every identifier it uses")
    func pageWithARefBindsEverything() throws {
        let component = PenNode(
            id: "Cmp01",
            common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
            kind: .frame(PenNode.FrameData(layout: .vertical))
        )
        let page = PenNode(
            id: "Pag01",
            common: PenNodeCommon(name: "Home"),
            kind: .frame(PenNode.FrameData(
                fills: PenFills.single(.shorthand("#FFFFFF")),
                layout: .vertical,
                children: [
                    PenNode(
                        id: "Rf001",
                        common: PenNodeCommon(name: "Card Instance"),
                        kind: .ref(PenNode.RefData(ref: "Cmp01"))
                    ),
                ]
            ))
        )
        let doc = PenDocument(version: "2.17", children: [component, page])
        let files = ReactEmitter.emit(
            document: doc,
            components: ComponentAnalyzer.analyze(doc),
            pages: PageAnalyzer.analyze(doc),
            theme: ThemeAnalyzer.analyze(doc)
        ).files
        let source = try #require(files.first { $0.path == "pages/Home.tsx" }).content
        let bound = boundNames(in: source)

        for name in ["cn", "className", "style", "Card"] {
            #expect(bound.contains(name), "the page uses `\(name)` but binds it nowhere")
        }
    }
}
