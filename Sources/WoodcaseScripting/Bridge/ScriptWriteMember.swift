//
//  ScriptWriteMember.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation
    import Woodcase

    /// Which member of `doc` made a write.
    ///
    /// A ``ScriptRun/Event/write(member:_:)`` carries one of these so a transcript row can
    /// lead with the verb, the way `apply`'s rows lead with `line N  applied`. Without it
    /// a `cp` and the three `override`s that fill the copy print four rows naming the same
    /// instance, because ``Woodcase/WriteReport`` says *what was touched* and never *what
    /// touched it*.
    ///
    /// An enum rather than the member's name as a string: the transcript pads the column
    /// to the widest name any run could print, and `allCases` is what makes that width a
    /// fact about the vocabulary rather than a number kept in the formatter.
    ///
    /// The raw values are the names a caller writes — dotted inside a namespace, and never
    /// carrying the `doc.` prefix, which belongs to the sentence a refusal is written in
    /// rather than to the row.
    public enum ScriptWriteMember: String, Friendly, CaseIterable {
        /// `doc.set`.
        case set

        /// `doc.add`.
        case add

        /// `doc.replace`.
        case replace

        /// `doc.cp`.
        case cp

        /// `doc.mv`.
        case mv

        /// `doc.rm`.
        case rm

        /// `doc.override`.
        case override

        /// `doc.vars.set`.
        case varsSet = "vars.set"

        /// `doc.vars.rm`.
        case varsRemove = "vars.rm"

        /// `doc.themes.set`.
        case themesSet = "themes.set"

        /// `doc.themes.rm`.
        case themesRemove = "themes.rm"

        /// `doc.imports.set`.
        case importsSet = "imports.set"

        /// `doc.imports.rm`.
        case importsRemove = "imports.rm"

        /// The member a batch verb is spelled as on `doc`.
        ///
        /// Seven of the ten share a name with the verb; the three document-level ones are
        /// nested, because `doc.var` would read as a keyword and `doc.themeAxis` names a
        /// wire spelling rather than a thing a caller has.
        ///
        /// - Parameter verb: The operation's verb.
        public init(_ verb: BatchOperation.Verb) {
            self = switch verb {
            case .set: .set
            case .add: .add
            case .replace: .replace
            case .cp: .cp
            case .mv: .mv
            case .rm: .rm
            case .override: .override
            case .variable: .varsSet
            case .themeAxis: .themesSet
            case .importOp: .importsSet
            }
        }

        /// How wide a column has to be to hold any member's name.
        ///
        /// The transcript pads to this, so every row's path starts at the same column
        /// whichever member wrote it — `apply`'s fixed status column, one surface over.
        public static let columnWidth = allCases.map(\.rawValue.count).max() ?? 0

        /// The name as a caller writes it, `doc.` and all.
        ///
        /// What a refusal names — *doc.cp could not read what it was given* — as against
        /// `rawValue`, which is the bare name a transcript column holds.
        public var qualifiedName: String {
            "doc.\(rawValue)"
        }
    }

#endif
