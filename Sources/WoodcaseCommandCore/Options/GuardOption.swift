//
//  GuardOption.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Woodcase

/// The `--guard <rev>` option group every mutating verb includes, beside `--rev`.
///
/// A guard is a **premise assertion**: "nothing anyone else did since my read moved
/// what I reasoned about." It takes the same token `--rev` takes — the per-node
/// revision a read printed — and differs in when and where it is checked:
///
/// | | `--rev` | `--guard` |
/// |---|---|---|
/// | asks | is this node exactly as I saw it, right now? | has anyone *else* moved this since my read? |
/// | checked | as the edit is applied | once, at transaction entry |
/// | scope | the node the verb acts on | that node, or any ancestor you name |
///
/// The difference shows in a batch. `--rev` on line 30 is checked after lines 1–29 have
/// run, so a batch that touches its own subtree trips itself and an agent rationally
/// disarms it. A guard is evaluated before line 1, so it stays true of the caller's
/// premise and false only when someone else has moved it.
///
/// ```bash
/// woodcase set design.pen Card/Title kind.content=Hi --guard 4f2a1b0c9d8e7f60
/// woodcase set design.pen Card/Title kind.content=Hi --guard Card=4f2a1b0c9d8e7f60
/// woodcase add design.pen document -F art.json --guard document=9c1b04e6f2a71d38
/// ```
///
/// Written bare the revision pins what the verb acts on — the parent for `add` and
/// `cp`, the whole document at the root. Written `<node>=<rev>` it pins that node's
/// whole subtree, which is how a caller says "I read this frame and composed against
/// everything in it". `--guard` may be given more than once. A moved premise exits
/// ``ExitCode/conflict`` (3), names both revisions and whoever moved it, and changes
/// nothing.
struct GuardOption: ParsableArguments {
    @Option(
        name: .customLong("guard"),
        parsing: .singleValue,
        help: ArgumentHelp(
            """
            A premise: the revision you read, unchanged by anyone else. Bare, it pins \
            what this verb acts on; <node>=<rev> pins that node's whole subtree, and \
            document=<rev> the whole file. Repeatable. A moved premise fails with exit \
            3 and changes nothing.
            """,
            valueName: "rev"
        )
    )
    var pins: [String] = []

    /// The pins, parsed.
    ///
    /// - Returns: One ``BatchGuard`` per `--guard`, in the order they were written.
    /// - Throws: ``CommandFailure`` with ``ExitCode/usage`` when a value is not a
    ///   revision, or names something that is not an address.
    func guards() throws -> [BatchGuard] {
        try pins.map(Self.parse)
    }

    /// Parses one `--guard` value: `<rev>`, `<node>=<rev>`, or `document=<rev>`.
    ///
    /// The split is on the **last** `=`, so a node whose name contains one still
    /// resolves: a revision never does.
    static func parse(_ raw: String) throws -> BatchGuard {
        guard let separator = raw.lastIndex(of: "=") else {
            return try BatchGuard(rev: revision(raw, in: raw))
        }
        let node = String(raw[raw.startIndex ..< separator])
        let rev = try revision(String(raw[raw.index(after: separator)...]), in: raw)
        guard node != AddressArgument.documentRoot else {
            return BatchGuard(rev: rev, scope: .document)
        }
        guard let address = NodeAddress(node) else {
            throw CommandFailure(
                message: "--guard \(raw) does not name a node: \(node) is not an address. "
                    + AddressArgument.addressForms,
                exitCode: .usage
            )
        }
        return BatchGuard(rev: rev, scope: .node(address))
    }

    /// Refuses anything that is not a revision, which is what makes a mistyped guard a
    /// message rather than a check that quietly compares two things that were never
    /// going to be equal.
    private static func revision(_ candidate: String, in raw: String) throws -> String {
        guard candidate.count == revisionLength,
              candidate.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
        else {
            throw CommandFailure(
                message: """
                --guard \(raw) is not a revision: a revision is \(revisionLength) lowercase hex \
                characters, like 4f2a1b0c9d8e7f60. Read one with `woodcase get <file> <node>`, or \
                from a row of `woodcase tree <file> --json`. To pin a named node, write \
                --guard <node>=<rev>.
                """,
                exitCode: .usage
            )
        }
        return candidate
    }

    /// How many hex characters ``Woodcase/EditableDocument/revision(of:)`` produces.
    private static let revisionLength = 16
}
