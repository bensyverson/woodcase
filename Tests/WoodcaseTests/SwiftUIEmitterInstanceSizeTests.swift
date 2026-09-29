//
//  SwiftUIEmitterInstanceSizeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How an instance's size reaches emitted SwiftUI. A component's fixed root size is its
/// *ideal* size — the body is flexible, so a parent sizes it — and every call states the
/// size the instance sits at with a `.frame`, as the previews do; so an instance that
/// resizes its component is a call, not a copy. A ref to a state variant calls the merged
/// view in that state.
struct SwiftUIEmitterInstanceSizeTests {
    // MARK: - The component

    @Test("A component's fixed root size is its ideal size in a flexible frame")
    func idealRoot() throws {
        let file = try #require(try emit([card]).files["Sources/PenUI/Components/Card.swift"])
        #expect(file.contains(".frame(minWidth: 0, idealWidth: 140, maxWidth: .infinity, minHeight: 0, idealHeight: 80, maxHeight: .infinity"))
        let body = try #require(file.components(separatedBy: "#Preview").first)
        #expect(!body.contains(".frame(width: 140"))
    }

    @Test("A component's preview draws it at its own size")
    func previewAtOwnSize() throws {
        let file = try #require(try emit([card]).files["Sources/PenUI/Components/Card.swift"])
        #expect(file.contains("#Preview {\n    Card()\n        .frame(width: 140, height: 80)\n}"))
    }

    @Test("A component fixed on one axis is framed on that axis alone in its preview")
    func previewOneAxis() throws {
        let file = try #require(try emit([strip]).files["Sources/PenUI/Components/Strip.swift"])
        #expect(file.contains("#Preview {\n    Strip()\n        .frame(width: 200)\n}"))
    }

    @Test("A catalog specimen draws the component at its own size")
    func catalogAtOwnSize() throws {
        let sheet = try #require(try emit([card]).files["Sources/PenUI/Catalog/PenCatalogSheet.swift"])
        #expect(sheet.contains("Card()\n                            .frame(width: 140, height: 80)"))
    }

    // MARK: - The call

    @Test("An instance at its component's size is a call framed to that size")
    func bareCall() throws {
        let code = try pageSource([card], instance: ##"{"type": "ref", "id": "i", "ref": "K"}"##)
        #expect(code.contains("Card()\n                .frame(width: 140, height: 80)\n"))
    }

    @Test("A fill_container instance of a fixed-size component is a call, framed only on its fixed axis")
    func fillCall() throws {
        let emitted = try emit([card, page(##"{"type": "ref", "id": "i", "ref": "K", "width": "fill_container"}"##)])
        let code = try #require(emitted.files["Sources/PenUI/Pages/Board.swift"])
        #expect(code.contains("Card()\n                .frame(height: 80)\n"))
        #expect(!code.contains("inlined from"))
        #expect(!emitted.diagnostics.contains { $0.nodeID == "i" })
    }

    @Test("A fixed instance of another size is a call framed to the instance's size")
    func resizedCall() throws {
        let code = try pageSource([card], instance: ##"{"type": "ref", "id": "i", "ref": "K", "width": 200, "height": 90}"##)
        #expect(code.contains("Card()\n                .frame(width: 200, height: 90)\n"))
        #expect(!code.contains("inlined from"))
    }

    @Test("A resized instance keeps its prop arguments")
    func resizedCallWithArguments() throws {
        let code = try pageSource([card], instance: ##"""
        {"type": "ref", "id": "i", "ref": "K", "width": "fill_container", "descendants": {"L": {"content": "Revenue"}}}
        """##)
        #expect(code.contains("Card(label: \"Revenue\")\n                .frame(height: 80)\n"))
    }

    @Test("A fill_container instance in a ZStack takes its fallback as a fixed frame")
    func fillInZStack() throws {
        let json = page(##"{"type": "ref", "id": "i", "ref": "K", "width": "fill_container(160)"}"##, layout: "none")
        let code = try #require(try emit([card, json]).files["Sources/PenUI/Pages/Board.swift"])
        #expect(code.contains("Card()\n                .frame(width: 160, height: 80)"))
    }

    @Test("A fit_content instance of a fixed-size component is still a copy: no frame says it")
    func fitInstanceInlines() throws {
        let emitted = try emit([card, page(##"{"type": "ref", "id": "i", "ref": "K", "width": "fit_content"}"##)])
        let code = try #require(emitted.files["Sources/PenUI/Pages/Board.swift"])
        #expect(code.contains("// woodcase: inlined from Card"))
        #expect(emitted.diagnostics.contains { $0.nodeID == "i" && $0.message.contains("no frame at the call can size its root's width") })
    }

    @Test("A resized instance of a content-sized component is still a copy: its paint would not follow")
    func contentSizedInlines() throws {
        let emitted = try emit([swatch, page(##"{"type": "ref", "id": "i", "ref": "W", "width": 50}"##)])
        let code = try #require(emitted.files["Sources/PenUI/Pages/Board.swift"])
        #expect(code.contains("// woodcase: inlined from Swatch"))
        #expect(emitted.diagnostics.contains { $0.nodeID == "i" && $0.message.contains("no frame at the call can size its root's width") })
    }

    // MARK: - State variants

    @Test("A ref to a state variant calls the merged view in that state")
    func variantCall() throws {
        let emitted = try emit([bar, barHome, page(##"{"type": "ref", "id": "i", "ref": "BH", "width": "fill_container"}"##)])
        let code = try #require(emitted.files["Sources/PenUI/Pages/Board.swift"])
        #expect(code.contains("Bar(selected: .home)\n                .frame(height: 50)\n"))
        #expect(!code.contains("inlined from"))
    }

    @Test("A ref to a state variant with an override no prop carries is a copy of the variant")
    func variantCopy() throws {
        let emitted = try emit([bar, barHome, page(##"{"type": "ref", "id": "i", "ref": "BH", "descendants": {"HL": {"fontSize": 20}}}"##)])
        let code = try #require(emitted.files["Sources/PenUI/Pages/Board.swift"])
        #expect(code.contains("// woodcase: inlined from Bar"))
        #expect(emitted.diagnostics.contains { $0.nodeID == "i" && $0.message.contains("no prop carries its overrides of HL") })
        #expect(code.contains(".penFont(size: 20)"))
    }

    // MARK: - woodcase-app

    @Test("woodcase-app's screens call their rows, status and tab bars; only overrides no prop carries copy")
    func woodcaseAppCalls() throws {
        let result = try SwiftUIFixtures.emit("woodcase-app")
        let files = Dictionary(result.files.map { ($0.path, $0.content) }) { first, _ in first }
        func component(_ name: String) throws -> String {
            try #require(files.first { $0.key.hasSuffix("/Components/\(name).swift") }?.value)
        }
        let home = try component("HomeCollection")
        #expect(home.contains("TabBar(selected: .home)\n"))
        #expect(home.contains("FavoriteCard(brand: \"Palomino\", name: \"Blackwing 602\")\n                            .frame(width: 160)"))
        #expect(try component("UsageLog").contains("TabBar(selected: .log)\n"))
        let settings = try component("ScreenSettings")
        #expect(settings.contains("StatusBar()\n                .frame(height: 62)"))
        #expect(settings.contains("ToggleRow(label: \"Dark Mode\")\n"))
        #expect(settings.contains("ActionButton(label: \"Export Data\")\n"))
        // The status bars' page fill and the Delete button's red are root fills no prop carries.
        for name in ["HomeCollection", "UsageLog", "ScreenSettings"] {
            #expect(try component(name).components(separatedBy: "// woodcase: inlined from").count == 2, "\(name)")
        }
    }

    // MARK: - Helpers

    /// A 140 × 80 card whose `label` prop reads its text.
    private let card = ##"""
    {"type": "frame", "id": "K", "name": "Card", "reusable": true, "width": 140, "height": 80, "layout": "vertical",
     "metadata": {"type": "component", "_props": {"label": "Label"}},
     "children": [{"type": "text", "id": "L", "name": "Label", "content": "Total", "fontSize": 12}]}
    """##

    /// A 300 × 50 tab bar, whose variants are reusable frames of their own.
    private let bar = ##"""
    {"type": "frame", "id": "B", "name": "Bar", "reusable": true, "width": 300, "height": 50, "metadata": {"_role": "tabBar"},
     "children": [{"type": "text", "id": "BL", "name": "Label", "content": "Home", "fontSize": 12}]}
    """##

    /// The tab bar with its home tab selected: a whole frame, as Pen writes one.
    private let barHome = ##"""
    {"type": "frame", "id": "BH", "name": "Bar:home", "reusable": true, "width": 300, "height": 50, "fill": "#FF0000",
     "children": [{"type": "text", "id": "HL", "name": "Label", "content": "Home", "fontSize": 12}]}
    """##

    /// A strip fixed at 200 wide and as tall as its content.
    private let strip = ##"""
    {"type": "frame", "id": "S", "name": "Strip", "reusable": true, "width": 200, "layout": "horizontal",
     "children": [{"type": "text", "id": "T", "content": "Strip"}]}
    """##

    /// A swatch sized by its content, painted.
    private let swatch = ##"""
    {"type": "frame", "id": "W", "name": "Swatch", "reusable": true, "fill": "#00FF00",
     "children": [{"type": "rectangle", "id": "D", "name": "Dot", "width": 10, "height": 10, "fill": "#FF0000"}]}
    """##

    /// A page frame named Board holding `children` (comma-separated node objects).
    private func page(_ children: String, layout: String = "vertical") -> String {
        ##"{"type": "frame", "id": "root", "name": "Board", "layout": "\##(layout)", "width": 400, "height": 300, "children": [\##(children)]}"##
    }

    /// The emitted page of a document holding `nodes` and a Board page around `instance`.
    private func pageSource(_ nodes: [String], instance: String) throws -> String {
        try #require(try emit(nodes + [page(instance)]).files["Sources/PenUI/Pages/Board.swift"])
    }

    /// Emit a document whose top-level nodes are `nodes`, the way `woodcase generate swiftui` does.
    private func emit(_ nodes: [String]) throws -> (files: [String: String], diagnostics: [PenDiagnostic]) {
        let json = ##"{"version": "2.17", "children": [\##(nodes.joined(separator: ", "))]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let diagnostics = PenDiagnosticCollector()
        let result = try SwiftUIEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document),
            pages: PageAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document), diagnostics: diagnostics
        )
        let files = Dictionary(result.files.map { ($0.path, $0.content) }) { first, _ in first }
        return (files, diagnostics.diagnostics)
    }
}
