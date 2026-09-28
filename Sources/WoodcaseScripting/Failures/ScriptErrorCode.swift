//
//  ScriptErrorCode.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation

    /// The ``ScriptError/code`` values the *host* produces, as against the ones that come
    /// from the editing layer.
    ///
    /// A refusal thrown by ``Woodcase/EditableDocument`` keeps its own
    /// ``Woodcase/EditingError/code`` — `ambiguousAddress`, `revisionConflict` and the
    /// rest — because a script that catches one wants to branch on the same word a
    /// `--json` report carries. These are the failures that belong to the host itself and
    /// have no editing error behind them.
    ///
    /// Spelled as constants rather than an enum so a script's `err.code` and a Swift
    /// `switch` share exactly one spelling of each word, and so the vocabulary can grow
    /// with the write side without a breaking change to a frozen enum.
    public enum ScriptErrorCode {
        /// The run passed its deadline; the next bridged call refused. Catchable — a
        /// script may clean up — but every later call refuses the same way.
        public static let timeout = "timeout"

        /// A source did not parse. There is no line the script ran; the location is the
        /// one the parser reported.
        public static let syntaxError = "syntaxError"

        /// A member was read off `doc` that does not exist.
        public static let unknownMember = "unknownMember"

        /// An options object carried a key the member does not take.
        public static let unknownOption = "unknownOption"

        /// An argument was the wrong shape — an address that is not a string, a `depth`
        /// that is not a whole number, a `theme` that is not an object of strings.
        public static let badArgument = "badArgument"

        /// `setTimeout`, `setInterval`, `fetch`, `require` or an `import` statement: the
        /// things a script may not do because it runs to completion in one pass.
        public static let synchronousOnly = "synchronousOnly"

        /// `doc.schema` was given a name the .pen format has no node type for.
        public static let unknownNodeType = "unknownNodeType"

        /// A ``ScriptSource/file(_:)`` could not be read.
        public static let sourceUnreadable = "sourceUnreadable"

        /// `doc.vars.rm` was asked to remove a variable something still references.
        ///
        /// The host's rather than the editing layer's: removing a referenced variable is
        /// applied happily by ``Woodcase/EditableDocument`` — a node whose fill is
        /// `$brand` does not fail when `brand` disappears, it renders the unresolved
        /// reference — so the refusal is a decision about consequence, and `woodcase
        /// vars rm` makes the same one. `{ force: true }` is how it is opted into.
        public static let variableInUse = "variableInUse"

        /// `doc.imports.rm` was asked to remove an alias something still reaches into.
        ///
        /// Its own code rather than ``variableInUse``: a script that catches one branches
        /// on what to do next, and the two answers differ. An unused variable can simply
        /// be dropped; an alias in use means every `ref` and `$alias:` binding under it
        /// has to be repointed or detached first, which is a different repair.
        public static let importInUse = "importInUse"

        /// The script threw something that is not a `WoodcaseError` — its own `Error`, a
        /// `TypeError`, a bare string.
        public static let scriptError = "scriptError"
    }

#endif
