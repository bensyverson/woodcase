//
//  PenExtras.swift
//  Woodcase
//

import Foundation

/// The keys of one .pen object that this build does not model, kept verbatim.
///
/// Pen adds keys faster than Woodcase models them. A file decode keeps every key the
/// typed model does not claim — on the document root, on a node, on each fill,
/// stroke paint and effect, and on the objects nested in them — here, and writes it back unchanged, so a newer Pen's data
/// survives a Woodcase edit. See <doc:PenEngine> for where extras are captured.
///
/// Extras are **write-through only**: layout, rendering and code generation never read
/// them, and no editing path writes them. They are captured only when a *file* is
/// decoded (``PenDecodingMode/file``); an agent's input is decoded in
/// ``PenDecodingMode/authoring``, where an unclaimed key is refused rather than kept,
/// so a typo such as `"fil"` is caught instead of carried along.
///
/// By construction an extra never shadows a modeled key: a key the model claims is
/// decoded into its typed property and never reaches here. When a later build models a
/// key, it simply stops being an extra.
///
/// ```swift
/// let node = try JSONDecoder().decode(PenNode.self, from: data)
/// node.extras["layoutIncludeStroke"]   // .bool(true), if the file wrote it
/// ```
public struct PenExtras: Friendly {
    /// Creates a set of extras.
    ///
    /// - Parameter values: The unclaimed keys and their values, as the file wrote them.
    public init(_ values: [String: AnyCodable] = [:]) {
        self.values = values
    }

    /// The unclaimed keys and their values, as the file wrote them.
    public var values: [String: AnyCodable]

    /// Whether there are no extras.
    public var isEmpty: Bool {
        values.isEmpty
    }

    /// The unclaimed keys, sorted.
    public var keys: [String] {
        values.keys.sorted()
    }

    /// The value kept under `key`, or `nil` if the object carried no such key.
    public subscript(key: String) -> AnyCodable? {
        values[key]
    }
}

// MARK: - Codable

public extension PenExtras {
    /// Decodes extras standing alone, as a plain JSON object.
    ///
    /// This is the form a CRDT register carries them in. Extras *inside* a .pen object
    /// are captured by `capture(from:claiming:describing:)` instead, because there
    /// they share the object with the keys the model claims.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` if the value is not a JSON object.
    init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode([String: AnyCodable].self))
    }

    /// Encodes the extras standing alone, as a plain JSON object.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}
