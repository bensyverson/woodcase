//
//  PenNode+RefData.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    // MARK: Ref

    struct RefData: Friendly {
        public init(
            ref: String,
            descendants: [String: PenDescendantOverride]? = nil,
            rootOverrides: [String: AnyCodable]? = nil
        ) {
            self.ref = ref
            self.descendants = descendants
            self.rootOverrides = rootOverrides
        }

        public var ref: String
        public var descendants: [String: PenDescendantOverride]?
        /// Properties on the ref node that override the component root's
        /// kind-specific properties (width, height, fill, cornerRadius, etc.).
        public var rootOverrides: [String: AnyCodable]?

        // MARK: - Codable

        private enum CodingKeys: String, CodingKey {
            case ref, descendants
        }

        /// Keys that belong to PenNode/PenNodeCommon or RefData itself —
        /// everything else is a root override.
        ///
        /// The format writes a ref's root overrides as the ref node's own top-level
        /// keys, so this set is the whole of what a root override *cannot* be: write
        /// `opacity` here and it comes back as the instance's own opacity, not the
        /// component root's. A writer that would store one of these is refused rather
        /// than allowed to store an edit that reads back as something else.
        public static let reservedKeys: Set<String> = [
            "id", "type", "ref", "descendants",
            "name", "x", "y", "rotation", "opacity", "enabled",
            "flipX", "flipY", "reusable", "theme", "context",
            "layoutPosition", "metadata",
        ]

        public init(from decoder: Decoder) throws {
            let keyed = try decoder.container(keyedBy: CodingKeys.self)
            ref = try keyed.decode(String.self, forKey: .ref)
            descendants = try keyed.decodeIfPresent(
                [String: PenDescendantOverride].self, forKey: .descendants
            )

            // Capture any non-reserved keys as root overrides
            let dynamic = try decoder.container(keyedBy: DynamicCodingKey.self)
            var overrides: [String: AnyCodable] = [:]
            for key in dynamic.allKeys where !Self.reservedKeys.contains(key.stringValue) {
                overrides[key.stringValue] = try dynamic.decode(AnyCodable.self, forKey: key)
            }
            rootOverrides = overrides.isEmpty ? nil : overrides
        }

        public func encode(to encoder: Encoder) throws {
            var keyed = encoder.container(keyedBy: CodingKeys.self)
            try keyed.encode(ref, forKey: .ref)
            try keyed.encodeIfPresent(descendants, forKey: .descendants)

            // Encode root overrides as top-level keys
            if let overrides = rootOverrides {
                var dynamic = encoder.container(keyedBy: DynamicCodingKey.self)
                for (key, value) in overrides {
                    try dynamic.encode(value, forKey: DynamicCodingKey(stringValue: key))
                }
            }
        }
    }
}
