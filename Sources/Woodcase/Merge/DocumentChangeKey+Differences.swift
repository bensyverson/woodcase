//
//  DocumentChangeKey+Differences.swift
//  Woodcase
//

import Foundation

extension DocumentChangeKey {
    /// The document-level members that differ between two documents.
    ///
    /// - Parameters:
    ///   - from: The source document.
    ///   - to: The target document.
    /// - Returns: One key per differing variable, import alias, theme axis and root
    ///   extra, plus the whole-value members and the root order when they differ.
    static func differences(from: EditableDocument, to: EditableDocument) -> Set<DocumentChangeKey> {
        var keys: Set<DocumentChangeKey> = []
        keys.formUnion(entries(from.variables, to.variables).map(DocumentChangeKey.variable))
        keys.formUnion(entries(from.imports, to.imports).map(DocumentChangeKey.importAlias))
        keys.formUnion(entries(from.themes, to.themes).map(DocumentChangeKey.themeAxis))
        keys.formUnion(entries(from.extras.values, to.extras.values).map(DocumentChangeKey.extra))
        if (from.variables == nil) != (to.variables == nil) { keys.insert(.declaredTable(.variables)) }
        if (from.imports == nil) != (to.imports == nil) { keys.insert(.declaredTable(.imports)) }
        if (from.themes == nil) != (to.themes == nil) { keys.insert(.declaredTable(.themes)) }
        if from.fonts != to.fonts { keys.insert(.fonts) }
        if from.version != to.version { keys.insert(.version) }
        if from.fileToken != to.fileToken { keys.insert(.fileToken) }
        if from.rootOrder != to.rootOrder { keys.insert(.rootOrder) }
        return keys
    }

    /// The keys of two tables whose entries differ, an absent table holding none.
    private static func entries<Value: Equatable>(_ old: [String: Value]?, _ new: [String: Value]?) -> Set<String> {
        let old = old ?? [:]
        let new = new ?? [:]
        return Set(old.keys).union(new.keys).filter { old[$0] != new[$0] }
    }
}
