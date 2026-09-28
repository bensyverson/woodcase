//
//  SettledTreeReuseTests.swift
//  WoodcaseTests
//

import Foundation
import Synchronization
import Testing
@testable import Woodcase

/// A settle that reuses an earlier one lays out exactly the roots a write could have moved.
///
/// Roots lay out independently, so a settled tree is a set of per-root pieces, and a
/// piece is still good while everything it was built from is: the root's own subtree,
/// every component it draws — which is what the root's ``EditableDocument/revision(of:)``
/// pins — the document's variables, themes, imports and fonts, the theme asked for, the
/// libraries it was read with and the font set it was measured in. Each test here makes
/// one of those move and names the roots that must be laid out again; every one also
/// checks the result against a settle from nothing, because laying out too little is only
/// visible there. `IncrementalSettleEquivalenceTests` makes the same comparison across
/// every fixture.
@MainActor
struct SettledTreeReuseTests {
    /// A font generation the test moves by hand, so a registration by a suite running in
    /// parallel cannot turn an exact root list into a flake.
    final class Generation: Sendable {
        private let value = Mutex(0)

        /// The current generation.
        var current: Int {
            value.withLock { $0 }
        }

        /// Records that fonts were registered.
        func advance() {
            value.withLock { $0 += 1 }
        }
    }

    /// A deterministic measurer: the equivalence is about which nodes were laid out, not
    /// about Core Text.
    static let measurer: TextMeasurer = { text, _, fontSize, _, _, _, _, maxWidth in
        let size = fontSize ?? 16
        let width = Double(text.count) * size * 0.6
        guard let maxWidth, maxWidth > 0, width > maxWidth else { return (width, size * 1.2) }
        return (maxWidth, size * 1.2 * (width / maxWidth).rounded(.up))
    }

    let generation = Generation()

    /// The text sizes every settle in one test shares.
    var textSizes: TextSizeCache {
        let generation = generation
        return TextSizeCache(measuring: Self.measurer, fontGeneration: { generation.current })
    }

    // MARK: - Helpers

    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    /// A fixture document, by file name.
    private func fixture(_ name: String) throws -> EditableDocument {
        guard let url = Bundle.module.url(
            forResource: name, withExtension: "pen", subdirectory: "Fixtures"
        ) else {
            throw FixtureLoadError.notFound("\(name).pen")
        }
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    /// Settles `document` reusing `previous`, checks the answer against a settle from
    /// nothing, and returns the roots it laid out.
    private func resettle(
        _ document: EditableDocument,
        reusing previous: SettledTree?,
        theme: [String: String] = [:],
        textSizes: TextSizeCache,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> (tree: SettledTree, laidOut: [String]) {
        let tree = SettledTree(document: document, theme: theme, textSizes: textSizes, reusing: previous)
        let fresh = SettledTree(document: document, theme: theme, textMeasurer: Self.measurer)
        #expect(tree.rects == fresh.rects, "rects differ from a settle from nothing", sourceLocation: sourceLocation)
        #expect(
            tree.absoluteRects == fresh.absoluteRects,
            "absolute rects differ from a settle from nothing", sourceLocation: sourceLocation
        )
        #expect(tree.nodes == fresh.nodes, "nodes differ from a settle from nothing", sourceLocation: sourceLocation)
        return (tree, tree.ledger?.laidOut ?? [])
    }

    /// Sets a text node's content.
    private func edit(_ nodeID: String, to text: String, in document: EditableDocument) throws {
        try document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: nodeID, properties: ["kind.content": .string(text)]
        )))
    }

    // MARK: - Nothing to reuse, nothing moved

    @Test("a settle with nothing to reuse lays out every root, in root order")
    func nothingToReuse() throws {
        let document = try fixture("addressing")
        let settled = resettle(document, reusing: nil, textSizes: textSizes)
        #expect(settled.laidOut == ["Dash1", "Btn01", "Bge01"])
    }

    @Test("reusing a settle of the unchanged document lays out no root")
    func nothingMoved() throws {
        let document = try fixture("addressing")
        let sizes = textSizes
        let first = resettle(document, reusing: nil, textSizes: sizes)
        let second = resettle(document, reusing: first.tree, textSizes: sizes)
        #expect(second.laidOut.isEmpty)
    }

    // MARK: - Writes to nodes

    @Test("a write inside one root lays out that root alone")
    func aWriteInOneRoot() throws {
        let document = try fixture("addressing")
        let sizes = textSizes
        let first = resettle(document, reusing: nil, textSizes: sizes)
        try edit("Ttl01", to: "Renamed dashboard", in: document)
        #expect(resettle(document, reusing: first.tree, textSizes: sizes).laidOut == ["Dash1"])
    }

    @Test("a definition edit lays out the definition and every root that draws it")
    func aDefinitionEdit() throws {
        let document = try fixture("addressing")
        let sizes = textSizes
        let first = resettle(document, reusing: nil, textSizes: sizes)

        // Lbl01 is inside Btn01, which Dash1 instantiates; Bge01 draws no button.
        try edit("Lbl01", to: "A much longer label", in: document)
        let second = resettle(document, reusing: first.tree, textSizes: sizes)
        #expect(second.laidOut == ["Dash1", "Btn01"])

        // Cnt01 is inside Bge01, which Btn01 instantiates, which Dash1 instantiates.
        try edit("Cnt01", to: "12345", in: document)
        #expect(resettle(document, reusing: second.tree, textSizes: sizes).laidOut == ["Dash1", "Btn01", "Bge01"])
    }

    @Test("an edit to a component used only as slot content lays out the root that fills the slot")
    func aSlotContentDefinitionEdit() throws {
        let document = try fixture("slot-fill")
        let sizes = textSizes
        let first = resettle(document, reusing: nil, textSizes: sizes)

        // Page0's Inst0 fills Card0's slot with an instance of Badg0.
        try edit("BTxt0", to: "a longer badge", in: document)
        #expect(resettle(document, reusing: first.tree, textSizes: sizes).laidOut == ["Badg0", "Page0"])
    }

    @Test("an added root is laid out alone, and a deleted one leaves nothing behind")
    func rootsComeAndGo() throws {
        let document = try fixture("addressing")
        let sizes = textSizes
        let first = resettle(document, reusing: nil, textSizes: sizes)

        try document.apply(.insertNode(EditOperation.InsertNode(node: PenNode(
            id: "New01",
            common: PenNodeCommon(name: "New", x: .literal(2000), y: .literal(0)),
            kind: .frame(PenNode.FrameData(width: .fixed(100), height: .fixed(80)))
        ))))
        let added = resettle(document, reusing: first.tree, textSizes: sizes)
        #expect(added.laidOut == ["New01"])

        try document.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "Dash1")))
        let deleted = resettle(document, reusing: added.tree, textSizes: sizes)
        #expect(deleted.laidOut.isEmpty)
        #expect(deleted.tree.rects["Dash1"] == nil)
        #expect(deleted.tree.nodes["Ttl01"] == nil)
    }

    // MARK: - What every root reads

    @Test("a variable edit lays out every root")
    func aVariableEdit() throws {
        let document = try fixture("addressing")
        let sizes = textSizes
        let first = resettle(document, reusing: nil, textSizes: sizes)
        try document.apply(.addVariable(EditOperation.AddVariable(
            name: "gap", variable: PenVariable(type: .number, value: .simple(.int(8)))
        )))
        #expect(resettle(document, reusing: first.tree, textSizes: sizes).laidOut == ["Dash1", "Btn01", "Bge01"])
    }

    @Test("a theme axis edit lays out every root")
    func aThemeEdit() throws {
        let document = try fixture("addressing")
        let sizes = textSizes
        let first = resettle(document, reusing: nil, textSizes: sizes)
        try document.apply(.addThemeAxis(EditOperation.AddThemeAxis(name: "mode", options: ["light", "dark"])))
        #expect(resettle(document, reusing: first.tree, textSizes: sizes).laidOut == ["Dash1", "Btn01", "Bge01"])
    }

    @Test("a settle for another theme reuses nothing")
    func anotherTheme() throws {
        let document = try fixture("addressing")
        let sizes = textSizes
        let first = resettle(document, reusing: nil, textSizes: sizes)
        let dark = resettle(document, reusing: first.tree, theme: ["mode": "dark"], textSizes: sizes)
        #expect(dark.laidOut == ["Dash1", "Btn01", "Bge01"])
    }

    @Test("a font registration lays out every root, even with no write")
    func aFontRegistration() throws {
        let document = try fixture("addressing")
        let sizes = textSizes
        let first = resettle(document, reusing: nil, textSizes: sizes)
        generation.advance()
        #expect(resettle(document, reusing: first.tree, textSizes: sizes).laidOut == ["Dash1", "Btn01", "Bge01"])
    }

    /// A document that declares one font file Core Text already has: IBM Plex Sans,
    /// the file ``TestFontRegistration`` registers, by absolute path.
    private func fontsDeclaringDocument() throws -> EditableDocument {
        TestFontRegistration.registerTestFonts()
        let plex = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fonts/IBMPlexSans[wdth,wght].ttf")
        return try EditableDocument(from: PenParser.parse(Data("""
        {"version": "2.19", "fonts": [{"name": "IBM Plex Sans", "url": "\(plex.path)"}], "children": [
          {"type": "frame", "id": "Page1", "width": 200, "height": 100, "children": [
            {"type": "text", "id": "Text1", "content": "Hello", "fontFamily": "IBM Plex Sans"}
          ]},
          {"type": "frame", "id": "Page2", "x": 300, "width": 200, "height": 100}
        ]}
        """.utf8)))
    }

    /// Reads `document` twice, as two CLI reads of an unchanged file do, in the font set
    /// Core Text really has — so a registration that moves ``PenFontRegistry/generation``
    /// shows — and returns the roots the second read laid out.
    ///
    /// Suites running in parallel move the real generation too (`PenFontRegistrationCacheTests`
    /// calls ``PenFontRegistry/didRegisterFonts()`` outright), so one pair of reads can lose
    /// a race. The pair is tried a few times and the smallest answer wins: a read that moves
    /// the generation itself re-lays out every root on every try, so the retry can hide
    /// only the race, never the bug.
    private func rereadLaysOut(_ document: EditableDocument) -> [String] {
        var fewest: [String]?
        for _ in 0 ..< 5 {
            let sizes = TextSizeCache(measuring: Self.measurer)
            let first = resettle(document, reusing: nil, textSizes: sizes)
            #expect(first.laidOut == ["Page1", "Page2"])
            let again = resettle(document, reusing: first.tree, textSizes: sizes).laidOut
            if again.count < fewest?.count ?? .max { fewest = again }
            if again.isEmpty { break }
        }
        return fewest ?? []
    }

    @Test("rereading an unchanged document whose declared font is already registered lays out no root")
    func aDeclaredFontAlreadyRegistered() throws {
        #expect(try rereadLaysOut(fontsDeclaringDocument()).isEmpty)
    }

    @Test("rereading through a font resolver lays out no root when every declared font is already registered")
    func aDeclaredFontAlreadyRegisteredWithAResolver() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettledTreeReuseTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = try fontsDeclaringDocument()
        document.readContext = PenReadContext(fonts: GoogleFontResolver(
            cache: GoogleFontCache(rootDirectory: directory), fetcher: DeclaredFontsTests.RecordingFetcher()
        ))
        #expect(rereadLaysOut(document).isEmpty)
    }

    @Test("new libraries lay out every root")
    func aReadContextChange() throws {
        let document = try fixture("addressing")
        let sizes = textSizes
        let first = resettle(document, reusing: nil, textSizes: sizes)
        document.readContext = PenReadContext()
        #expect(resettle(document, reusing: first.tree, textSizes: sizes).laidOut == ["Dash1", "Btn01", "Bge01"])
    }

    @Test("a settle of another document reuses nothing")
    func anotherDocument() throws {
        let sizes = textSizes
        let first = try resettle(fixture("addressing"), reusing: nil, textSizes: sizes)
        let other = try fixture("addressing")
        #expect(resettle(other, reusing: first.tree, textSizes: sizes).laidOut == ["Dash1", "Btn01", "Bge01"])
    }

    // MARK: - Where pieces cannot be told apart

    @Test("two roots that settle a node under the same id are settled whole, and never reused")
    func aSharedIDIsSettledWhole() throws {
        // Inst1 expands Card1's root under "Inst1/Card1", the id Page1's child was authored with.
        let document = try EditableDocument(from: PenParser.parse(Data("""
        {"version": "2.10", "children": [
          {"type": "frame", "id": "Card1", "reusable": true, "width": 50, "height": 50},
          {"type": "ref", "id": "Inst1", "ref": "Card1", "x": 100},
          {"type": "frame", "id": "Page1", "x": 300, "width": 80, "height": 80, "children": [
            {"type": "frame", "id": "Inst1/Card1", "width": 10, "height": 10}
          ]}
        ]}
        """.utf8)))
        let sizes = textSizes
        let first = resettle(document, reusing: nil, textSizes: sizes)
        #expect(first.tree.ledger == nil)
        _ = resettle(document, reusing: first.tree, textSizes: sizes)
    }
}
