//
//  ScriptLogLevel.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation
    import Woodcase

    /// Which `console` member a script printed a line with.
    ///
    /// Three levels, because three is what `console` has that carries meaning: the CLI
    /// sends ``log`` to stdout interleaved with the write rows, and ``warn`` and
    /// ``error`` to stderr, which is the split every other verb already makes.
    /// `console.info` and `console.debug` exist and report as ``log`` — a model reaches
    /// for them, and a `TypeError` teaches nothing.
    public enum ScriptLogLevel: String, Friendly, CaseIterable {
        /// `console.log`, `console.info`, `console.debug`.
        case log

        /// `console.warn`.
        case warn

        /// `console.error`.
        case error
    }

#endif
