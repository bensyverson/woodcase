import Foundation
import Testing
import Woodcase

/// A reusable component that is a ref to a reusable ref: a chain two links deep.
///
/// `Icn01` → `Out01` → `Btn01`. Each link overrides something the frame at the end
/// owns, so every override has to land on `Btn01`'s clone. The outer link's overrides
/// used to be patched onto the middle *ref node*, which has no children, and were lost:
/// the placed icon button kept its caption and its original padding.
struct PenRefExpanderChainTests {
    /// Three reusable links and one placed instance, as a .pen document.
    private static let document = ##"""
    {
      "version": "2.17",
      "children": [
        {"type": "frame", "id": "Btn01", "reusable": true, "padding": 20, "fill": "#111111",
         "children": [
           {"type": "text", "id": "Cap01", "content": "Go", "fill": "#ffffff", "fontSize": 13},
           {"type": "frame", "id": "Box01", "width": 10, "height": 10}
         ]},
        {"type": "ref", "id": "Out01", "ref": "Btn01", "reusable": true, "fill": "#ffffff",
         "descendants": {"Cap01": {"fill": "#222222"}}},
        {"type": "ref", "id": "Icn01", "ref": "Out01", "reusable": true, "padding": 4,
         "descendants": {"Cap01": {"enabled": false}}},
        {"type": "ref", "id": "Use01", "ref": "Icn01", "x": 0, "y": 0}
      ]
    }
    """##

    /// The placed instance `Use01`, expanded.
    private func placed() throws -> PenNode {
        let expanded = try PenRefExpander.expand(PenParser.parse(Self.document))
        return try #require(expanded.children.first { $0.id.hasPrefix("Use01") })
    }

    @Test("Every link's overrides land on the chain's frame, the outer link's last")
    func outerDescendantOverrideLands() throws {
        guard case let .frame(data) = try placed().kind else {
            Issue.record("expected the chain to end in a frame")
            return
        }
        let caption = try #require(data.children?.first { $0.id.hasSuffix("Cap01") })
        #expect(caption.common.enabled == .literal(false))
        // The middle link's override on the same node still applies.
        guard case let .text(text) = caption.kind else {
            Issue.record("expected a text caption")
            return
        }
        #expect(Self.color(text.fills) == "#222222")
        // Root overrides keep their precedence: outer link, then middle, then the frame.
        #expect(data.padding == .uniform(.literal(4)))
        #expect(Self.color(data.fills) == "#ffffff")
    }

    /// A solid fill's colour, however the JSON spelled it.
    private static func color(_ fills: PenFills?) -> String? {
        switch fills?.all.first {
        case let .shorthand(value): value
        case let .color(fill): if case let .literal(value) = fill.color { value } else { nil }
        default: nil
        }
    }
}
