//
//  EditableDocument+DocumentProperties.swift
//  Woodcase
//

import Foundation

/// Applying, checking and inverting ``EditOperation/setDocumentProperties(_:)``.
extension EditableDocument {
    /// Checks a document patch, changing nothing.
    ///
    /// - Parameter op: The patch.
    /// - Throws: The ``EditingError`` its first bad key or value raises.
    func validateSetDocumentProperties(_ op: EditOperation.SetDocumentProperties) throws {
        _ = try DocumentPropertyCodec.patched(op.properties, in: self)
    }

    /// Applies a document patch: every key is resolved on a copy of the root first, so
    /// one bad entry leaves the document untouched.
    ///
    /// The declared fonts are what a settled read measures text in, so writing them
    /// drops every cached layout.
    ///
    /// - Parameter op: The patch.
    /// - Throws: The ``EditingError`` its first bad key or value raises.
    func applySetDocumentProperties(_ op: EditOperation.SetDocumentProperties) throws {
        let patched = try DocumentPropertyCodec.patched(op.properties, in: self)
        if patched.fonts != fonts {
            fonts = patched.fonts
            _layoutCache?.invalidateAll()
        }
        if patched.version != version { version = patched.version }
        if patched.fileToken != fileToken { fileToken = patched.fileToken }
        if patched.extras != extras { extras = patched.extras }
    }

    /// The inverse of a document patch: the same keys, each with the value it has now.
    ///
    /// - Parameter op: The patch about to be applied.
    /// - Returns: The patch that restores every key it names.
    /// - Throws: ``EditingError/unknownDocumentProperty(key:)`` for a key outside the
    ///   vocabulary, so an undo stack is never handed an inverse it cannot replay.
    func prepareInverseSetDocumentProperties(_ op: EditOperation.SetDocumentProperties) throws -> EditOperation {
        let root = DocumentPropertyCodec.root(of: self)
        var prior: [String: AnyCodable] = [:]
        for key in op.properties.keys {
            prior[key] = try DocumentPropertyCodec.value(at: key, of: root)
        }
        return .setDocumentProperties(EditOperation.SetDocumentProperties(properties: prior))
    }
}
