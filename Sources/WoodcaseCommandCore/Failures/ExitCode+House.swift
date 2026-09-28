//
//  ExitCode+House.swift
//  WoodcaseCommandCore
//

import ArgumentParser

/// The house exit-code table, shared by every command-line tool in this family so an
/// agent learns it once (`project/agents/cli-design.md`).
///
/// | Code | Meaning |
/// |---|---|
/// | 0 | Success, or the asserted condition holds |
/// | 1 | Clean negative: the check ran and the answer is no |
/// | 2 | Usage error: the invocation itself was malformed |
/// | 3 | Conflict or timeout: the world changed, a lock or budget ran out |
/// | 4 | Target failure: the file could not be loaded |
/// | 5 | Environment error: missing session, dead helper, wrong setup |
///
/// ArgumentParser supplies 0 as `ExitCode.success` and 1 as `ExitCode.failure`; the
/// rest are named here. Note that ArgumentParser's own `ExitCode.validationFailure` is
/// 64, which this table overrides with 2 — see ``WoodcaseCommand/main()``.
///
/// A verb never invents a number: it throws one of these, or throws a
/// ``CommandFailure`` and lets the mapping choose.
extension ExitCode {
    /// The check ran and the answer is no — a `lint` with findings, an `--exists`
    /// that does not. A clean negative is not an error; scripts branch on it.
    static let cleanNegative = ExitCode(1)

    /// The invocation was malformed: an unknown flag, a missing argument, an address
    /// that does not resolve, a property no node of that type has.
    static let usage = ExitCode(2)

    /// The world changed underneath, or a wait ran out: a stale revision, a .pen file
    /// another process still holds the lock on.
    static let conflict = ExitCode(3)

    /// The target could not be loaded: the .pen file is missing, unreadable, or not a
    /// .pen document at all.
    static let targetFailure = ExitCode(4)

    /// The setup around the command is wrong: the activity log cannot be written, a
    /// helper is missing, `$WOODCASE_HOME` points somewhere unusable.
    static let environment = ExitCode(5)
}
