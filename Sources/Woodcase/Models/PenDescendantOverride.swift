//
//  PenDescendantOverride.swift
//  Woodcase
//
//  Created by Claude on 2026-03-22.
//

import Foundation

/// A descendant override applied by a `ref` node to a descendant of its component.
///
/// In the .pen format, `ref` nodes can override properties on descendants of the component
/// they reference. The `descendants` map keys use slash notation for nested paths
/// (e.g. `"card/header/label"`).
///
/// Overrides come in two forms:
/// - **Property patch:** Merges specific properties into the descendant node.
/// - **Object replacement:** Replaces the entire descendant node (identified by presence of `type`).
///
/// We store the raw JSON properties at parse time. Resolution happens during ref expansion (Step 6).
public struct PenDescendantOverride: Friendly {
    /// The raw override properties from the .pen JSON.
    public var properties: [String: AnyCodable]

    /// Whether this override replaces the entire descendant node.
    ///
    /// Object replacements include a `type` field, distinguishing them from property patches.
    public init(properties: [String: AnyCodable]) {
        self.properties = properties
    }

    /// The key whose presence turns a property patch into a whole-node replacement.
    public static let typeKey = "type"

    /// Whether this override replaces the entire descendant node.
    public var isObjectReplacement: Bool {
        properties[Self.typeKey] != nil
    }
}

// MARK: - Written content

public extension PenDescendantOverride {
    /// Whether the override writes nodes of its own — a `children` list, or a whole
    /// replacement node — rather than only patching properties.
    ///
    /// Those nodes are the writer's own slot content, which no other key of the same
    /// instance reaches.
    var writesChildren: Bool {
        isObjectReplacement || properties[PenNodePatcher.childrenKey] != nil
    }
}

// MARK: - Codable

public extension PenDescendantOverride {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        properties = try container.decode([String: AnyCodable].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(properties)
    }
}
