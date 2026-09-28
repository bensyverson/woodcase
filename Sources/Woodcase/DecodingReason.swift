//
//  DecodingReason.swift
//  Woodcase
//

import Foundation

/// Turns a `DecodingError` into the clause a reader can act on.
///
/// `DecodingError` holds everything worth knowing — the key, its path, the type the
/// decoder wanted — in fields, and then throws all of it away in
/// `localizedDescription`: *"The data couldn't be read because it isn't in the correct
/// format."* That sentence is the same for a truncated file, a misspelled key and a
/// number where a string belongs, so a reader who has only that has to open the file
/// and guess. This reads the fields back out:
///
/// ```swift
/// DecodingReason.describe(error)   // children[0].id should be a string
/// ```
///
/// Where the decoder was one of ours — ``PenNode`` refusing an unknown `type`, say —
/// its own `debugDescription` is already the sentence, so it is kept whole and only
/// given its path.
enum DecodingReason {
    /// A short reason for a decoding failure, naming the key and the type it wanted.
    ///
    /// - Parameters:
    ///   - error: The failure `JSONDecoder` threw. Anything that is not a
    ///     `DecodingError` keeps its own `localizedDescription`.
    ///   - root: What to call the value at the root of the coding path — "the
    ///     document" for a whole file, "the line" for one line of a batch.
    /// - Returns: One clause, with no trailing period, for a sentence to embed.
    static func describe(_ error: any Error, root: String = "the document") -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        switch decoding {
        case let .keyNotFound(key, context):
            return "\(path(of: context, or: root)) has no \"\(key.stringValue)\""
        case let .typeMismatch(type, context):
            return "\(path(of: context, or: root)) should be \(readable(type))"
        case let .valueNotFound(type, context):
            return "\(path(of: context, or: root)) is null, but \(readable(type)) is required"
        case let .dataCorrupted(context):
            let detail = sentence(context.debugDescription)
            guard !context.codingPath.isEmpty else { return detail }
            return "\(path(of: context, or: root)): \(detail)"
        @unknown default:
            return error.localizedDescription
        }
    }

    // MARK: - Private

    /// The dotted, indexed path a context points at — `children[0].id` — or `root`
    /// when it points at the whole value.
    private static func path(of context: DecodingError.Context, or root: String) -> String {
        guard !context.codingPath.isEmpty else { return root }
        return context.codingPath.reduce(into: "") { path, key in
            if let index = key.intValue {
                path += "[\(index)]"
            } else {
                path += path.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
    }

    /// What a JSON reader calls the type the decoder wanted.
    ///
    /// The Swift type is the wrong vocabulary for someone looking at a `.pen` file:
    /// `Double`, `Int` and `CGFloat` are all one thing in JSON, and
    /// `Dictionary<String, Any>` is an object. Anything with no JSON name — one of our
    /// own model types — is named as it is.
    private static func readable(_ type: Any.Type) -> String {
        if type is String.Type { return "a string" }
        if type is Bool.Type { return "a boolean" }
        if type is any BinaryInteger.Type || type is any BinaryFloatingPoint.Type {
            return "a number"
        }
        let name = String(describing: type)
        if name.hasPrefix("Dictionary") { return "an object" }
        if name.hasPrefix("Array") { return "an array" }
        return "a \(name)"
    }

    /// A `debugDescription` trimmed of the trailing period the surrounding sentence
    /// supplies for itself.
    private static func sentence(_ description: String) -> String {
        var trimmed = description.trimmingCharacters(in: .whitespaces)
        while trimmed.hasSuffix(".") {
            trimmed.removeLast()
        }
        return trimmed
    }
}
