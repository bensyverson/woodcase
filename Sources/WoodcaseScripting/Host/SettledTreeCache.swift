//
//  SettledTreeCache.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation
    import Woodcase

    /// The settled trees a script run has already paid for, one per theme.
    ///
    /// Pen's own MCP taught the rule a script has to obey: *a read after a write must see
    /// settled layout, in the same invocation, always.* Settling is a full pipeline —
    /// expansion, variable resolution, font registration, layout — so a script that reads
    /// three times between two writes must not pay for it three times, and a script that
    /// writes must not be allowed to read a stale rect.
    ///
    /// Both halves are here: a tree is built on first ask and kept, and ``invalidate()``
    /// marks every one of them stale. The write side calls ``invalidate()`` after each
    /// write, so the next read settles again — **incrementally**: the stale tree is handed
    /// to ``Woodcase/SettledTree``'s reusing settle, which lays out again only the roots
    /// the write could have moved (a root whose subtree or whose components changed, or
    /// every root when a variable, a theme axis, an import or the font set did) and keeps
    /// the rest. Which roots those are is decided in the library, from what the document
    /// holds now, never from what the write said it did — so no write path can forget to
    /// report one.
    ///
    /// Every settle of the run measures text through one ``Woodcase/TextSizeCache``,
    /// shared with the run's overlap check, so a text is typeset once per run and font set.
    ///
    /// Keyed by theme because a themed read (`doc.tree(null, { theme: { mode: 'dark' } })`)
    /// resolves different variables and so lays out differently; two themes in one script
    /// keep two trees rather than thrashing one.
    ///
    /// Not `Sendable`, and deliberately: it holds values derived from an
    /// ``Woodcase/EditableDocument``, which belongs to whoever made it.
    final class SettledTreeCache {
        /// Creates an empty cache.
        ///
        /// - Parameter textSizes: The text sizes every settle of the run shares. A test
        ///   passes one whose font set it controls.
        init(textSizes: TextSizeCache = TextSizeCache()) {
            self.textSizes = textSizes
        }

        /// The text sizes every settle of the run shares.
        let textSizes: TextSizeCache

        /// Trees already built, keyed by ``key(for:)``.
        private var trees: [String: SettledTree] = [:]

        /// The keys of trees a write has made stale since they were built.
        private var stale: Set<String> = []

        /// How many times a tree has been built — whole or by reusing a stale one — for
        /// the tests that assert the cache is doing its job.
        private(set) var settleCount = 0

        /// How many roots have been laid out, across every settle of the run.
        private(set) var rootSettleCount = 0

        /// The settled tree for a theme, building it if this run has not already and
        /// bringing it up to date if a write has made it stale.
        ///
        /// - Parameters:
        ///   - theme: The theme axes to pin, merged over the document's default theme.
        ///   - document: The document to settle.
        /// - Returns: The tree, from the cache, brought up to date, or freshly built.
        func tree(for theme: [String: String], of document: EditableDocument) -> SettledTree {
            let key = Self.key(for: theme)
            if let cached = trees[key], !stale.contains(key) { return cached }
            let settled = SettledTree(
                document: document, theme: theme, textSizes: textSizes, reusing: trees[key]
            )
            trees[key] = settled
            stale.remove(key)
            settleCount += 1
            rootSettleCount += settled.ledger?.laidOut.count
                ?? document.rootOrder.count { document.nodes[$0] != nil }
            return settled
        }

        /// Marks every settled tree stale, so the next read brings it up to date.
        ///
        /// Called after every write. It decides nothing about *what* the write moved: the
        /// reusing settle compares every root against the document as it now stands, so
        /// there is no partial invalidation here to get wrong.
        func invalidate() {
            stale = Set(trees.keys)
        }

        /// A stable cache key for a theme.
        ///
        /// A dictionary has no order, so the pairs are sorted before they are joined;
        /// `=` and `;` are the separators, and an axis name or value containing either
        /// would only ever merge two entries that settle identically anyway.
        ///
        /// - Parameter theme: The axes to key on.
        /// - Returns: The key.
        private static func key(for theme: [String: String]) -> String {
            theme.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ";")
        }
    }

#endif
