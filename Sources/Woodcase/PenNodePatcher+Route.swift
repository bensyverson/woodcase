//
//  PenNodePatcher+Route.swift
//  Woodcase
//

import Foundation

extension PenNodePatcher {
    /// How a patch reaches the node it is merged onto.
    ///
    /// Both routes are the same JSON merge; they differ only in whether the merged object
    /// is ever written out. `PenNodePatcherEquivalenceTests` expands every fixture both
    /// ways and requires identical documents.
    enum Route: Friendly {
        /// ``PenNodeOverlay``, and the JSON round trip wherever the overlay declines — for
        /// a value it cannot read back, and for every refused patch, whose `DecodingError`
        /// the round trip words the way the writers that report it expect. The default.
        case overlay

        /// ``PenNodeOverlay`` alone: a patch it declines is refused. For the equivalence
        /// tests, so a case the overlay cannot answer shows up instead of falling back.
        case overlayOnly

        /// Encode the node, lay the patch over its JSON object, decode the result — four
        /// coder passes. The reference the overlay is held to.
        case jsonRoundTrip
    }

    /// The route patches take in the current task: ``Route/overlay`` unless a test says
    /// otherwise.
    @TaskLocal static var route: Route = .overlay

    /// A value stored as ``AnyCodable`` — slot content, a replacement node — decoded as
    /// `type`, by the current ``route``.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - value: The stored value.
    /// - Returns: The decoded value, or `nil` when it does not decode as `type`.
    static func decoded<T: Decodable>(_ type: T.Type, from value: AnyCodable) -> T? {
        switch route {
        case .overlay: (try? AnyCodableDecoder.decode(type, from: value)) ?? jsonDecoded(type, from: value)
        case .overlayOnly: try? AnyCodableDecoder.decode(type, from: value)
        case .jsonRoundTrip: jsonDecoded(type, from: value)
        }
    }

    /// The same decode through JSON text.
    private static func jsonDecoded<T: Decodable>(_ type: T.Type, from value: AnyCodable) -> T? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
