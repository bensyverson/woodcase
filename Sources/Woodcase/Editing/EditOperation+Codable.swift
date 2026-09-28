//
//  EditOperation+Codable.swift
//  Woodcase
//

import Foundation

/// A standalone wrapper that encodes/decodes `PenNode.Kind` as `{"type": "frame", ...data}`.
///
/// `PenNode.Kind`'s own `Codable` throws when used directly (it relies on `PenNode`'s
/// custom `init(from:)`). This envelope provides independent serialization for use in
/// ``EditOperation/UpdateKind`` and ``CRDTOperation`` payloads.
struct KindEnvelope: Friendly {
    var kind: PenNode.Kind

    private enum CodingKeys: String, CodingKey {
        case type
    }

    /// Keys that belong to PenNodeCommon or PenNode itself, not type-specific data.
    private static let reservedKeys: Set<String> = [
        "id", "type", "name", "x", "y", "rotation", "opacity", "enabled",
        "flipX", "flipY", "reusable", "theme", "context", "layoutPosition", "metadata",
    ]

    init(kind: PenNode.Kind) {
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)

        if let nodeType = PenNode.NodeType(rawValue: typeString) {
            switch nodeType {
            case .frame:
                kind = try .frame(PenNode.FrameData(from: decoder))
            case .text:
                kind = try .text(PenNode.TextData(from: decoder))
            case .rectangle:
                kind = try .rectangle(PenNode.RectangleData(from: decoder))
            case .ellipse:
                kind = try .ellipse(PenNode.EllipseData(from: decoder))
            case .path:
                kind = try .path(PenNode.PathData(from: decoder))
            case .group:
                kind = try .group(PenNode.GroupData(from: decoder))
            case .line:
                kind = try .line(PenNode.LineData(from: decoder))
            case .polygon:
                kind = try .polygon(PenNode.PolygonData(from: decoder))
            case .ref:
                kind = try .ref(PenNode.RefData(from: decoder))
            case .note:
                kind = try .note(PenNode.NoteData(from: decoder))
            case .prompt:
                kind = try .prompt(PenNode.PromptData(from: decoder))
            case .context:
                kind = try .context(PenNode.ContextData(from: decoder))
            case .icon:
                kind = try .icon(PenNode.IconData(from: decoder))
            case .script:
                kind = try .script(PenNode.ScriptData(from: decoder))
            case .browser:
                kind = try .browser(PenNode.BrowserData(from: decoder))
            case .connection:
                kind = try .connection(PenNode.ConnectionData(from: decoder))
            }
        } else {
            let dynContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
            var props: [String: AnyCodable] = [:]
            for key in dynContainer.allKeys where !Self.reservedKeys.contains(key.stringValue) {
                props[key.stringValue] = try dynContainer.decode(AnyCodable.self, forKey: key)
            }
            kind = .unknown(typeName: typeString, properties: props)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch kind {
        case let .frame(data):
            try container.encode(PenNode.NodeType.frame, forKey: .type)
            try data.encode(to: encoder)
        case let .text(data):
            try container.encode(PenNode.NodeType.text, forKey: .type)
            try data.encode(to: encoder)
        case let .rectangle(data):
            try container.encode(PenNode.NodeType.rectangle, forKey: .type)
            try data.encode(to: encoder)
        case let .ellipse(data):
            try container.encode(PenNode.NodeType.ellipse, forKey: .type)
            try data.encode(to: encoder)
        case let .path(data):
            try container.encode(PenNode.NodeType.path, forKey: .type)
            try data.encode(to: encoder)
        case let .group(data):
            try container.encode(PenNode.NodeType.group, forKey: .type)
            try data.encode(to: encoder)
        case let .line(data):
            try container.encode(PenNode.NodeType.line, forKey: .type)
            try data.encode(to: encoder)
        case let .polygon(data):
            try container.encode(PenNode.NodeType.polygon, forKey: .type)
            try data.encode(to: encoder)
        case let .ref(data):
            try container.encode(PenNode.NodeType.ref, forKey: .type)
            try data.encode(to: encoder)
        case let .note(data):
            try container.encode(PenNode.NodeType.note, forKey: .type)
            try data.encode(to: encoder)
        case let .prompt(data):
            try container.encode(PenNode.NodeType.prompt, forKey: .type)
            try data.encode(to: encoder)
        case let .context(data):
            try container.encode(PenNode.NodeType.context, forKey: .type)
            try data.encode(to: encoder)
        case let .icon(data):
            try container.encode(PenNode.NodeType.icon, forKey: .type)
            try data.encode(to: encoder)
        case let .script(data):
            try container.encode(PenNode.NodeType.script, forKey: .type)
            try data.encode(to: encoder)
        case let .browser(data):
            try container.encode(PenNode.NodeType.browser, forKey: .type)
            try data.encode(to: encoder)
        case let .connection(data):
            try container.encode(PenNode.NodeType.connection, forKey: .type)
            try data.encode(to: encoder)
        case let .unknown(typeName, properties):
            try container.encode(typeName, forKey: .type)
            var dynContainer = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in properties {
                try dynContainer.encode(value, forKey: DynamicCodingKey(stringValue: key))
            }
        }
    }
}

// MARK: - EditOperation.DeleteNode custom Codable

public extension EditOperation.DeleteNode {
    private enum CodingKeys: String, CodingKey {
        case nodeID
        case instances
    }

    /// Decodes a delete, defaulting ``EditOperation/DeleteNode/instances`` to
    /// ``EditOperation/DeleteNode/Instances/refuse`` when the key is absent.
    ///
    /// The safe policy is the default, so a caller writing operations by hand — an
    /// agent composing a batch file, say — spells out `instances` only when it wants
    /// the consequential one.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(String.self, forKey: .nodeID)
        instances = try container.decodeIfPresent(Instances.self, forKey: .instances) ?? .refuse
    }

    /// Encodes the node id and the instances policy.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nodeID, forKey: .nodeID)
        try container.encode(instances, forKey: .instances)
    }
}

// MARK: - EditOperation.UpdateKind custom Codable

public extension EditOperation.UpdateKind {
    private enum CodingKeys: String, CodingKey {
        case nodeID
        case kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(String.self, forKey: .nodeID)
        let envelope = try container.decode(KindEnvelope.self, forKey: .kind)
        kind = envelope.kind
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nodeID, forKey: .nodeID)
        try container.encode(KindEnvelope(kind: kind), forKey: .kind)
    }
}
