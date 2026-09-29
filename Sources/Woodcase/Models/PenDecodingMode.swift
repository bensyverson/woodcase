//
//  PenDecodingMode.swift
//  Woodcase
//

import Foundation

/// Whether a decode is reading a .pen file or an agent's input, which decides what
/// happens to a key or a `type` the model does not recognize.
///
/// Set it on a decoder's `userInfo` under ``userInfoKey``:
///
/// ```swift
/// let decoder = JSONDecoder()
/// decoder.userInfo[PenDecodingMode.userInfoKey] = PenDecodingMode.authoring
/// let node = try decoder.decode(PenNode.self, from: data)   // throws on "fil"
/// ```
///
/// A decoder that sets nothing decodes in ``file`` mode. That is deliberate: every
/// decode Woodcase runs on its own output — the undo log, a CRDT operation, a property
/// codec round trip, an override merge — re-reads state that was already accepted, and
/// must keep what that state carries. Only the entry points that take an agent's input
/// (``PenSubtreeDecoder`` and the `set` value check) opt in to ``authoring``.
public enum PenDecodingMode: String, Friendly, CaseIterable {
    /// A .pen file, or Woodcase's own encoding of one: unclaimed keys become
    /// ``PenExtras``, and an unrecognized fill or effect `type` becomes `.unknown`.
    case file

    /// An agent's input — `add`, `replace`, `set`, a batch line, a script: an unclaimed
    /// key or an unrecognized fill or effect `type` is a decoding error.
    case authoring

    /// The `userInfo` key a decoder carries its mode under.
    public static let userInfoKey: CodingUserInfoKey = {
        guard let key = CodingUserInfoKey(rawValue: "com.bensyverson.woodcase.decodingMode") else {
            preconditionFailure("a non-empty raw value always makes a CodingUserInfoKey")
        }
        return key
    }()

    /// The mode a decoder was configured with, ``file`` when it names none.
    ///
    /// - Parameter decoder: The decoder being read from.
    /// - Returns: The mode its `userInfo` carries.
    public static func of(_ decoder: Decoder) -> PenDecodingMode {
        decoder.userInfo[userInfoKey] as? PenDecodingMode ?? .file
    }
}
