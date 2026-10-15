//
//  PenMetadata+Woodcase.swift
//  Woodcase
//

import Foundation

/// Reading and writing the keys Woodcase owns, under `metadata.woodcase`.
///
/// This is the one way Woodcase code reaches its own metadata. A read takes the
/// namespaced key, and falls back to the key's old spelling (``WoodcaseKey/oldSpelling``)
/// — files written before the namespace still work. A write stores only the namespaced
/// key and removes the old spelling, so a file converts as it is edited.
///
/// ```swift
/// var metadata = node.common.metadata ?? PenMetadata(type: nil)
/// metadata[woodcase: .tint]                      // .string("#A5D6A7"), either spelling
/// metadata[woodcase: .state] = .string("resolved")
/// // {"woodcase": {"state": "resolved"}} — and a bare "state" is gone
/// ```
public extension PenMetadata {
    /// The value Woodcase keeps under a key, from either spelling, the namespace winning.
    ///
    /// Setting a value writes `metadata.woodcase.<key>` and removes the key's old
    /// spelling; setting `nil` removes both, and a namespace left empty with them. An old
    /// `type: "postit"` becomes ``woodcaseType``, and metadata left with keys but no
    /// `type` takes it, since Pen's schema requires one.
    ///
    /// - Parameter key: The key.
    /// - Returns: The namespaced value, else the old spelling's, else `nil`.
    subscript(woodcase key: WoodcaseKey) -> AnyCodable? {
        get {
            namespace[key.rawValue] ?? oldStyleValue(of: key)
        }
        set {
            removeOldSpelling(of: key)
            var keys = namespace
            keys[key.rawValue] = newValue
            namespace = keys
            if !extensions.isEmpty { requireType() }
        }
    }

    /// The keys this metadata holds under their old spelling, in ``WoodcaseKey`` order.
    ///
    /// A key also written in the namespace still counts: its old spelling is dead
    /// weight a migration removes.
    var oldStyleWoodcaseKeys: [WoodcaseKey] {
        WoodcaseKey.allCases.filter { oldStyleValue(of: $0) != nil }
    }

    /// This metadata with every old spelling moved under `metadata.woodcase`.
    ///
    /// Where both spellings are present the namespaced value is kept and the old one
    /// dropped — the namespace already won every read. Keys Woodcase no longer owns,
    /// such as a post-it's legacy `kind`, are left as written.
    ///
    /// - Returns: The migrated metadata; equal to `self` when there was nothing to move.
    func migratingOldStyleWoodcaseKeys() -> PenMetadata {
        var migrated = self
        // The type goes last: while it stands, it is what makes the bare note keys read.
        for key in oldStyleWoodcaseKeys.sorted(by: { ($0 == .type ? 1 : 0) < ($1 == .type ? 1 : 0) }) {
            migrated[woodcase: key] = migrated[woodcase: key]
        }
        return migrated
    }

    // MARK: - Internal

    /// Gives metadata with no `type` the one Woodcase writes; any other type is kept.
    internal mutating func requireType() {
        if type == nil { type = Self.woodcaseType }
    }

    /// The metadata as Woodcase writes it: typed (``requireType()``), or `nil` when it
    /// holds nothing but Woodcase's own type — that type only makes other keys valid, so
    /// alone it is no metadata at all. Applied wherever Woodcase authors metadata.
    internal func typedForWriting() -> PenMetadata? {
        guard !extensions.isEmpty || (type != nil && type != Self.woodcaseType) else { return nil }
        var typed = self
        typed.requireType()
        return typed
    }

    /// The `type` an old-style post-it's metadata declares.
    internal static let oldPostItType = "postit"

    /// The metadata as one JSON object, `type` included.
    internal var object: [String: AnyCodable] {
        var object = extensions
        if let type { object["type"] = .string(type) }
        return object
    }

    /// Metadata read from one JSON object, as a file's would be.
    ///
    /// - Parameter object: The object; a `type` that is not a string stays an extension.
    internal init(object: [String: AnyCodable]) {
        var extensions = object
        var type: String?
        if case let .string(text)? = object["type"] {
            type = text
            extensions.removeValue(forKey: "type")
        }
        self.init(type: type, extensions: extensions)
    }

    // MARK: - Private

    /// The `woodcase` object's keys; setting an empty one removes the object.
    private var namespace: [String: AnyCodable] {
        get {
            guard case let .dictionary(keys)? = extensions[Self.woodcaseNamespace] else { return [:] }
            return keys
        }
        set {
            if newValue.isEmpty {
                extensions.removeValue(forKey: Self.woodcaseNamespace)
            } else {
                extensions[Self.woodcaseNamespace] = .dictionary(newValue)
            }
        }
    }

    /// Whether a note key's bare old spelling is Woodcase's here.
    private var readsBareNoteKeys: Bool {
        type == Self.oldPostItType || namespace[WoodcaseKey.type.rawValue] != nil
    }

    /// The value a key holds under `metadata.woodcase`, ignoring its old spelling.
    internal func namespacedValue(of key: WoodcaseKey) -> AnyCodable? {
        namespace[key.rawValue]
    }

    /// The key an old spelling stands for here, or `nil` when the spelling is not
    /// Woodcase's on this metadata.
    ///
    /// `type` is never one: `metadata.type` is the schema's own key, and only its value
    /// `postit` is an old spelling, which ``oldStyleValue(of:)`` reads.
    internal func woodcaseKey(forOldSpelling spelling: String) -> WoodcaseKey? {
        WoodcaseKey.allCases.first { key in
            guard key != .type, key.oldSpelling == spelling else { return false }
            return key.group == .codegen || readsBareNoteKeys
        }
    }

    /// The value a key's old spelling holds, when that spelling is Woodcase's here.
    internal func oldStyleValue(of key: WoodcaseKey) -> AnyCodable? {
        guard let spelling = key.oldSpelling else { return nil }
        switch key.group {
        case .codegen:
            return extensions[spelling]
        case .text, .stroke, .editor:
            return nil
        case .note, .noteTextStyle:
            guard readsBareNoteKeys else { return nil }
            if key == .type { return type == Self.oldPostItType ? .string(Self.oldPostItType) : nil }
            return extensions[spelling]
        }
    }

    /// Removes a key's old spelling, when that spelling is Woodcase's here.
    private mutating func removeOldSpelling(of key: WoodcaseKey) {
        guard oldStyleValue(of: key) != nil, let spelling = key.oldSpelling else { return }
        if key == .type {
            type = Self.woodcaseType
        } else {
            extensions.removeValue(forKey: spelling)
        }
    }
}
