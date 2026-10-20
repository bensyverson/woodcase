//
//  KiwiSchema+Friendly.swift
//  Woodcase
//

/// A schema is its definitions: the compiled lookup tables are derived from them, so
/// equality, hashing and coding use the definitions alone, and decoding recompiles them.
extension KiwiSchema: Codable, Hashable {
    private enum CodingKeys: String, CodingKey {
        case definitions
    }

    /// Decodes the definitions and compiles them, failing if they would not compile.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let definitions = try container.decode([KiwiDefinition].self, forKey: .definitions)
        do {
            try self.init(definitions: definitions)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .definitions, in: container,
                debugDescription: "The definitions do not compile: \(error)"
            )
        }
    }

    /// Encodes the definitions.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(definitions, forKey: .definitions)
    }

    /// Whether two schemas have the same definitions in the same order.
    public static func == (lhs: KiwiSchema, rhs: KiwiSchema) -> Bool {
        lhs.definitions == rhs.definitions
    }

    /// Hashes the definitions.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(definitions)
    }
}
