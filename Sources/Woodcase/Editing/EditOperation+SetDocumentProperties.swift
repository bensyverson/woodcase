//
//  EditOperation+SetDocumentProperties.swift
//  Woodcase
//

import Foundation

public extension EditOperation {
    /// Parameters for setting the document root's own properties by key.
    ///
    /// The root carries a few properties no node owns and no other operation writes:
    /// the `fonts` it declares, the format `version`, the editor's `fileToken`, and the
    /// root keys a file wrote that the model does not claim (``EditableDocument/extras``).
    /// Variables, imports and theme axes have operations of their own and are not keys
    /// here. Keys come from ``DocumentPropertyCodec``:
    ///
    /// | Key | Value | Null |
    /// | --- | --- | --- |
    /// | `fonts` | the `fonts` array, as the file writes it | removes the array |
    /// | `version` | a string | refused: every document has a version |
    /// | `fileToken` | a string | removes the token |
    /// | `extras.<key>` | any JSON value | removes the key |
    ///
    /// Like ``SetProperties`` the operation is atomic — every key and value is checked
    /// before anything is written — and its inverse names exactly the keys it wrote,
    /// each with the value it had.
    ///
    /// ```swift
    /// try document.apply(.setDocumentProperties(EditOperation.SetDocumentProperties(
    ///     properties: ["version": "2.20", "extras.futureKey": .null]
    /// )))
    /// ```
    struct SetDocumentProperties: Friendly {
        /// Creates a patch of the document root.
        ///
        /// - Parameter properties: The properties to set, keyed by document property key.
        public init(properties: [String: AnyCodable]) {
            self.properties = properties
        }

        /// The properties to set, keyed by document property key.
        public var properties: [String: AnyCodable]
    }
}
