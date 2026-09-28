//
//  IdentityOptions.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation

/// The `--as <name>` option group, in one of the three roles an identity plays.
///
/// Identity is a name, not an account: there is no registration step, and naming an
/// identity is creating it. It comes from `--as`, or from `$WOODCASE_AS` when the flag
/// is absent — never from the OS user, which would attribute a shared machine's edits
/// to whoever happens to be logged in.
///
/// The ``IdentityRole`` type argument picks the help text, because what `--as` means
/// differs by verb even though the resolution never does:
///
/// ```swift
/// @OptionGroup var identity: IdentityOptions<Identity.Attribution>  // add, set, cp, …
/// @OptionGroup var identity: IdentityOptions<Identity.Filter>       // activity
/// @OptionGroup var identity: IdentityOptions<Identity.Required>     // undo
/// ```
///
/// ``identity`` is `nil` when neither is set. Under ``Identity/Attribution`` that is
/// allowed, and it is *not* a reason to skip the log: `nil` reaches
/// ``PenFileTransaction/run(at:identity:log:timeout:effect:fonts:isolation:_:)`` as the unattributed writer and
/// the edit is recorded under ``ActivityEvent/unattributed``, so no write a verb makes is
/// ever missing from the history. Under ``Identity/Required`` the verb refuses instead —
/// the role says so, and the verb enforces it.
struct IdentityOptions<Role: IdentityRole>: ParsableArguments {
    @Option(name: .customLong("as"), help: Role.help)
    var identityName: String?

    /// The writer's name, or `nil` for an unattributed edit.
    var identity: String? {
        identity(in: ProcessInfo.processInfo.environment)
    }

    /// The writer's name as resolved against a given environment.
    ///
    /// - Parameter environment: The environment to read
    ///   ``Identity/environmentVariable`` from.
    /// - Returns: The trimmed name from `--as`, else the one from the environment,
    ///   else `nil`. Blank in either place counts as unset.
    func identity(in environment: [String: String]) -> String? {
        Self.name(identityName) ?? Self.name(environment[Identity.environmentVariable])
    }

    /// A raw value as a usable name: trimmed, and `nil` when nothing is left.
    private static func name(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}
