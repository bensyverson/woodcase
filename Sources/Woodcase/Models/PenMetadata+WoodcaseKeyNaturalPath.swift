//
//  PenMetadata+WoodcaseKeyNaturalPath.swift
//  Woodcase
//

import Foundation

/// The natural path a Woodcase key is read and written at, beside where it is stored.
///
/// A key that stands in for a property Pen's format lacks is written the way a caller
/// would guess it — `kind.strokeDash`, `common.locked` — and Woodcase stores it in
/// `metadata.woodcase`, which Pen keeps. ``NodePropertyCodec`` converts between the two, so
/// no reader or writer spells the storage path, and a write that does is refused
/// (``EditingError/storedAtNaturalPath(nodeID:path:naturalPath:)``; Ben's ruling of
/// 2026-10-20, `project/2026-10-20-natural-paths-for-woodcase-properties.md`).
///
/// This is the one table of that mapping: a key's ``naturalPath`` and the node types that
/// take it (``naturalPathTypes``). The codec's vocabulary
/// (``PropertyDiff/allKindKeys(_:)-(PenNode.NodeType)``, ``NodePropertyCodec/naturalCommonPaths``),
/// the schema and ``PenSchema/woodcaseFields(for:)`` all read it from here.
public extension PenMetadata.WoodcaseKey {
    /// The property path a caller reads and writes this key at, or `nil` for a key read and
    /// written at its storage path (``path``).
    ///
    /// The code-generation keys are written under a namespace of their own, `codegen.role`
    /// (leaf tRzkPS): only Woodcase reads them, and the namespace keeps them clear of any
    /// future Pen field. The note keys and a note's text style take `note.state`,
    /// `note.fontSize` (leaf DPY8DH) as aliases: their raw keys stay accepted
    /// (``storagePathRule``). A
    /// shadow's spread has none either: paths don't address array elements, so it is written
    /// as a `spread` field on its shadow in `kind.effects` (``writtenThrough``). A text's
    /// protected `textDecoration` mirrors the native `kind.underline` and
    /// `kind.strikethrough`, so it needs none.
    var naturalPath: String? {
        switch self {
        case .blendMode: "kind.blendMode"
        case .strokeDash: "kind.strokeDash"
        case .strokeDashOffset: "kind.strokeDashOffset"
        case .strokeMiterLimit: "kind.strokeMiterLimit"
        case .locked: "common.locked"
        case .defaultTextStyle: "kind.defaultTextStyle"
        case .spans: "kind.spans"
        case .props, .role, .states, .action, .scroll: "\(NodePropertyCodec.codegenPrefix)\(rawValue)"
        case .type, .state, .author, .leaf, .stage, .tint, .copiedFrom, .anchor, .replyTo, .requestedBy, .createdAt,
             .fontFamily, .fontSize, .fontWeight, .fontStyle, .letterSpacing, .lineHeight, .textAlign,
             .textAlignVertical, .scale:
            "\(NodePropertyCodec.notePrefix)\(rawValue)"
        default: nil
        }
    }

    /// The node types that take this key at its natural path; empty for a key with none.
    ///
    /// Every type takes a lock and the code-generation keys; the drawn shapes, text, icons and the two containers a blend
    /// (``PenNode/blendedTypes``); every type whose stroke follows one outline a dash, and
    /// every one of those but a line, which has no corners, a miter limit; a text its spans
    /// and the default-text-style mark; a note, a prompt and a context the note keys and a
    /// note's text style.
    var naturalPathTypes: Set<PenNode.NodeType> {
        switch self {
        case .blendMode: PenNode.blendedTypes
        case .strokeDash, .strokeDashOffset: Self.dashedTypes
        case .strokeMiterLimit: Self.dashedTypes.subtracting([.line])
        case .locked, .props, .role, .states, .action, .scroll: Set(PenNode.NodeType.allCases)
        case .defaultTextStyle, .spans: [.text]
        case .type, .state, .author, .leaf, .stage, .tint, .copiedFrom, .anchor, .replyTo, .requestedBy, .createdAt,
             .fontFamily, .fontSize, .fontWeight, .fontStyle, .letterSpacing, .lineHeight, .textAlign,
             .textAlignVertical, .scale:
            Self.noteTypes
        default: []
        }
    }

    /// The property a caller writes to set this key, when that is not its storage path: its
    /// ``naturalPath``, or `kind.effects` for a shadow's spread, which is a `spread` field on
    /// each shadow there (``NodePropertyCodec/presentedValue(at:of:)``).
    ///
    /// A write at the storage path of a key with one is refused, naming it
    /// (``NodePropertyCodec/checkNoStoragePaths(_:nodeID:)``).
    var writtenThrough: String? {
        naturalPath ?? (self == .shadowSpread ? NodePropertyCodec.effectsPath : nil)
    }

    /// Whether a caller may write a key at its storage path as well as at its natural path.
    enum StoragePathRule: Friendly {
        /// The storage path is refused, naming the natural path: one way in, so two spellings
        /// cannot drift (rule 3).
        case refused
        /// Both spellings are accepted and write the same key: the natural path is an alias.
        /// The note convention publishes the raw keys for tools without Woodcase
        /// (<doc:PenPostItConvention>), so its keys keep them.
        case accepted
    }

    /// Whether this key's storage path is refused as a way in, or accepted beside its alias.
    ///
    /// The note keys and a note's text style are ``StoragePathRule/accepted``: their
    /// `note.*` paths are aliases (leaf DPY8DH). Every other key with a natural path is
    /// ``StoragePathRule/refused``.
    var storagePathRule: StoragePathRule {
        switch group {
        case .note, .noteTextStyle: .accepted
        case .codegen, .text, .stroke, .editor, .effect, .compositing: .refused
        }
    }

    /// The path a caller reads and writes this key at: its ``naturalPath``, or its storage
    /// ``path`` for a key with none.
    var propertyPath: String {
        naturalPath ?? path
    }

    /// The key a natural path stands for.
    ///
    /// - Parameter naturalPath: A property path, such as `kind.blendMode`.
    /// - Returns: `nil` when the path is no key's ``naturalPath``.
    init?(naturalPath: String) {
        guard let key = Self.byNaturalPath[naturalPath] else { return nil }
        self = key
    }

    /// The key written through another property (``writtenThrough``) that a storage path, or
    /// a deep key below one, writes.
    ///
    /// - Parameter storagePath: A property path such as `common.metadata.woodcase.strokeDash`
    ///   or `common.metadata.woodcase.spans.text`.
    /// - Returns: The key, or `nil` when the path writes no key a caller writes elsewhere, or
    ///   one whose storage path stays accepted (``storagePathRule``).
    init?(storagePath: String) {
        let prefix = "\(NodePropertyCodec.metadataPath).\(PenMetadata.woodcaseNamespace)."
        guard storagePath.hasPrefix(prefix) else { return nil }
        let field = storagePath.dropFirst(prefix.count).prefix { $0 != "." }
        guard let key = Self(rawValue: String(field)), key.writtenThrough != nil, key.storagePathRule == .refused
        else { return nil }
        self = key
    }

    /// The key whose natural path ends in this field, as a `descendants` override or a node
    /// object spells it top-level (`strokeDash`, `locked`).
    ///
    /// - Parameter naturalField: A raw key.
    /// - Returns: `nil` when no natural path ends in it.
    init?(naturalField: String) {
        guard let key = Self.byNaturalField[naturalField] else { return nil }
        self = key
    }

    /// The field a natural path ends in: `strokeDash` for `kind.strokeDash`.
    var naturalField: String? {
        naturalPath.flatMap(NodePropertyCodec.fieldName(of:))
    }

    /// The three note types: a note, a prompt and a context.
    static let noteTypes: Set<PenNode.NodeType> = [.note, .prompt, .context]

    /// The types whose stroke follows one outline the dashes can flow around.
    private static let dashedTypes: Set<PenNode.NodeType> = [.frame, .rectangle, .ellipse, .polygon, .path, .line]

    /// Every key with a natural path, by that path.
    private static let byNaturalPath: [String: Self] = Dictionary(
        uniqueKeysWithValues: allCases.compactMap { key in key.naturalPath.map { ($0, key) } }
    )

    /// Every key with a natural path, by the field it ends in.
    private static let byNaturalField: [String: Self] = Dictionary(
        uniqueKeysWithValues: allCases.compactMap { key in key.naturalField.map { ($0, key) } }
    )
}
