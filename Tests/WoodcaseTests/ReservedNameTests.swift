//
//  ReservedNameTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A component, page or icon whose name is one the generated code already means something
/// by — a JavaScript global (`String`), a web platform constructor (`Image`), a React export
/// (`Fragment`) or the package's own (`ThemeProvider`) — is renamed, so no emitted
/// declaration or import shadows it (issue 8xg1Mt: `render-mesh-malformed-points`' frame
/// `string` became `function String`).
struct ReservedNameTests {
    /// A document holding `frames`, each a small `frame` JSON object.
    private func document(_ frames: [String]) throws -> PenDocument {
        let json = ##"{"version": "2.17", "children": [\##(frames.joined(separator: ", "))]}"##
        return try PenParser.parse(Data(json.utf8))
    }

    /// A frame `id` named `name`, reusable or not, holding `children`.
    private func frame(_ id: String, _ name: String, reusable: Bool = false, children: [String] = []) -> String {
        ##"{"type": "frame", "id": "\##(id)", "name": "\##(name)", "reusable": \##(reusable), "width": 10, "height": 10, "##
            + ##""children": [\##(children.joined(separator: ", "))]}"##
    }

    /// An icon node `id` drawing `icon` from `library`.
    private func icon(_ id: String, _ icon: String, _ library: String) -> String {
        ##"{"type": "icon", "id": "\##(id)", "icon": "\##(icon)", "library": "\##(library)", "width": 24, "height": 24, "fill": "#000000"}"##
    }

    /// A ref `id` to the component `ref`.
    private func ref(_ id: String, _ ref: String) -> String {
        ##"{"type": "ref", "id": "\##(id)", "ref": "\##(ref)"}"##
    }

    private func pageNames(_ doc: PenDocument) -> [String: String] {
        Dictionary(uniqueKeysWithValues: PageAnalyzer.analyze(doc).map { ($0.id, $0.name) })
    }

    private func componentNames(_ doc: PenDocument) -> [String: String] {
        Dictionary(uniqueKeysWithValues: ComponentAnalyzer.analyze(doc).map { ($0.id, $0.name) })
    }

    private func emit(_ doc: PenDocument) -> [GeneratedFile] {
        ReactEmitter.emit(
            document: doc,
            components: ComponentAnalyzer.analyze(doc),
            pages: PageAnalyzer.analyze(doc),
            theme: ThemeAnalyzer.analyze(doc)
        ).files
    }

    // MARK: - Pages and components

    @Test("A page named for a reserved name is suffixed Page", arguments: [
        ("string", "StringPage"), ("Image", "ImagePage"), ("Fragment", "FragmentPage"),
        ("Map", "MapPage"), ("Text", "TextPage"), ("React", "ReactPage"), ("ThemeProvider", "ThemeProviderPage"),
    ])
    func reservedPage(name: String, expected: String) throws {
        let doc = try document([frame("P", name)])
        #expect(pageNames(doc) == ["P": expected])
    }

    @Test("A component named for a reserved name is suffixed Component", arguments: [
        ("Object", "ObjectComponent"), ("Text", "TextComponent"), ("Component/Image", "ImageComponent"),
        ("Suspense", "SuspenseComponent"), ("Event", "EventComponent"),
    ])
    func reservedComponent(name: String, expected: String) throws {
        let doc = try document([frame("C", name, reusable: true)])
        #expect(componentNames(doc) == ["C": expected])
    }

    @Test("A suffixed name that another already has is numbered, as any clash is")
    func suffixedNameNumbered() throws {
        let doc = try document([frame("A", "StringPage"), frame("B", "string")])
        #expect(pageNames(doc) == ["A": "StringPage", "B": "StringPage2"])
        let components = try document([frame("A", "TextComponent", reusable: true), frame("B", "Text", reusable: true)])
        #expect(componentNames(components) == ["A": "TextComponent", "B": "TextComponent2"])
    }

    @Test("React writes the page under its suffixed name, and no function named for the global")
    func reactPageFile() throws {
        let files = try emit(document([frame("P", "string")]))
        let page = try #require(files.first { $0.path == "pages/StringPage.tsx" }, "\(files.map(\.path))")
        #expect(page.content.contains("export function StringPage("))
        #expect(!files.contains { $0.content.contains("function String(") })
    }

    @Test("A page's ref to a renamed component imports and draws the renamed component")
    func refToRenamedComponent() throws {
        let doc = try document([frame("C", "Text", reusable: true), frame("P", "Home", children: [ref("r", "C")])])
        let files = emit(doc)
        let page = try #require(files.first { $0.path == "pages/Home.tsx" })
        #expect(page.content.contains(#"import { TextComponent } from "../components/TextComponent";"#))
        #expect(page.content.contains("<TextComponent"))
        #expect(files.contains { $0.path == "components/TextComponent.tsx" })
    }

    // MARK: - Icons

    /// Every icon import specifier in `source`, by import path.
    private func iconImports(_ source: String) -> [String: [String]] {
        var imports: [String: [String]] = [:]
        for match in source.matches(of: /import \{ ([^}]+) \} from "([^"]+)";/) {
            let path = String(match.output.2)
            guard IconLibraryMapping.family(forImportPath: path) != nil else { continue }
            imports[path, default: []] += match.output.1.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return imports
    }

    @Test("An icon named for a reserved name is imported under an alias")
    func reservedIcon() throws {
        let doc = try document([frame("P", "Home", children: [icon("i", "map", "lucide")])])
        let page = try #require(emit(doc).first { $0.path == "pages/Home.tsx" })
        #expect(iconImports(page.content) == ["lucide-react": ["Map as MapLucide"]], "\(page.content)")
        #expect(page.content.contains("<MapLucide"))
        #expect(!page.content.contains("<Map "))
    }

    /// Each path carries Pen's default weight, 200, since leaf AyTAji.
    @Test("One icon name from two families is imported once plainly and once under an alias")
    func iconNameFromTwoFamilies() throws {
        let doc = try document([frame("P", "Home", children: [
            icon("a", "vpn_lock", "Material Symbols Outlined"),
            icon("b", "vpn_lock", "Material Symbols Rounded"),
            icon("c", "vpn_lock", "Material Symbols Sharp"),
        ])])
        let page = try #require(emit(doc).first { $0.path == "pages/Home.tsx" })
        #expect(iconImports(page.content) == [
            "@nine-thirty-five/material-symbols-react/outlined/200": ["VpnLock"],
            "@nine-thirty-five/material-symbols-react/rounded/200": ["VpnLock as VpnLockRounded"],
            "@nine-thirty-five/material-symbols-react/sharp/200": ["VpnLock as VpnLockSharp"],
        ], "\(page.content)")
        for name in ["<VpnLock ", "<VpnLockRounded ", "<VpnLockSharp "] {
            #expect(page.content.contains(name), "\(name)")
        }
    }

    @Test("An icon named like a component is imported under an alias")
    func iconNamedLikeComponent() throws {
        let doc = try document([
            frame("C", "Bell", reusable: true),
            frame("P", "Home", children: [ref("r", "C"), icon("i", "bell", "lucide")]),
        ])
        let page = try #require(emit(doc).first { $0.path == "pages/Home.tsx" })
        #expect(iconImports(page.content) == ["lucide-react": ["Bell as BellLucide"]], "\(page.content)")
        #expect(page.content.contains(#"import { Bell } from "../components/Bell";"#))
        #expect(page.content.contains("<BellLucide"))
    }

    @Test("An icon inside a component named like it is imported under an alias")
    func iconNamedLikeItsComponent() throws {
        let doc = try document([frame("C", "Heart", reusable: true, children: [icon("i", "heart", "lucide")])])
        let component = try #require(emit(doc).first { $0.path == "components/Heart.tsx" })
        #expect(iconImports(component.content) == ["lucide-react": ["Heart as HeartLucide"]], "\(component.content)")
        #expect(component.content.contains("<HeartLucide"))
    }
}
