import ArgumentParser
import Foundation
import Woodcase

/// Rewrites .pen files in the current format version, in place.
struct Migrate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Write: rewrite .pen files in the current \(PenDocument.currentFormatVersion) format.",
        discussion: """
        Each file is parsed through the version gate — which migrates a 2.8–2.10 \
        document — and written back with sorted keys and two-space indentation. \
        Every diagnostic the migration emits is printed to stderr, prefixed with the \
        file's path. Files already at \(PenDocument.currentFormatVersion) — or at a \
        newer 2.x minor, which a newer Pen wrote — are left alone unless --force is \
        given, and --force keeps a newer minor's own version. A file of another major \
        version is read-only: it is reported as a failure and left untouched.

        Each file is rewritten under its lock, like any other write, and gains one \
        `migrate` row in the activity log, attributed to --as. A migration changes the \
        file's bytes, not its document, so its revision is unchanged and `undo` passes \
        over the row.

        One unusable file does not stop the rest: every failure is reported, the run \
        finishes, and the exit is 4. A path that names nothing is 4 as well; naming a \
        file that is not a .pen file is 2. --dry-run always exits 0 when nothing failed.

          woodcase migrate ./designs --dry-run
        """
    )

    @Argument(help: "The .pen files, or directories to search recursively, to migrate.")
    var inputs: [PenInputPath]

    @Flag(name: .long, help: "Report what would change without writing anything.")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Rewrite files that already declare the current version.")
    var force: Bool = false

    @Option(name: .long, help: "A file or directory to leave alone (repeatable).")
    var exclude: [String] = []

    @OptionGroup var identity: IdentityOptions<Identity.Attribution>

    /// Expands the arguments, rewrites every .pen file among them, and reports.
    ///
    /// - Throws: ``CommandFailure`` when an argument names nothing (4) or names a file
    ///   that is not a .pen file (2); `CleanExit` when the arguments hold no .pen file
    ///   at all; ``ExitCode/targetFailure`` (4) when at least one file could not be
    ///   read, migrated or written — after every other file has been done.
    func run() async throws {
        let files = try Migrate.penFiles(in: inputs, excluding: exclude)
        guard !files.isEmpty else {
            throw CleanExit.message("No .pen files found.")
        }

        var migrated = 0
        var skipped = 0
        var failed = 0

        let writer = identity.identity
        for url in files {
            let diagnostics = PenDiagnosticCollector()
            let transaction: PenFileTransaction.Outcome<PenFileMigrator.Outcome>
            do {
                transaction = try await PenFileTransaction.migrate(
                    at: url, identity: writer, effect: dryRun ? .dryRun : .commit,
                    rewritingCurrent: force, diagnostics: diagnostics
                )
            } catch {
                report(error, for: url)
                failed += 1
                continue
            }
            for diagnostic in diagnostics.diagnostics {
                warn("\(url.path): \(diagnostic)")
            }
            if let note = transaction.lineage.note(naming: url) {
                warn("note  \(note)")
            }

            guard transaction.wouldWrite else {
                skipped += 1
                continue
            }
            let outcome = transaction.value
            let from = outcome.declaredVersion ?? "no version"
            let verb = transaction.didWrite ? "migrated" : "would migrate"
            print("\(verb) \(url.path) (\(from) → \(outcome.writtenVersion))")
            migrated += 1
        }

        let verb = dryRun ? "would migrate" : "migrated"
        print("\(verb) \(migrated) file(s), skipped \(skipped) already current, \(failed) failed.")
        if failed > 0 {
            // A file that exists but could not be rewritten is a target failure (4),
            // the same number every other verb returns for a .pen file it cannot read
            // — not a clean negative (1), which is reserved for a check that ran and
            // answered no, and which a script would read as "nothing to do".
            throw ExitCode.targetFailure
        }
    }

    // MARK: - Discovery

    /// Expands the command's arguments into the .pen files to rewrite.
    ///
    /// A directory is searched recursively; a file argument must itself be a .pen
    /// file. The result is sorted by path, so a run over a tree is reproducible.
    ///
    /// - Parameters:
    ///   - inputs: File or directory paths.
    ///   - excluded: File or directory paths to leave out. A directory excludes
    ///     everything beneath it — that is how `Fixtures/v2.9`, whose whole point is
    ///     to stay legacy, survives a run over `Tests`.
    /// - Returns: The .pen files to migrate, de-duplicated and sorted by path.
    /// - Throws: ``CommandFailure`` with ``ExitCode/targetFailure`` if a path does not
    ///   exist, and with ``ExitCode/usage`` if one names a file that is not a .pen file
    ///   — see ``PenInputPath/existingTarget()``.
    static func penFiles(
        in inputs: [PenInputPath], excluding excluded: [String] = []
    ) throws -> [URL] {
        var found: Set<URL> = []
        for input in inputs {
            switch try input.existingTarget() {
            case let .directory(url):
                found.formUnion(penFiles(under: url))
            case let .file(url):
                found.insert(url)
            }
        }
        let barriers = excluded.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        return found
            .filter { url in !barriers.contains { url.path == $0 || url.path.hasPrefix($0 + "/") } }
            .sorted { $0.path < $1.path }
    }

    /// Every .pen file beneath a directory, at any depth.
    private static func penFiles(under directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "pen" }
            .map(\.standardizedFileURL)
    }

    // MARK: - Reporting

    /// Prints one file's failure to stderr and lets the run continue, so a single
    /// unreadable file in a tree does not hide the rest.
    private func report(_ error: Error, for url: URL) {
        let message: String = if let parserError = error as? PenParserError {
            parserError.description
        } else if let refusal = error as? PenFormatWriteRefusal {
            ReadOnlyFormatMessage.describe(refusal)
        } else if let fileError = error as? PenFileError {
            fileError.description
        } else {
            error.localizedDescription
        }
        warn("\(url.path): error: \(message)")
    }

    /// Writes one line to stderr, keeping diagnostics out of the piped stdout report.
    private func warn(_ line: String) {
        FileHandle.standardError.write(Data("\(line)\n".utf8))
    }
}
