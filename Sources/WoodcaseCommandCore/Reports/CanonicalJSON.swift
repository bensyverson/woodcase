//
//  CanonicalJSON.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// JSON printed in the form a `.pen` file is written in: sorted keys, two-space
/// indentation, `"key": value`.
///
/// A verb that prints a node, or a report wrapping one, prints it exactly as the file
/// stores it — so a fragment can be diffed against the file it came from, pasted back
/// into one, or handed to `-F` without a reformatting step. The bytes come from
/// ``Woodcase/PenParser/encodeForFile(_:)``, the same encoder
/// ``Woodcase/PenFileTransaction`` writes with, so there is one canonical form and not
/// two.
///
/// ```swift
/// print(try CanonicalJSON.text(node))
/// ```
enum CanonicalJSON {
    /// Encodes a value as canonical `.pen` JSON text.
    ///
    /// - Parameter value: Anything `Encodable` — a node, a report, a document.
    /// - Returns: The JSON, with no trailing newline, so `print` supplies the only one.
    /// - Throws: Whatever `JSONEncoder` throws for a value that cannot be encoded.
    static func text(_ value: some Encodable) throws -> String {
        let data = try PenParser.encodeForFile(value)
        var text = String(decoding: data, as: UTF8.self)
        if text.hasSuffix("\n") {
            text.removeLast()
        }
        return text
    }
}
