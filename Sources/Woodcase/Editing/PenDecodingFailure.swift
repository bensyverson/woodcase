//
//  PenDecodingFailure.swift
//  Woodcase
//

import Foundation

/// Turns the `DecodingError` behind a refused write into a clause a caller can act on.
///
/// A *scalar* property is refused for a reason its own JSON type already gives: a
/// boolean was written where a number belongs, and there is nothing more to say. A
/// *structured* one is not. `kind.fills=[{"type":"solid","color":"#FFD166"}]` is an
/// array, and arrays are accepted — what is wrong is one spelling inside element
/// zero, and a refusal that says only "an array" contradicts the forms it just
/// listed. `DecodingError` knows exactly which element and which key, in a coding
/// path and a debug description, but phrases it in Swift's vocabulary; this renders
/// it in the .pen file's own:
///
/// ```
/// [0].type: "solid" is not an accepted spelling
/// ```
enum PenDecodingFailure {
    /// The clause saying what inside a value was refused.
    ///
    /// - Parameters:
    ///   - error: The error the decode raised.
    ///   - field: The property's field name. Its JSON key leads every coding path
    ///     — the codec decodes the whole payload to patch one key of it — so the
    ///     clause drops it and locates the fault relative to the value as typed.
    /// - Returns: A clause like `[0].type: "solid" is not an accepted spelling`, or
    ///   `nil` when the error says no more than the value's own JSON type does.
    static func clause(for error: Error, field: String) -> String? {
        guard let decoding = error as? DecodingError else { return nil }
        let location = location(of: decoding, field: field)
        switch decoding {
        case let .dataCorrupted(context):
            return phrase(location, reason(context.debugDescription))
        case let .keyNotFound(key, _):
            return phrase(location, "the required key \"\(key.stringValue)\" is missing")
        case .typeMismatch, .valueNotFound:
            guard location != nil else { return nil }
            return phrase(location, "the value there is not one of the accepted forms")
        @unknown default:
            return nil
        }
    }

    // MARK: - Private

    /// A location and a reason, joined the way a refusal reads them.
    private static func phrase(_ location: String?, _ reason: String) -> String {
        guard let location else { return reason }
        return "\(location): \(reason)"
    }

    /// Where in the value the fault is, as `[0].type`, or `nil` at its very root.
    private static func location(of error: DecodingError, field: String) -> String? {
        var keys = context(of: error).codingPath
        if let first = keys.first, first.intValue == nil,
           first.stringValue == NodePropertyCodec.jsonKey(for: field)
        {
            keys.removeFirst()
        }
        guard !keys.isEmpty else { return nil }
        var text = ""
        for key in keys {
            if let index = key.intValue {
                text += "[\(index)]"
            } else if text.isEmpty {
                text += key.stringValue
            } else {
                text += ".\(key.stringValue)"
            }
        }
        return text
    }

    /// A debug description phrased for someone reading a .pen file.
    ///
    /// The one description Swift writes itself — a `RawRepresentable` enum given a
    /// value it does not have — names the Swift type, which means nothing to a
    /// caller typing JSON. Every other description here is written by a .pen model
    /// and already reads in the file's own words, so it passes through.
    private static func reason(_ description: String) -> String {
        let pattern = /Cannot initialize \w+ from invalid \w+ value (.+)/
        guard let match = description.wholeMatch(of: pattern) else { return description }
        return "\"\(match.1)\" is not an accepted spelling"
    }

    /// The context every `DecodingError` case carries.
    private static func context(of error: DecodingError) -> DecodingError.Context {
        switch error {
        case let .dataCorrupted(context),
             let .keyNotFound(_, context),
             let .typeMismatch(_, context),
             let .valueNotFound(_, context):
            context
        @unknown default:
            DecodingError.Context(codingPath: [], debugDescription: "")
        }
    }
}
