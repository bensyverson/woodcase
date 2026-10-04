//
//  ThreeWayResolver+Document.swift
//  Woodcase
//

import Foundation

/// The document-level keys, merged by the same rule as a node's properties.
extension ThreeWayResolver {
    /// Takes every document key only theirs changed, and reports one both changed
    /// differently, keeping ours'. The top-level order is merged with the child lists.
    mutating func resolveDocument() {
        let keys = theirsChanges.document.filter { $0 != .rootOrder }
        for key in keys.sorted(by: { String(describing: $0) < String(describing: $1) }) {
            guard oursChanges.document.contains(key) else {
                documentKeys.insert(key)
                continue
            }
            let oursValue = Self.value(of: key, in: ours)
            let theirsValue = Self.value(of: key, in: theirs)
            guard oursValue != theirsValue else { continue }
            report(Self.subject(of: key), .bothChanged, base: Self.value(of: key, in: base), ours: oursValue, theirs: theirsValue)
        }
    }

    /// What a conflict on a document key is about.
    private static func subject(of key: DocumentChangeKey) -> MergeConflict.Subject {
        switch key {
        case let .variable(name): .variable(name)
        case let .importAlias(alias): .importAlias(alias)
        case let .themeAxis(axis): .themeAxis(axis)
        case .fonts: .document(key: DocumentPropertyCodec.fontsKey)
        case .version: .document(key: DocumentPropertyCodec.versionKey)
        case .fileToken: .document(key: DocumentPropertyCodec.fileTokenKey)
        case let .extra(name): .document(key: DocumentPropertyCodec.extrasPrefix + name)
        case .rootOrder: .childOrder(parentID: nil)
        case let .declaredTable(table): .document(key: table.rawValue)
        }
    }

    /// A document key's value in the .pen file's JSON shape, or `nil` when the
    /// document does not hold it.
    private static func value(of key: DocumentChangeKey, in document: EditableDocument) -> AnyCodable? {
        switch key {
        case let .variable(name): encoded(document.variables?[name])
        case let .importAlias(alias): document.imports?[alias].map(AnyCodable.string)
        case let .themeAxis(axis): encoded(document.themes?[axis])
        case .fonts: encoded(document.fonts)
        case .version: .string(document.version)
        case .fileToken: document.fileToken.map(AnyCodable.string)
        case let .extra(name): document.extras[name]
        case .rootOrder: .array(document.rootOrder.map(AnyCodable.string))
        case .declaredTable(.variables): encoded(document.variables)
        case .declaredTable(.imports): encoded(document.imports)
        case .declaredTable(.themes): encoded(document.themes)
        }
    }

    /// A value encoded to its JSON shape, or `nil` for an absent one.
    private static func encoded(_ value: (some Encodable)?) -> AnyCodable? {
        guard let value else { return nil }
        return try? NodePropertyCodec.encode(value)
    }
}
