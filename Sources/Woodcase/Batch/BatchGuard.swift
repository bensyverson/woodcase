//
//  BatchGuard.swift
//  Woodcase
//

import Foundation

/// A premise a write asserts before it is allowed to happen: "this is still what I
/// read".
///
/// A guard carries a revision — ``EditableDocument/revision(of:)``, the same token
/// `--rev` takes — and what that revision was read for. Every guard of a transaction is
/// checked **once, at transaction entry**, by
/// ``BatchApplier/checkGuards(_:in:log:file:)``, before any line of it has run. That is
/// the whole difference from `rev`, which each line checks as it is applied:
///
/// - a guard answers *"has anyone else moved this since I read it?"*, because under the
///   file lock every foreign write strictly precedes entry and the batch's own lines all
///   follow it. Line 30 may guard a frame that line 3 legitimately rewrote;
/// - a `rev` answers *"is this node exactly as I last saw it, right now?"*, which a
///   batch's own earlier lines can and do falsify.
///
/// Both are opt-in, and a write with neither applies regardless — the default that keeps
/// fan-out free of spurious failures.
///
/// ## Wire form
///
/// ```jsonl
/// {"op":"set","target":"Files/Row","props":{…},"guard":"4f2a1b0c9d8e7f60"}
/// {"op":"set","target":"Files/Row","props":{…},"guard":{"node":"Files","rev":"4f2a…"}}
/// {"op":"add","parent":"Files","node":{…},"guard":{"node":"document","rev":"9c1b…"}}
/// ```
///
/// A bare string pins whatever the line itself acts on (see
/// ``BatchOperation/guardTarget``). An object pins a named ancestor — any node the
/// caller read and composed against — or the whole document, spelled `document` exactly
/// as a parent is. On the command line the same three shapes are `--guard <rev>`,
/// `--guard <node>=<rev>` and `--guard document=<rev>`, and `--guard` may be repeated.
public struct BatchGuard: Friendly {
    /// Creates a guard.
    ///
    /// - Parameters:
    ///   - rev: The revision the caller observed.
    ///   - scope: What that revision was read for. Defaults to ``Scope/target``.
    public init(rev: String, scope: Scope = .target) {
        self.rev = rev
        self.scope = scope
    }

    /// The revision the caller observed, as 16 lowercase hex characters.
    public var rev: String

    /// What the revision was read for.
    public var scope: Scope

    /// The word that means the whole document where a node is expected — the same word
    /// a parent takes, so an agent learns it once.
    public static let documentScope = NodeAddress.documentRoot

    /// What a guard's revision was read for.
    ///
    /// Three cases rather than an optional address: "the line's own target" and "the
    /// whole document" are different assertions, and a `nil` address cannot say which
    /// one a caller meant.
    public enum Scope: Friendly {
        /// The node the operation itself acts on — ``BatchOperation/guardTarget``.
        case target

        /// A named node: any ancestor (or unrelated node) the caller read.
        case node(NodeAddress)

        /// The whole document, pinned by ``EditableDocument/documentRevision``.
        case document
    }
}

// MARK: - Codable

public extension BatchGuard {
    /// Decodes a guard from a bare revision string or from a `{"node":…,"rev":…}` object.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError.dataCorrupted` when the value is neither shape.
    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let rev = try? single.decode(String.self) {
            self.init(rev: rev)
            return
        }
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        let rev = try keyed.decode(String.self, forKey: .rev)
        guard let node = try keyed.decodeIfPresent(String.self, forKey: .node) else {
            self.init(rev: rev)
            return
        }
        guard node != Self.documentScope else {
            self.init(rev: rev, scope: .document)
            return
        }
        guard let address = NodeAddress(node) else {
            throw DecodingError.dataCorruptedError(
                forKey: .node, in: keyed,
                debugDescription: "'\(node)' is not a node address"
            )
        }
        self.init(rev: rev, scope: .node(address))
    }

    /// Encodes a guard in the tersest shape that round-trips.
    ///
    /// - Parameter encoder: The encoder to write to.
    func encode(to encoder: Encoder) throws {
        guard case .target = scope else {
            var keyed = encoder.container(keyedBy: CodingKeys.self)
            try keyed.encode(rev, forKey: .rev)
            switch scope {
            case let .node(address): try keyed.encode(address.description, forKey: .node)
            case .document: try keyed.encode(Self.documentScope, forKey: .node)
            case .target: break
            }
            return
        }
        var single = encoder.singleValueContainer()
        try single.encode(rev)
    }

    /// The two fields of a guard's object form.
    private enum CodingKeys: String, CodingKey {
        case node, rev
    }
}
