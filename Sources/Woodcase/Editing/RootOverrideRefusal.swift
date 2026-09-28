//
//  RootOverrideRefusal.swift
//  Woodcase
//

import Foundation

/// Why a key cannot be written as one of an instance's root overrides.
///
/// The format writes root overrides as the `ref` node's own non-reserved top-level
/// keys, so the reserved ones are not merely discouraged: written there they would come
/// back meaning something else entirely — the instance's own opacity rather than the
/// component root's, or an override *named* `descendants`. Which of the three reasons
/// applies decides which command does work instead, so it travels with the refusal
/// rather than being re-derived from the key downstream.
public enum RootOverrideRefusal: String, Friendly, CaseIterable {
    /// `id` and `type`: what the node *is*, which no property write may change.
    case identity

    /// `ref` and `descendants`: the instance's own kind properties, written with
    /// `set kind.ref` and with an override addressed at a descendant.
    case refStructure

    /// A shared `common.*` property. On an instance these belong to the ref node
    /// itself — where it sits, whether it draws — and `set` writes them there.
    case instanceCommon

    /// How a message names what the key is, in place of a root override.
    public var explanation: String {
        switch self {
        case .identity: "what the node is"
        case .refStructure: "the instance's own structure"
        case .instanceCommon: "the instance's own property"
        }
    }

    /// The property path that writes this key on the instance node itself.
    ///
    /// - Parameter key: The raw .pen key the caller wrote.
    /// - Returns: The `set` path, or `nil` for a key no write may set.
    public func propertyPath(for key: String) -> String? {
        switch self {
        case .identity: nil
        case .refStructure: NodePropertyCodec.kindPrefix + NodePropertyCodec.fieldName(forRawKey: key)
        case .instanceCommon: NodePropertyCodec.commonPrefix + NodePropertyCodec.fieldName(forRawKey: key)
        }
    }

    /// The batch line that writes the key where it belongs.
    ///
    /// - Parameters:
    ///   - address: The instance's address.
    ///   - path: The property path from ``propertyPath(for:)``.
    /// - Returns: The remedy sentence.
    public func batchRemedy(address: String, path: String?) -> String {
        guard let path else {
            return #"`"id"` and `"type"` are what a node *is*; add the node you want instead"#
        }
        if self == .refStructure, path == "kind.descendants" {
            return #"write `{"op":"override","target":"\#(address)/<name>",…}` to override one "#
                + "node inside the instance"
        }
        return #"write it as `{"op":"set","target":"\#(address)","props":{"\#(path)":…}}`; "#
            + "it belongs to the instance, not to the component it shows"
    }

    /// The command that writes the key where it belongs.
    ///
    /// - Parameters:
    ///   - file: The .pen file a command names.
    ///   - address: The instance's address.
    ///   - path: The property path from ``propertyPath(for:)``.
    /// - Returns: The remedy sentence.
    public func commandRemedy(file: String, address: String, path: String?) -> String {
        guard let path else {
            return "`id` and `type` are what a node *is*; `woodcase add` makes the node you want"
        }
        if self == .refStructure, path == "kind.descendants" {
            return "run `woodcase override \(file) \(address)/<name> key=value` to override one "
                + "node inside the instance"
        }
        return "run `woodcase set \(file) \(address) \(path)=…` instead; it belongs to the "
            + "instance, not to the component it shows"
    }

    /// The reason a raw .pen key is refused, or `nil` when it is a root override.
    ///
    /// - Parameter key: The key as the ref node's JSON would spell it.
    /// - Returns: Which family reserved the key, or `nil` when nothing did.
    public static func refusing(_ key: String) -> RootOverrideRefusal? {
        guard PenNode.RefData.reservedKeys.contains(key) else { return nil }
        switch key {
        case "id", "type": return .identity
        case "ref", "descendants": return .refStructure
        default: return .instanceCommon
        }
    }
}
