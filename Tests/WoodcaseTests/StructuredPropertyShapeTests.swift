//
//  StructuredPropertyShapeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The refusals a *structured* property raises — a fill, a stroke, an effect, a
/// corner radius, a padding.
///
/// A scalar property's refusal is easy: the value is a boolean where a number
/// belongs, and naming the two shapes is the whole message. A structured one is
/// not, because "array" is both an accepted form and, when one element is wrong,
/// the shape that was refused — which is how
/// `kind.fills=[{"type":"solid","color":"#FFD166"}]` came to be refused with a
/// sentence that listed arrays as accepted. These pin both halves: the accepted
/// forms name their wire spellings and carry a literal to paste, and the refusal
/// says *what in the value* was wrong.
@Suite("Structured property shapes")
struct StructuredPropertyShapeTests {
    // MARK: - Helpers

    /// A frame, which carries every structured property under test.
    private func frame() -> PenNode {
        PenNode(
            id: "f1",
            common: PenNodeCommon(name: "Cards"),
            kind: .frame(PenNode.FrameData(width: .fixed(100), height: .fixed(60)))
        )
    }

    /// The `expected` and `actual` of the mismatch an authored write raises, or `nil` if it did not.
    ///
    /// An authored write is checked by ``NodePropertyCodec/checkAuthored(_:on:)`` before
    /// ``NodePropertyCodec/setting(_:at:on:)`` runs, as the batch planner does: `setting`
    /// alone is also the funnel undo and a CRDT peer write through, so it keeps a fill or
    /// effect `type` it does not model instead of refusing it.
    private func mismatch(_ value: AnyCodable, at path: String) -> (expected: String, actual: String)? {
        do {
            try NodePropertyCodec.checkAuthored([path: value], on: frame())
            _ = try NodePropertyCodec.setting(value, at: path, on: frame())
            return nil
        } catch let error as EditingError {
            guard case let .propertyTypeMismatch(_, _, expected, actual) = error else { return nil }
            return (expected, actual)
        } catch {
            return nil
        }
    }

    /// The JSON literal `text` describes, as the command line would type it.
    private func json(_ text: String) throws -> AnyCodable {
        try JSONDecoder().decode(AnyCodable.self, from: Data(text.utf8))
    }

    // MARK: - The reported refusal

    @Test("An array of fills with an unknown type names the element and the spelling")
    func fillArrayWithUnknownTypeNamesTheElement() throws {
        let value = try json(##"[{"type":"solid","color":"#FFD166"}]"##)
        let refusal = try #require(mismatch(value, at: "kind.fills"))

        // The refusal must say what in the array was wrong, not merely "an array" —
        // the array form is one of the accepted ones.
        #expect(refusal.actual != "array")
        #expect(refusal.actual != "an array")
        #expect(refusal.actual.contains("[0]"))
        #expect(refusal.actual.contains("solid"))
    }

    @Test("The accepted forms carry the wire spellings and a literal to paste")
    func fillShapeCarriesSpellingsAndExample() throws {
        let value = try json(##"[{"type":"solid","color":"#FFD166"}]"##)
        let refusal = try #require(mismatch(value, at: "kind.fills"))

        for spelling in ["color", "gradient", "image", "mesh_gradient", "shader"] {
            #expect(refusal.expected.contains(spelling), "the accepted spellings omit \(spelling)")
        }
        #expect(refusal.expected.contains(##"{"type":"color","color":"#FFD166"}"##))
    }

    @Test("The fill the message recommends is the fill the codec accepts")
    func recommendedFillIsAccepted() throws {
        let value = try json(##"[{"type":"color","color":"#FFD166"}]"##)
        let patched = try NodePropertyCodec.setting(value, at: "kind.fills", on: frame())

        guard case let .frame(data) = patched.kind else { Issue.record("not a frame"); return }
        #expect(data.fills == .multiple([.color(PenFill.PenColorFill(color: .literal("#FFD166")))]))
    }

    // MARK: - The same class of refusal, across every structured property

    /// A value that must be refused, and the words the refusal has to contain.
    struct BadValue {
        let path: String
        let literal: String
        let mustSay: [String]
    }

    static let badValues: [BadValue] = [
        BadValue(
            path: "kind.fills",
            literal: ##"[{"type":"solid","color":"#FFD166"}]"##,
            mustSay: ["[0]", "solid"]
        ),
        BadValue(
            path: "kind.stroke",
            literal: ##"[{"type":"solid","color":"#FFD166"}]"##,
            mustSay: ["[0]", "solid"]
        ),
        BadValue(
            path: "kind.effects",
            literal: #"[{"type":"drop_shadow","blur":8}]"#,
            mustSay: ["[0]", "drop_shadow"]
        ),
        BadValue(
            path: "kind.fills",
            literal: #"[{"type":"color"}]"#,
            mustSay: ["[0]", "color"]
        ),
        BadValue(path: "kind.cornerRadius", literal: "[1,2,3]", mustSay: ["4", "3"]),
        BadValue(path: "kind.padding", literal: "[1,2,3]", mustSay: ["2", "4", "3"]),
    ]

    @Test("Every structured property says what in the value was wrong", arguments: badValues)
    func structuredRefusalsExplainThemselves(bad: BadValue) throws {
        let refusal = try #require(
            try mismatch(json(bad.literal), at: bad.path),
            "\(bad.path)=\(bad.literal) was not refused"
        )
        for word in bad.mustSay {
            #expect(
                refusal.actual.contains(word),
                "\(bad.path)=\(bad.literal) refused with \"\(refusal.actual)\", which never says \(word)"
            )
        }
    }

    // MARK: - Every example in the table is a value the codec accepts

    /// The kinds the example sweep writes onto, between them covering every field
    /// that carries one.
    static let sampleKinds: [PenNode.Kind] = [
        .frame(PenNode.FrameData(width: .fixed(100), height: .fixed(60))),
        .text(PenNode.TextData(content: .literal("hi"))),
        .path(PenNode.PathData(geometry: "M0 0 L1 1")),
        .polygon(PenNode.PolygonData(width: .fixed(10))),
        .icon(PenNode.IconData(icon: .literal("star"))),
        .script(PenNode.ScriptData(scriptUri: "s.js")),
        .browser(PenNode.BrowserData(url: "example.com")),
        .connection(PenNode.ConnectionData(
            source: PenNode.ConnectionData.Endpoint(path: "a", anchor: .right),
            target: PenNode.ConnectionData.Endpoint(path: "b", anchor: .left)
        )),
        .ref(PenNode.RefData(ref: "Button")),
    ]

    @Test("Every literal a refusal offers is one the codec takes", arguments: NodePropertyCodec.shapes.keys.sorted())
    func everyExampleIsAccepted(field: String) throws {
        guard let example = NodePropertyCodec.shape(of: field)?.example else { return }
        let value = try json(example)

        var written = false
        for kind in Self.sampleKinds {
            let node = PenNode(id: "n1", common: PenNodeCommon(), kind: kind)
            for prefix in ["common.", "kind."] where NodePropertyCodec.paths(for: node).contains(prefix + field) {
                _ = try NodePropertyCodec.setting(value, at: prefix + field, on: node)
                written = true
            }
        }
        #expect(written, "no sample node carries \(field), so its example \(example) is never checked")
    }

    // MARK: - The padding order is the one the .pen schema writes

    @Test("A two-element padding is [vertical, horizontal], as the message says it is")
    func paddingShapeMatchesTheSchema() throws {
        let patched = try NodePropertyCodec.setting(json("[12,16]"), at: "kind.padding", on: frame())
        guard case let .frame(data) = patched.kind else { Issue.record("not a frame"); return }
        #expect(data.padding?.resolve() == PenPadding.Edges(top: 12, right: 16, bottom: 12, left: 16))

        // The refusal text must not tell a caller the opposite of what the decoder does.
        let refusal = try #require(try mismatch(json("[1,2,3]"), at: "kind.padding"))
        #expect(refusal.expected.contains("[vertical, horizontal]"))
        #expect(!refusal.expected.contains("[horizontal, vertical]"))
    }
}
