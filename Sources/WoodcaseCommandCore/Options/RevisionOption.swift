//
//  RevisionOption.swift
//  WoodcaseCommandCore
//

import ArgumentParser

/// The `--rev <hash>` option group every mutating verb includes.
///
/// Optimistic concurrency, scoped as narrowly as the edit is: the revision a read
/// handed back guards *that node*, not the whole file, so two agents editing two
/// cards never conflict. Pass the `rev` a read or an earlier write printed; if the
/// node has changed since, the verb exits ``ExitCode/conflict`` (3) naming the node
/// and both revisions, and changes nothing.
///
/// ```bash
/// woodcase set design.pen Card/Title kind.content=Hi --rev 4f2a1b0c9d8e7f60
/// ```
///
/// Omitting it means "apply regardless", which is right for a first write and wrong
/// for a read-then-write. The check covers the node the verb acts on — for `add` and
/// `cp` that is the parent, and at the document root it is the whole document.
///
/// ``GuardOption`` is its sibling and takes the same token. `--rev` asks "is this node
/// exactly as I last saw it, *right now*", checked as the edit applies; `--guard` asks
/// "has anyone *else* moved it since my read", checked once at transaction entry and
/// scopable to any node the caller read. Use `--rev` for a single read-then-write, and
/// `--guard` when the premise is bigger than the node being written.
struct RevisionOption: ParsableArguments {
    @Option(
        name: .long,
        help: ArgumentHelp(
            """
            The revision you last observed for this node. A stale value fails with \
            exit 3 and changes nothing.
            """,
            valueName: "hash"
        )
    )
    var rev: String?
}
