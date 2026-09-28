//
//  IdentityRole.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation

/// What `--as <name>` *means* on the verb carrying it.
///
/// The flag is spelled the same everywhere, which is the point — an agent learns one
/// identity flag for the whole tool. What it does with the name is not the same
/// everywhere: on a verb that edits a file the name is attribution, on `activity` it is
/// a filter, and on `undo` it is required, because an unlogged undo would leave the
/// activity log no longer describing the file. Help that claimed one of those on a verb
/// that means another would be worse than no help.
///
/// ArgumentParser fixes an option's help text when the type is declared, not when it is
/// used, so the role has to reach the declaration — which is why ``IdentityOptions`` is
/// generic over one of these rather than taking a parameter.
protocol IdentityRole {
    /// The help ArgumentParser prints for `--as` on a verb in this role.
    static var help: ArgumentHelp { get }
}

/// The three roles `--as` plays, and the environment variable they all default from.
///
/// A namespace, not a value: each role is a case-less enum used only as a type
/// argument to ``IdentityOptions``.
enum Identity {
    /// The environment variable `--as` defaults from, in every role.
    static let environmentVariable = "WOODCASE_AS"

    /// `--as` names who a write is attributed to. The role of every verb that edits.
    enum Attribution: IdentityRole {
        static let help = ArgumentHelp(
            """
            Who to attribute this edit to. Defaults to $\(Identity.environmentVariable); \
            with neither, the edit is logged as an unattributed write.
            """,
            valueName: "name"
        )
    }

    /// `--as` narrows a read to one writer. The role of `activity`.
    enum Filter: IdentityRole {
        static let help = ArgumentHelp(
            """
            Show only this writer's events. Defaults to $\(Identity.environmentVariable); \
            with neither, every writer's are shown.
            """,
            valueName: "name"
        )
    }

    /// `--as` is who you are, and the verb refuses without it. The role of `undo`.
    enum Required: IdentityRole {
        static let help = ArgumentHelp(
            """
            Who you are: whose edits to reverse, and who the undo is recorded as. \
            Defaults to $\(Identity.environmentVariable); undo refuses without one.
            """,
            valueName: "name"
        )
    }
}
