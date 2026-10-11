//
//  DocumentLinter+MetadataOldStyle.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/metadataOldStyle`` check.
///
/// Woodcase keeps its metadata under `metadata.woodcase` and still reads the spellings
/// from before (``PenMetadata/WoodcaseKey/oldSpelling``), so nothing is wrong with a
/// node that holds them. The notice names them so a reader knows the file predates the
/// namespace, and says which command moves them in. See <doc:PenMetadataNamespace>.
extension DocumentLinter {
    /// A node, as the file stores it, whose metadata holds old-style Woodcase keys.
    ///
    /// A row inside an instance is skipped: its metadata is the component's, reported
    /// once on the component's own node.
    ///
    /// - Parameters:
    ///   - row: The row, for the finding's id and path.
    ///   - context: The lint context, for the node as authored.
    /// - Returns: Zero or one finding, naming every old spelling the node holds.
    static func metadataOldStyle(_ row: TreeRow, in context: Context) -> [LintFinding] {
        guard !row.id.contains(NodeAddress.separator),
              let metadata = context.authored(row)?.common.metadata
        else { return [] }
        let spellings = metadata.oldStyleWoodcaseKeys.compactMap(\.oldSpelling)
        guard !spellings.isEmpty else { return [] }
        let named = spellings.map { "`\($0)`" }.joined(separator: ", ")
        return [finding(
            .metadataOldStyle, row,
            "keeps Woodcase metadata under its old spelling (\(named)), which is still read. Run "
                + "`woodcase migrate <file>` to move it under `metadata.\(PenMetadata.woodcaseNamespace)`."
        )]
    }
}
