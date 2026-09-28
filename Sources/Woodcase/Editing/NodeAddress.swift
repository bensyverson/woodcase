//
//  NodeAddress.swift
//  Woodcase
//

import Foundation

/// A parsed node address: the string an agent or a CLI uses to name a node.
///
/// Four surface forms parse into two cases:
///
/// | Written           | Parses to                                |
/// | ----------------- | ---------------------------------------- |
/// | `ALu8G`           | `.path(["ALu8G"])` — a bare id or name    |
/// | `Header/Title`    | `.path(["Header", "Title"])`              |
/// | `@hero`           | `.tag(name: "hero", path: [])`            |
/// | `@hero/Title`     | `.tag(name: "hero", path: ["Title"])`     |
///
/// A tag composes with a path: it names where the walk starts, and the segments after
/// it are the same parent→child steps a path address takes — including the step into a
/// component instance. That is what lets one batch create an instance and dress its
/// descendants, rather than creating everything, reading the ids back and running a
/// second batch to override them.
///
/// Parsing is purely syntactic: a single segment could be an id *or* a name, and
/// only ``EditableDocument/resolve(_:tags:)-(String,_)`` can tell which. A segment
/// written `#ALu8G` forces an id match — it is also the marker
/// ``EditableDocument/namePath(of:)-(String)`` uses for a node that cannot be named
/// in a path, so every rendered path can be pasted straight back in.
///
/// Only an address that *begins* with `@` is a tag; `Card/@hero` is an ordinary
/// path whose last segment happens to start with `@`.
public enum NodeAddress: Friendly {
    /// One or more path segments, outermost first. A single segment is a bare id or name.
    case path([String])

    /// A batch tag, without its leading `@`, and the path to walk from the node it
    /// names. The path is empty for a bare `@hero`.
    case tag(name: String, path: [String])

    // MARK: - Syntax

    /// Separates path segments (`Dashboard/Header/Title`).
    public static let separator: Character = "/"

    /// Introduces a batch tag (`@hero`), at the head of an address only.
    public static let tagPrefix: Character = "@"

    /// Forces a segment to match a node id rather than a name (`#ALu8G`).
    public static let idPrefix: Character = "#"

    /// The word that means the document root wherever a parent — or a guard's scope —
    /// is expected, rather than a node.
    ///
    /// It is a *synonym*, not an address, and it is spelled the same on argv
    /// (`woodcase cp file Home document`), in a batch line (`"parent":"document"`) and
    /// in a guard (`{"node":"document"}`), so an agent learns it once. A root node
    /// genuinely named `document` is still addressable as `#<id>`, or through a longer
    /// path — the trade a literal always asks for.
    public static let documentRoot = "document"

    /// The path segment that addresses a node by id and never by name.
    ///
    /// This is the marker a name path uses for a node whose name cannot appear in a
    /// path — an unnamed node, or one whose name would itself parse as something else.
    ///
    /// - Parameter id: The node id to wrap.
    /// - Returns: The id behind ``idPrefix`` (`"#ALu8G"`).
    public static func marker(forID id: String) -> String {
        "\(idPrefix)\(id)"
    }

    /// The id a segment forces, or `nil` if the segment is an ordinary id-or-name.
    ///
    /// - Parameter segment: One path segment.
    /// - Returns: The id behind ``idPrefix``, or `nil` when the segment is not prefixed.
    public static func forcedID(in segment: String) -> String? {
        guard segment.first == idPrefix else { return nil }
        let id = String(segment.dropFirst())
        return id.isEmpty ? nil : id
    }

    // MARK: - Parsing

    /// Parses an address string.
    ///
    /// Returns `nil` for a malformed address: an empty string, an empty segment
    /// (`"A//B"`, `"/A"`, `"A/"`, `"@hero/"`), or a bare `@` or `#`.
    /// Nothing is trimmed — a name may legitimately contain spaces.
    ///
    /// - Parameter raw: The address as written.
    public init?(_ raw: String) {
        guard !raw.isEmpty else { return nil }

        let segments = raw
            .split(separator: Self.separator, omittingEmptySubsequences: false)
            .map(String.init)
        guard segments.allSatisfy({ !$0.isEmpty && $0 != String(Self.idPrefix) }) else { return nil }

        guard raw.first == Self.tagPrefix else {
            self = .path(segments)
            return
        }
        let name = String(segments[0].dropFirst())
        guard !name.isEmpty else { return nil }
        self = .tag(name: name, path: Array(segments.dropFirst()))
    }

    // MARK: - Shape

    /// The path segments, or `nil` for a tag.
    public var segments: [String]? {
        guard case let .path(segments) = self else { return nil }
        return segments
    }

    /// The tag name without its `@`, or `nil` for a path.
    public var tagName: String? {
        guard case let .tag(name, _) = self else { return nil }
        return name
    }

    /// The segments to walk from the tagged node, or `nil` for a path address.
    ///
    /// Empty for a bare `@hero`, `["Title"]` for `@hero/Title`.
    public var tagPath: [String]? {
        guard case let .tag(_, path) = self else { return nil }
        return path
    }

    /// Whether this is a single-segment path — a bare id or name.
    ///
    /// A bare segment is the only form resolved id-first: an exact id match wins
    /// outright, because ids are unique and a name collision is not the caller's fault.
    public var isBare: Bool {
        segments?.count == 1
    }
}

// MARK: - CustomStringConvertible

extension NodeAddress: CustomStringConvertible {
    /// The address as written, which parses back to an equal value.
    public var description: String {
        switch self {
        case let .path(segments): segments.joined(separator: String(Self.separator))
        case let .tag(name, path):
            ([String(Self.tagPrefix) + name] + path).joined(separator: String(Self.separator))
        }
    }
}

// MARK: - Codable

public extension NodeAddress {
    /// Decodes an address from its string form, failing on a malformed address.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError.dataCorrupted` when the string is not a valid address.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let address = NodeAddress(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "'\(raw)' is not a node address"
            )
        }
        self = address
    }

    /// Encodes the address as its string form.
    ///
    /// - Parameter encoder: The encoder to write to.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
