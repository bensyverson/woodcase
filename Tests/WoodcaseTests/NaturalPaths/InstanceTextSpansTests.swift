//
//  InstanceTextSpansTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Rich text inside a component instance (Penumbra spec §7.6 (1), Ben's ruling of
/// 2026-10-11): a text inside an instance takes spans through an instance override, stored in
/// the override's own `metadata.woodcase.spans` and laid over the component text's metadata
/// key by key, as every Woodcase-owned key is (rule 6). The definition is never touched.
@MainActor
struct InstanceTextSpansTests {
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private static let words = "Make this bold"

    /// `bold` bolded and reddened, made for ``words``.
    private static let bold = PenTextSpans(text: words, runs: [
        PenTextRun(start: 10, end: 14, fontWeight: 700, fill: PenHexColor(red: 255, green: 0, blue: 0)),
    ])

    private static let title = ResolvedNodeAddress.instanceDescendant(refID: "Ins01", descendantKey: "Ttl01")

    /// A `Card` component holding the text `Ttl01`, whose metadata keeps a note and a blend,
    /// and two instances of it, `Ins01` and `Ins02`.
    private func document() -> EditableDocument {
        var metadata = PenMetadata(type: nil)
        metadata.extensions["note"] = .string("keep me")
        metadata[woodcase: .blendMode] = .string("multiply")
        let text = PenNode(
            id: "Ttl01",
            common: PenNodeCommon(name: "Title", metadata: metadata),
            kind: .text(PenNode.TextData(
                content: .literal(Self.words), fontFamily: .literal("Inter"), fontSize: .literal(20),
                fills: .single(.shorthand("#000000"))
            ))
        )
        let card = PenNode(
            id: "Crd01",
            common: PenNodeCommon(name: "Card", reusable: true),
            kind: .frame(PenNode.FrameData(width: .fixed(200), height: .fixed(40), children: [text]))
        )
        let first = PenNode(
            id: "Ins01", common: PenNodeCommon(name: "First", x: .literal(0), y: .literal(100)), kind: .ref(PenNode.RefData(ref: "Crd01"))
        )
        let second = PenNode(
            id: "Ins02", common: PenNodeCommon(name: "Second", x: .literal(0), y: .literal(200)), kind: .ref(PenNode.RefData(ref: "Crd01"))
        )
        return EditableDocument(from: PenDocument(children: [card, first, second]))
    }

    private func apply(_ plan: EditPlan, to document: EditableDocument) throws {
        for operation in plan.operations {
            try document.apply(operation)
        }
    }

    /// The `descendants` entry `Ins01` keeps for the title.
    private func titleOverride(in document: EditableDocument, of refID: String = "Ins01") -> [String: AnyCodable]? {
        guard case let .ref(data)? = document.node(id: refID)?.kind else { return nil }
        return data.descendants?["Ttl01"]?.properties
    }

    /// The `woodcase` object of an override's metadata.
    private func woodcase(_ properties: [String: AnyCodable]?) -> [String: AnyCodable]? {
        guard case let .dictionary(metadata)? = properties?["metadata"],
              case let .dictionary(keys)? = metadata[PenMetadata.woodcaseNamespace]
        else { return nil }
        return keys
    }

    private func expanded(_ id: String, in document: EditableDocument) -> PenNode? {
        NaturalPathFixture.expanded(id, in: document)
    }

    /// Bolds a word in `Ins01`'s title the way an editor's Format command does: the spans
    /// for the text as the instance shows it, planned where the instance stores them.
    private func boldTitle(in document: EditableDocument) throws -> EditPlan {
        let plan = try EditPlanner.plan(
            .set([PenMetadata.WoodcaseKey.spans.propertyPath: Self.bold.metadataValue]),
            routedAt: Self.title, in: document
        )
        try apply(plan, to: document)
        return plan
    }

    // MARK: - Planning

    @Test("Bolding a word in an instance's text plans a spans override on the instance, and the definition is unchanged")
    func boldingPlansAnOverride() throws {
        let document = document()
        let definition = document.node(id: "Ttl01")
        let plan = try boldTitle(in: document)

        #expect(plan.storage == .instanceOverride)
        #expect(plan.targetID == "Ins01")
        #expect(plan.operations.count == 1)
        guard case let .overrideDescendant(write)? = plan.operations.first else {
            Issue.record("expected one descendant override, got \(plan.operations)")
            return
        }
        #expect(write.refNodeID == "Ins01")
        #expect(write.descendantID == "Ttl01")
        #expect(woodcase(titleOverride(in: document))?["spans"] == Self.bold.metadataValue)
        #expect(titleOverride(in: document)?["spans"] == nil)
        #expect(document.node(id: "Ttl01") == definition)
        #expect(expanded("Ins01/Ttl01", in: document)?.appliedRuns == Self.bold.runs)
        #expect(expanded("Ins02/Ttl01", in: document)?.textSpans == nil)
    }

    @Test("The spans override merges per key: the component text's other metadata still reaches the instance")
    func spansMergePerKey() throws {
        let document = document()
        _ = try boldTitle(in: document)
        let title = try #require(expanded("Ins01/Ttl01", in: document))
        #expect(title.textSpans == Self.bold)
        #expect(title.blendMode == .multiply)
        #expect(title.common.metadata?.extensions["note"] == .string("keep me"))
    }

    @Test("Content and its spans written together land in one override, and the spans apply")
    func contentAndSpansTogether() throws {
        let document = document()
        let words = "Bold me now"
        let spans = PenTextSpans(text: words, runs: [PenTextRun(start: 0, end: 4, fontWeight: 700)])
        let plan = try EditPlanner.plan(
            .set(["kind.content": .string(words), PenMetadata.WoodcaseKey.spans.propertyPath: spans.metadataValue]),
            routedAt: Self.title, in: document
        )
        try apply(plan, to: document)
        #expect(plan.operations.count == 1)
        #expect(titleOverride(in: document)?["content"] == .string(words))
        let title = try #require(expanded("Ins01/Ttl01", in: document))
        #expect(title.appliedRuns == spans.runs)
        #expect(title.hasStaleTextSpans == false)
    }

    @Test("Malformed spans in an override are refused, as a set's are")
    func malformedSpansRefused() throws {
        let document = document()
        let malformed: AnyCodable = .dictionary([
            "text": .string(Self.words),
            "runs": .array([.dictionary(["start": 0, "end": 4, "bold": true])]),
        ])
        #expect {
            try EditPlanner.plan(
                .set([PenMetadata.WoodcaseKey.spans.propertyPath: malformed]), routedAt: Self.title, in: document
            )
        } throws: { error in
            guard let refusal = error as? EditRefusal else { return false }
            return refusal.errorCode == "textSpansRejected" && refusal.message.contains("bold")
                && refusal.message.contains("First/Title (Ins01/Ttl01)")
        }
        #expect(titleOverride(in: document) == nil)
    }

    @Test("Malformed spans on the root of a text component's instance are refused, and the ref keeps none")
    func malformedRootSpansRefused() throws {
        let text = PenNode(
            id: "Lbl01", common: PenNodeCommon(name: "Label", reusable: true),
            kind: .text(PenNode.TextData(content: .literal(Self.words)))
        )
        let instance = PenNode(id: "Ins09", common: PenNodeCommon(name: "Inst"), kind: .ref(PenNode.RefData(ref: "Lbl01")))
        let document = EditableDocument(from: PenDocument(children: [text, instance]))
        let malformed: AnyCodable = .dictionary(["text": .string(Self.words), "runs": .string("bold")])
        #expect {
            try EditPlanner.plan(
                .override([PenMetadata.WoodcaseKey.spans.propertyPath: malformed]), at: .node(id: "Ins09"), in: document
            )
        } throws: { error in
            (error as? EditRefusal)?.errorCode == "textSpansRejected"
        }
        #expect(document.node(id: "Ins09")?.common.metadata == nil)
    }

    @Test("Clearing the instance's spans with null draws the component's spans plain on that instance only")
    func nullClearsOnTheInstance() throws {
        let document = document()
        try apply(
            EditPlanner.plan(
                .set([PenMetadata.WoodcaseKey.spans.propertyPath: Self.bold.metadataValue]),
                routedAt: .node(id: "Ttl01"), in: document
            ),
            to: document
        )
        try apply(
            EditPlanner.plan(.set([PenMetadata.WoodcaseKey.spans.propertyPath: .null]), routedAt: Self.title, in: document),
            to: document
        )
        #expect(expanded("Ins01/Ttl01", in: document)?.textSpans == nil)
        #expect(expanded("Ins02/Ttl01", in: document)?.textSpans == Self.bold)
        #expect(document.node(id: "Ttl01")?.textSpans == Self.bold)
    }

    // MARK: - The component's edits

    @Test("A component spans edit reaches an instance without spans of its own, not one with them")
    func componentEditsFlowToInstancesWithoutTheirOwn() throws {
        let document = document()
        _ = try boldTitle(in: document)
        let italic = PenTextSpans(text: Self.words, runs: [PenTextRun(start: 0, end: 4, isItalic: true)])
        try apply(
            EditPlanner.plan(
                .set([PenMetadata.WoodcaseKey.spans.propertyPath: italic.metadataValue]),
                routedAt: .node(id: "Ttl01"), in: document
            ),
            to: document
        )
        #expect(expanded("Ins01/Ttl01", in: document)?.textSpans == Self.bold)
        #expect(expanded("Ins02/Ttl01", in: document)?.textSpans == italic)
    }

    // MARK: - Stale spans

    @Test("An instance's own spans go stale when its content override changes the words")
    func ownSpansGoStale() throws {
        let document = document()
        _ = try boldTitle(in: document)
        try apply(EditPlanner.plan(.override(["content": "Other words"]), at: Self.title, in: document), to: document)
        let title = try #require(expanded("Ins01/Ttl01", in: document))
        #expect(title.hasStaleTextSpans)
        #expect(title.appliedRuns.isEmpty)
    }

    @Test("The lint reports an instance's own stale spans on the instance's row")
    func lintReportsOwnStaleSpans() throws {
        let document = document()
        _ = try boldTitle(in: document)
        try apply(EditPlanner.plan(.override(["content": "Other words"]), at: Self.title, in: document), to: document)
        let stale = try DocumentLinter.findings(in: document).filter { $0.check == .spansStale }
        #expect(stale.map(\.nodeID) == ["Ins01/Ttl01"])
        #expect(stale.first?.message.contains("woodcase override") == true)
    }

    @Test("The lint reports a component's spans once, on the component, not on an instance that changed the words")
    func lintKeepsComponentSpansOnTheComponent() throws {
        let document = document()
        try apply(
            EditPlanner.plan(
                .set([PenMetadata.WoodcaseKey.spans.propertyPath: Self.bold.metadataValue]),
                routedAt: .node(id: "Ttl01"), in: document
            ),
            to: document
        )
        try apply(EditPlanner.plan(.override(["content": "Other words"]), at: Self.title, in: document), to: document)
        let stale = try DocumentLinter.findings(in: document).filter { $0.check == .spansStale }
        #expect(stale.isEmpty)
    }

    // MARK: - Storage and drawing

    @Test("An instance's spans round-trip through save and load in the override's metadata")
    func roundTrips() throws {
        let document = document()
        _ = try boldTitle(in: document)
        let reread = try EditableDocument(from: PenParser.parse(PenParser.encode(document.materialize())))
        #expect(woodcase(titleOverride(in: reread))?["spans"] == Self.bold.metadataValue)
        #expect(expanded("Ins01/Ttl01", in: reread)?.appliedRuns == Self.bold.runs)
    }

    @Test("The CG renderer draws the instance's bold red word, and leaves the other instance plain")
    func rendererDrawsTheOverride() throws {
        let document = document()
        let plain = try redPixels(of: "Ins01/Ttl01", in: document)
        _ = try boldTitle(in: document)
        #expect(plain == 0)
        #expect(try redPixels(of: "Ins01/Ttl01", in: document) > 0, "the instance's red run is missing")
        #expect(try redPixels(of: "Ins02/Ttl01", in: document) == 0)
    }

    /// The red pixels in one node's rect, in a render of the settled document.
    private func redPixels(of id: String, in document: EditableDocument) throws -> Int {
        let settled = PenVariableResolver.resolve(PenRefExpander.expand(document.materialize()))
        let rects = PenLayoutEngine.layout(settled)
        let canvas = PenLayoutEngine.canvasRects(in: settled, layoutRects: rects)
        let rect = try #require(canvas[id])
        let image = try #require(PenRenderer.render(settled, layoutRects: rects, size: CGSize(width: 300, height: 300)))
        let rgba = try #require(PenFillDomainTests.RGBA(image))
        return (Int(rect.y) ..< Int(rect.y + rect.height)).reduce(0) { count, y in
            count + (Int(rect.x) ..< Int(rect.x + rect.width)).count { x in
                let pixel = rgba.pixel(x, y)
                return pixel.r > 200 && pixel.g < 120 && pixel.b < 120
            }
        }
    }
}
