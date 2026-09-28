//
//  SwiftUIEmitterSlotTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What a component's slot frames become in emitted SwiftUI: one generic `@ViewBuilder`
/// parameter per slot, a default-content view and a constrained init for the slots an
/// instance leaves alone, and trailing closures on the calls that fill them. Over
/// `codegen-slots.pen` (a card with one slot, a panel with two, a button with one) and small
/// synthetic documents for the edges; the goldens (``SwiftUIEmitterComponentGoldenTests``)
/// pin the fixture's files whole.
struct SwiftUIEmitterSlotTests {
    // MARK: - The component

    @Test("A slot is a generic @ViewBuilder parameter, stored and drawn inside the slot frame")
    func slotParameter() throws {
        let card = try Self.file("Components/Card.swift")
        #expect(card.contains("public struct Card<Content: View>: View {"))
        #expect(card.contains("    private let content: Content\n"))
        #expect(card.contains("    public init(title: String = \"Card title\", @ViewBuilder content: () -> Content) {"))
        #expect(card.contains("        self.content = content()\n"))
        #expect(card.contains(/VStack\(alignment: \.leading, spacing: 8\) \{\n\s+content\n\s+\}/))
    }

    @Test("A slot's own children are its default: a view of their own and a constrained init that passes it")
    func defaultContent() throws {
        let card = try Self.file("Components/Card.swift")
        #expect(card.contains("extension Card where Content == CardContentDefault {"))
        #expect(card.contains("    public init(title: String = \"Card title\") {\n        self.init(title: title, content: { CardContentDefault() })\n    }"))
        #expect(card.contains("public struct CardContentDefault: View {"))
        // The default text is drawn once, by the default view, not by the card's body.
        #expect(card.components(separatedBy: "Text(\"Nothing here yet\")").count == 2)
        #expect(card.contains("#Preview {\n    Card()\n}"))
    }

    @Test("Two slots are two generics in order, and an empty slot's default is EmptyView")
    func twoSlots() throws {
        let panel = try Self.file("Components/Panel.swift")
        #expect(panel.contains("public struct Panel<HeaderContent: View, FooterContent: View>: View {"))
        #expect(panel.contains("public init(@ViewBuilder header: () -> HeaderContent, @ViewBuilder footer: () -> FooterContent) {"))
        #expect(panel.contains("extension Panel where HeaderContent == EmptyView, FooterContent == PanelFooterDefault {"))
        #expect(panel.contains("self.init(header: { EmptyView() }, footer: { PanelFooterDefault() })"))
        #expect(panel.contains("public struct PanelFooterDefault: View {"))
        #expect(!panel.contains("PanelHeaderDefault"))
    }

    @Test("A control's slot follows its members, and the default init forwards them")
    func slottedControl() throws {
        let button = try Self.file("Components/SlotButton.swift")
        #expect(button.contains("public struct SlotButton<IconContent: View>: View {"))
        #expect(button.contains("action: @escaping () -> Void = {}, @ViewBuilder icon: () -> IconContent) {"))
        #expect(button.contains("extension SlotButton where IconContent == SlotButtonIconDefault {"))
        #expect(button.contains("self.init(label: label, action: action, icon: { SlotButtonIconDefault() })"))
    }

    // MARK: - The calls

    @Test("An instance that fills the slot is a call with a trailing closure holding the fill")
    func filledCall() throws {
        let page = try Self.file("Pages/FilledCard.swift")
        #expect(page.contains("Card(title: \"Recent orders\") {"))
        #expect(page.contains("Text(\"Order 1024 shipped\")"))
        #expect(page.contains("Text(\"Order 1025 packed\")"))
        #expect(!page.contains("inlined"))
        let profile = try Self.file("Pages/ProfileCard.swift")
        #expect(profile.contains("Card(title: \"Profile\") {"))
        #expect(profile.contains("Text(\"Ada Lovelace\")"))
    }

    @Test("An instance that leaves the slot alone is a call without a closure")
    func defaultCall() throws {
        let page = try Self.file("Pages/DefaultCard.swift")
        #expect(page.contains("Card(title: \"Inbox\")\n"))
        #expect(!page.contains("Card(title: \"Inbox\") {"))
    }

    @Test("Filling two slots is labelled trailing closures; a slot left alone passes its default")
    func labelledClosures() throws {
        let filled = try Self.file("Pages/FilledPanel.swift")
        #expect(filled.contains(/Panel \{\n\s+Text\("Settings"\)/))
        #expect(filled.contains(/\} footer: \{\n\s+Text\("Cancel"\)/))
        let header = try Self.file("Pages/HeaderPanel.swift")
        #expect(header.contains(/Panel \{\n\s+Text\("Notifications"\)/))
        #expect(header.contains(/\} footer: \{\n\s+PanelFooterDefault\(\)\n\s+\}/))
    }

    @Test("A filled control is its call with the prop argument and the trailing closure")
    func filledControl() throws {
        let page = try Self.file("Pages/UploadButton.swift")
        #expect(page.contains("SlotButton(label: \"Upload\") {"))
    }

    @Test("No instance of the fixture is inlined")
    func nothingInlined() throws {
        let diagnostics = PenDiagnosticCollector()
        _ = try SwiftUIFixtures.emit("codegen-slots", diagnostics: diagnostics)
        let inlined = diagnostics.diagnostics.filter { $0.message.contains("inlined") }
        #expect(inlined.isEmpty, "\(inlined.map(\.message))")
    }

    // MARK: - Edges

    @Test("A slot that shares a prop's name takes the name with Content")
    func slotNameCollision() throws {
        let emitted = try emit([Self.titled(slot: ##""slot": [], "layout": "vertical""##)])
        let file = try #require(emitted.files["Sources/PenUI/Components/Box.swift"])
        #expect(file.contains("public struct Box<TitleContent: View>: View {"))
        #expect(file.contains("@ViewBuilder titleContent: () -> TitleContent"))
    }

    @Test("A slot frame that spreads its children with spacers is drawn as a frame, and the fill inlines")
    func spreadSlot() throws {
        let emitted = try emit([
            Self.titled(slot: ##""slot": [], "layout": "horizontal", "justifyContent": "space_between""##),
            Self.page(##"{"type": "ref", "id": "i", "ref": "B", "descendants": {"S": {"children": [{"type": "text", "id": "t", "content": "Hi"}]}}}"##),
        ])
        let file = try #require(emitted.files["Sources/PenUI/Components/Box.swift"])
        #expect(file.contains("public struct Box: View {"))
        #expect(emitted.diagnostics.contains { $0.nodeID == "B" && $0.message.contains("slot") && $0.message.contains("space_between") })
        let page = try #require(emitted.files["Sources/PenUI/Pages/Board.swift"])
        #expect(page.contains("// woodcase: inlined from Box"))
    }

    @Test("A fill with an absolutely placed child in a stacked slot inlines")
    func absoluteFill() throws {
        let emitted = try emit([
            Self.titled(slot: ##""slot": [], "layout": "vertical""##),
            Self.page(##"""
            {"type": "ref", "id": "i", "ref": "B", "descendants": {"S": {"children": [
              {"type": "text", "id": "t", "content": "Hi", "layoutPosition": "absolute", "x": 4, "y": 4}]}}}
            """##),
        ])
        let page = try #require(emitted.files["Sources/PenUI/Pages/Board.swift"])
        #expect(page.contains("// woodcase: inlined from Box"))
    }

    @Test("A prop read inside a slot's default content is left out with a warning")
    func propInDefault() throws {
        let box = ##"""
        {"type": "frame", "id": "B", "name": "Box", "reusable": true, "width": 100, "height": 40, "layout": "vertical",
         "metadata": {"type": "component", "_props": {"note": "Slot/Note"}},
         "children": [{"type": "frame", "id": "S", "name": "Slot", "slot": [], "layout": "vertical",
                       "children": [{"type": "text", "id": "N", "name": "Note", "content": "Empty"}]}]}
        """##
        let emitted = try emit([box])
        let file = try #require(emitted.files["Sources/PenUI/Components/Box.swift"])
        #expect(!file.contains("public let note"))
        #expect(emitted.diagnostics.contains { $0.message.contains("\"note\"") && $0.message.contains("default content") })
    }

    // MARK: - Helpers

    /// A file `codegen-slots.pen` emits, by its path under the module.
    private static func file(_ path: String) throws -> String {
        let files = try SwiftUIFixtures.emit("codegen-slots").files
        return try #require(files.first { $0.path == "Sources/PenUI/\(path)" }?.content, "no \(path)")
    }

    /// A component `Box` with a `title` text prop and a frame `S` named "Title" of `slot`'s properties.
    private static func titled(slot: String) -> String {
        ##"""
        {"type": "frame", "id": "B", "name": "Box", "reusable": true, "width": 100, "height": 60, "layout": "vertical",
         "metadata": {"type": "component", "_props": {"title": "Label"}},
         "children": [{"type": "text", "id": "L", "name": "Label", "content": "Box"},
                      {"type": "frame", "id": "S", "name": "Title", "width": 80, "height": 20, \##(slot)}]}
        """##
    }

    /// A page `Board` holding `children`.
    private static func page(_ children: String) -> String {
        ##"{"type": "frame", "id": "P", "name": "Board", "width": 200, "height": 200, "layout": "vertical", "children": [\##(children)]}"##
    }

    private func emit(_ nodes: [String]) throws -> (files: [String: String], diagnostics: [PenDiagnostic]) {
        let json = ##"{"version": "2.17", "children": [\##(nodes.joined(separator: ", "))]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let diagnostics = PenDiagnosticCollector()
        let result = SwiftUIEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document),
            pages: PageAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document), diagnostics: diagnostics
        )
        let files = Dictionary(result.files.map { ($0.path, $0.content) }) { first, _ in first }
        return (files, diagnostics.diagnostics)
    }
}
