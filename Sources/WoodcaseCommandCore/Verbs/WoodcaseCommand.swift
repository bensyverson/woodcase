import ArgumentParser
import Foundation

/// The root of the `woodcase` command tree, and the library's one entry point.
///
/// It is `package` rather than `internal` because the `WoodcaseCommand` executable
/// target is a one-file `@main` shim over ``main()``; nothing outside this package
/// needs it, and nothing else here is exported. Every verb below it stays internal.
package struct WoodcaseCommand: AsyncParsableCommand {
    /// Creates the root command. ArgumentParser calls this; nothing else should.
    package init() {}

    package static let configuration = CommandConfiguration(
        commandName: "woodcase",
        abstract: "Read, edit and render Pen .pen design files.",
        discussion: """
        Every verb takes the .pen file as its first argument and leaves it a plain, \
        canonical .pen file any editor of the format can still open. There is no \
        session and no daemon: \
        a command opens the file, does one thing, and writes it back under a lock.

          read    tree  find  get  shot  lint  activity  vars  imports  icons  schema
                  never write; --json on every one, and a document read carries a revision
          write   new  add  set  replace  cp  mv  rm  override  apply  js  undo
                  attributed with --as, appended to the activity log, guarded by --rev
          render  render  themes  generate  migrate
          view    serve  preview

        START HERE with `woodcase tree design.pen`. It prints one row per node — type, \
        name, the settled rectangle, and the id — and every row's address is one any \
        other verb accepts; its header line carries the revision to quote back with \
        --rev on the write that follows.

        THEN `woodcase help design` for the flex-first layout rules, addressing, batch \
        tags and the read-write-verify loop, `woodcase help schema [<type>]` for every \
        property a node type takes and the shape of each value, `woodcase help recipes` \
        for runnable command sequences, and `woodcase <verb> --help`, which carries a \
        worked example. No other manual is needed.

        EXIT CODES are the same across this family of tools: 0 success, 1 a clean \
        negative (lint found something), 2 a malformed invocation, 3 a conflict (a \
        stale --rev, a lock held elsewhere), 4 the file could not be read, 5 the \
        environment is wrong.
        """,
        version: WoodcaseVersion.line,
        subcommands: [
            Tree.self, Find.self, Get.self, Shot.self, Lint.self, Schema.self, Undo.self,
            NewCommand.self,
            AddCommand.self, SetCommand.self, ReplaceCommand.self, CopyCommand.self,
            MoveCommand.self, RemoveCommand.self,
            OverrideCommand.self, Apply.self, Js.self, Vars.self, Imports.self,
            Render.self, Themes.self, Generate.self, Migrate.self, Activity.self, Icons.self,
            Serve.self, Preview.self, Help.self,
        ]
    )

    /// Parses and runs, ending the process with a house exit code.
    ///
    /// ArgumentParser's own entry point exits 64 for a malformed invocation, which is
    /// `EX_USAGE` from `sysexits.h`. The house table says 2 (see
    /// ``ArgumentParser/ExitCode/usage``), and an agent has to be able to rely on the
    /// same number across every tool in the family, so the translation happens here —
    /// once, for every verb — rather than in each verb's `run()`.
    ///
    /// Everything else keeps ArgumentParser's behaviour: `--help` and `CleanExit` print
    /// on stdout and exit 0, and an ``ArgumentParser/ExitCode`` thrown by a verb is
    /// obeyed silently, because whoever threw it has already said what happened.
    /// The isolation is explicit because it used to be inferred: `@main` gives the
    /// entry point of an executable target main-actor isolation for free, and this type
    /// no longer carries `@main` — the `WoodcaseCommand` executable's shim does. Every
    /// verb ran on the main actor before the split and still does.
    ///
    /// This is now the *only* thing that puts a verb on the main actor. The library is
    /// non-isolated: ``Woodcase/PenFileTransaction`` runs its body on the caller's
    /// isolation, and an ``Woodcase/EditableDocument`` belongs to whoever made it. So a
    /// verb lands on the main actor because this entry point does, and for no other
    /// reason — which is what lets the same library run a document off it elsewhere.
    @MainActor
    package static func main() async {
        // The vector is normalised before the parser sees it, because
        // ArgumentParser cannot express an option whose value may be omitted.
        let arguments = BareOptionValue.filled(Array(CommandLine.arguments.dropFirst()))
        do {
            var command = try parseAsRoot(arguments)
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            exitReportingHouseCode(error, given: arguments)
        }
    }

    /// Prints what a failure has to say and exits with its house code.
    ///
    /// - Parameters:
    ///   - error: The failure that ended the command.
    ///   - arguments: The command line the parser was given, so a usage failure whose
    ///     cause is the invocation's *shape* can say which rule it broke. See
    ///     ``SeparatorRemedy``.
    /// - Returns: Never; the process exits.
    @MainActor
    private static func exitReportingHouseCode(_ error: any Error, given arguments: [String]) -> Never {
        // A clean exit or a help request: ArgumentParser prints it on stdout, exit 0.
        guard exitCode(for: error) != .success else {
            exit(withError: error)
        }
        if let code = error as? ExitCode {
            Foundation.exit(code.rawValue)
        }
        if exitCode(for: error) == .validationFailure {
            StandardError.write(SeparatorRemedy.message(for: arguments) ?? fullMessage(for: error))
            Foundation.exit(ExitCode.usage.rawValue)
        }
        let failure = CommandFailure.describing(error)
        StandardError.write(failure.message)
        Foundation.exit(failure.exitCode.rawValue)
    }
}
