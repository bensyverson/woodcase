//
//  DocumentLinter+PenDropsOverride.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/penDropsOverride`` check.
///
/// An instance stores its overrides of Woodcase-owned keys — a dash, a miter limit, a blend,
/// a lock — in metadata: a descendant's in its `descendants` override, the instance root's
/// on the `ref` node (rule 6; <doc:PenMetadataNamespace>, *Natural paths*). Pen drops both
/// when it saves the file (pen CLI 0.3.11, 2026-10-20). Ben accepts that, since transfers run
/// Pen to Penumbra, so this is a notice: one per instance, naming what a save through Pen
/// would lose, with nothing to fix.
extension DocumentLinter {
    /// An instance, as the file stores it, that overrides Woodcase-owned keys.
    ///
    /// A row inside another instance is skipped: what it stores is its own component's,
    /// reported on that component's instance.
    ///
    /// - Parameters:
    ///   - row: The row, for the finding's id and path.
    ///   - context: The lint context, for the node as authored.
    /// - Returns: Zero or one finding, naming each key by its natural path, with the
    ///   descendant it is overridden on.
    static func penDropsOverride(_ row: TreeRow, in context: Context) -> [LintFinding] {
        guard !row.id.contains(NodeAddress.separator),
              let node = context.authored(row), case let .ref(data) = node.kind
        else { return [] }
        var named = naturalPaths(in: node.common.metadata?.extensions[PenMetadata.woodcaseNamespace])
        for key in (data.descendants ?? [:]).keys.sorted() {
            guard case let .dictionary(metadata)? = data.descendants?[key]?.properties["metadata"] else { continue }
            let descendant = descendantName(key, in: context.document)
            named += naturalPaths(in: metadata[PenMetadata.woodcaseNamespace]).map { "\(descendant) \($0)" }
        }
        guard !named.isEmpty else { return [] }
        return [finding(
            .penDropsOverride, row,
            "overrides \(named.joined(separator: ", ")), which Woodcase keeps in metadata and Pen drops when it "
                + "saves the file. It draws as written here; nothing to fix."
        )]
    }

    /// The natural paths of the Woodcase-owned keys a `woodcase` object holds, sorted.
    private static func naturalPaths(in namespace: AnyCodable?) -> [String] {
        guard case let .dictionary(keys)? = namespace else { return [] }
        return keys.keys.compactMap { PenMetadata.WoodcaseKey(rawValue: $0)?.naturalPath }.sorted()
    }

    /// A `descendants` key named as Layers names it: the node's name, or the key.
    private static func descendantName(_ key: String, in document: EditableDocument) -> String {
        let id = key.split(separator: "/").last.map(String.init) ?? key
        return document.node(id: id)?.common.name ?? key
    }
}
