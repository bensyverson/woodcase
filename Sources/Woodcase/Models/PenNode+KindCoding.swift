//
//  PenNode+KindCoding.swift
//  Woodcase
//

import Foundation

/// The type-specific half of a node's Codable conformance.
///
/// A node decodes its children inside its payload's decoder, so ``PenNode/init(from:)``
/// is on the stack once per level of the tree. Written as one `switch` over sixteen
/// payload types, a debug build reserved a slot for every one of them in that frame —
/// 38 KB per level, enough to overflow a 512 KiB task stack about a dozen frames deep.
/// Each payload is decoded in a generic helper instead, so only the one being decoded
/// is on the stack; encoding reads the payload out in a getter that returns before the
/// payload's own encoder runs. See `project/2026-09-26-debug-stack-depth.md`.
extension PenNode.Kind {
    /// Decodes the payload of a modelled node type.
    ///
    /// - Parameters:
    ///   - type: The node's `type`.
    ///   - decoder: The node object's decoder.
    /// - Returns: The kind, payload decoded.
    /// - Throws: Whatever the payload's decoder throws.
    static func decoding(_ type: PenNode.NodeType, from decoder: Decoder) throws -> Self {
        switch type {
        case .frame: try decoded(PenNode.FrameData.self, as: frame, from: decoder)
        case .text: try decoded(PenNode.TextData.self, as: text, from: decoder)
        case .rectangle: try decoded(PenNode.RectangleData.self, as: rectangle, from: decoder)
        case .ellipse: try decoded(PenNode.EllipseData.self, as: ellipse, from: decoder)
        case .path: try decoded(PenNode.PathData.self, as: path, from: decoder)
        case .group: try decoded(PenNode.GroupData.self, as: group, from: decoder)
        case .line: try decoded(PenNode.LineData.self, as: line, from: decoder)
        case .polygon: try decoded(PenNode.PolygonData.self, as: polygon, from: decoder)
        case .ref: try decoded(PenNode.RefData.self, as: ref, from: decoder)
        case .note: try decoded(PenNode.NoteData.self, as: note, from: decoder)
        case .prompt: try decoded(PenNode.PromptData.self, as: prompt, from: decoder)
        case .context: try decoded(PenNode.ContextData.self, as: context, from: decoder)
        case .icon: try decoded(PenNode.IconData.self, as: icon, from: decoder)
        case .script: try decoded(PenNode.ScriptData.self, as: script, from: decoder)
        case .browser: try decoded(PenNode.BrowserData.self, as: browser, from: decoder)
        case .connection: try decoded(PenNode.ConnectionData.self, as: connection, from: decoder)
        }
    }

    /// The payload of a modelled kind, ready to encode, or `nil` for an unknown one.
    var encodablePayload: (any Encodable)? {
        switch self {
        case let .frame(data): data
        case let .text(data): data
        case let .rectangle(data): data
        case let .ellipse(data): data
        case let .path(data): data
        case let .group(data): data
        case let .line(data): data
        case let .polygon(data): data
        case let .ref(data): data
        case let .note(data): data
        case let .prompt(data): data
        case let .context(data): data
        case let .icon(data): data
        case let .script(data): data
        case let .browser(data): data
        case let .connection(data): data
        case .unknown: nil
        }
    }

    /// Decodes one payload type and wraps it in its case.
    private static func decoded<Payload: Decodable>(
        _: Payload.Type,
        as wrap: (Payload) -> Self,
        from decoder: Decoder
    ) throws -> Self {
        try wrap(Payload(from: decoder))
    }
}
