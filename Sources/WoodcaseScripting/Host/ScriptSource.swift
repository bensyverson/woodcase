//
//  ScriptSource.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation
    import Woodcase

    /// One piece of JavaScript to evaluate: a file on disk, or a string the caller
    /// already holds.
    ///
    /// The host takes an ordered list of these and evaluates them one at a time in one
    /// context, so a helpers file precedes the run that uses it and top-level `const`
    /// declared in the first is visible to the second. Each is evaluated with its own
    /// source URL, so an error in the second reports *that* source's line rather than a
    /// line in a concatenation.
    ///
    /// Where a script comes from is the caller's decision, never the host's: the CLI's
    /// repeated `-F` maps onto this list and holds nothing of its own, and a library
    /// consumer — Penumbra, a test — hands over strings it already has without touching
    /// disk.
    ///
    /// ```swift
    /// let run = ScriptHost.run(
    ///     [.file(helpers), .text("doc.lint().length", name: "<argv>")],
    ///     over: document
    /// )
    /// ```
    public enum ScriptSource: Friendly {
        /// A file to read and evaluate. Its path is the name an error reports.
        case file(URL)

        /// Source the caller holds, with the name an error should report it under —
        /// `"<stdin>"`, `"<argv>"`, a rule name, whatever the caller calls it.
        case text(String, name: String)

        /// What an error's location names this source.
        public var name: String {
            switch self {
            case let .file(url): url.path
            case let .text(_, name): name
            }
        }
    }

#endif
