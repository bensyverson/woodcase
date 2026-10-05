//
//  PenAssetReferences.swift
//  Woodcase
//

import Foundation

/// The files a document points at — image fills and declared fonts — found and rewritten
/// wherever the document writes them.
///
/// An image paint is any object with `type: "image"` and a `url`, as Pen reads one: in a
/// node's `fill` or `stroke`, in `children`, in a `ref`'s `descendants` override bags. A
/// declared font is an entry of the root `fonts` array (``PenDocument/fonts``). Walking
/// the document's JSON rather than its typed model reaches all of them with one rule,
/// including the paints the model keeps as untyped override values.
///
/// ```swift
/// let moved = try PenAssetReferences.rewrite(document) { kind, reference in
///     kind == .image && reference == "hero.png" ? "./images/hero.png" : nil
/// }
/// ```
enum PenAssetReferences {
    /// Which kind of file a reference points at.
    typealias Kind = PenBundle.AssetKind

    /// One reference, as the document writes it.
    struct Reference: Friendly {
        /// What it points at.
        var kind: Kind
        /// The `url` string, exactly as written.
        var value: String
    }

    /// Every reference in a document, in document order, each once.
    ///
    /// - Parameter document: The document.
    /// - Returns: The references.
    /// - Throws: Whatever encoding the document throws.
    static func collect(from document: PenDocument) throws -> [Reference] {
        var found: [Reference] = []
        _ = try rewrite(document) { kind, value in
            let reference = Reference(kind: kind, value: value)
            if !found.contains(reference) { found.append(reference) }
            return nil
        }
        return found
    }

    /// The document with every reference passed through `transform`.
    ///
    /// - Parameters:
    ///   - document: The document.
    ///   - transform: Given a reference's kind and value, the value to write instead, or
    ///     `nil` to leave it as it is.
    /// - Returns: The rewritten document — `document` itself when nothing changed.
    /// - Throws: Whatever encoding or parsing the document throws.
    static func rewrite(
        _ document: PenDocument,
        _ transform: (Kind, String) throws -> String?
    ) throws -> PenDocument {
        let data = try PenParser.encodeForFile(document)
        let tree = try JSONDecoder().decode(AnyCodable.self, from: data)
        guard case var .dictionary(root) = tree else { return document }

        var changed = false
        if case let .array(fonts)? = root[fontsKey] {
            root[fontsKey] = try .array(fonts.map { try rewritten($0, key: urlKey, kind: .font, &changed, transform) })
        }
        for key in root.keys.sorted() where key != fontsKey {
            root[key] = try images(in: root[key] ?? .null, &changed, transform)
        }
        guard changed else { return document }
        return try PenParser.parse(JSONEncoder().encode(AnyCodable.dictionary(root)))
    }

    // MARK: - Private

    /// The root key declared fonts live under.
    private static let fontsKey = "fonts"

    /// The key a reference's address lives under.
    private static let urlKey = "url"

    /// Rewrites every image paint inside `value`, at any depth.
    ///
    /// A work list rather than recursion would keep a deep tree off the stack, but the
    /// rebuild needs each container after its children; the depth here is the JSON's,
    /// which ``PenParser`` already decoded recursively to get this far.
    private static func images(
        in value: AnyCodable,
        _ changed: inout Bool,
        _ transform: (Kind, String) throws -> String?
    ) throws -> AnyCodable {
        switch value {
        case let .array(items):
            return try .array(items.map { try images(in: $0, &changed, transform) })
        case var .dictionary(object):
            if object["type"] == .string(Kind.image.rawValue) {
                return try rewritten(.dictionary(object), key: urlKey, kind: .image, &changed, transform)
            }
            for key in object.keys.sorted() {
                object[key] = try images(in: object[key] ?? .null, &changed, transform)
            }
            return .dictionary(object)
        default:
            return value
        }
    }

    /// One object with its `key` string passed through `transform`.
    private static func rewritten(
        _ value: AnyCodable,
        key: String,
        kind: Kind,
        _ changed: inout Bool,
        _ transform: (Kind, String) throws -> String?
    ) throws -> AnyCodable {
        guard case var .dictionary(object) = value,
              case let .string(current)? = object[key],
              let replacement = try transform(kind, current),
              replacement != current
        else { return value }
        object[key] = .string(replacement)
        changed = true
        return .dictionary(object)
    }
}
