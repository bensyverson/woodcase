import ArgumentParser
import Foundation
import Woodcase

struct Lint: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Read: what is wrong with a .pen file, from its settled layout.",
        discussion: """
        A read verb and an assertion: it exits 1 when it finds anything and 0 when the \
        file is clean, so `woodcase lint design.pen && woodcase render design.pen` \
        renders only a file that passed.

        One line per finding, in document order:

            warning clipped  Card/Title (x9Kqp)  20,80 160×24 sits partly outside Card (200×100)

        The checks are the pipeline's own diagnostics plus, from the layout as it \
        settles for the chosen theme: a text node with no fill, a fill_container node \
        whose parent sizes to content on the same axis, a fit_content container with \
        no children, a node that falls outside its parent, two roots on top of each \
        other, two nodes sharing a name, a ref whose component is missing, a property \
        still holding an unresolved $variable, and a ref's stored override carrying a \
        value, a key, or a property the instance will silently drop when it expands. \
        Three say what Pen will do to the file: a mesh gradient Pen paints nothing \
        for (points or colors that do not fill columns × rows, or a grid under 2×2), \
        one it paints distorted (a color its mesh misreads, such as 4-digit #RGBA, \
        or a patch folded over itself), and a stroke, underline or strikethrough on text, which Pen strips \
        on load and never draws. \
        Three more read only the metadata `generate react` reads, and say what it will \
        choke on: a component's `_props` entry that resolves to no descendant, a \
        `_role` outside the roles it knows, and an instance whose overrides no declared \
        prop covers — which makes the emitter inline a copy of the component instead of \
        writing a tag for it.

        `woodcase lint --list` prints every check with the one line saying what it \
        looks for, and reads no file:

            woodcase lint --list

        `--summary` reports the same run as one row per check that fired, with a count, \
        rather than one line per finding — the read for a file with sixty findings:

            woodcase lint design.pen --summary

        Fonts are not checked: deciding whether a family is a typo or a downloadable \
        Google font needs the network, and lint stays offline.

        Filter what's reported with --exclude (repeatable, one check id per use) and \
        --severity (report only findings at or above the level); both also narrow what \
        --list prints. A phone screen whose scrolling list is meant to overflow the \
        fold trips `clipped` on purpose — or, better, say so: set \
        common.metadata._scroll to "vertical" or "horizontal" on the clipping frame \
        (clip:true) and lint stays quiet on overflow along that axis alone, still \
        catching a real bug on the other one. Left unannotated, a clipping frame that \
        stacks its children folds every child that only overflows its own stacking axis \
        into one finding on the frame, naming how many and how far, rather than one \
        finding per row of a long list. A pre-render gate that wants neither kind of \
        noise:

            woodcase lint design.pen --exclude clipped && woodcase render design.pen

        or, to gate on real breakage alone and leave warnings for a human to read:

            woodcase lint design.pen --severity error

        A file written by a newer Pen of the same major (2.20 while this build models \
        2.19) reads with a notice, which only --severity notice shows and which never \
        makes lint exit 1. A file of another major reads with a warning, and is \
        read-only: every write verb refuses it.

        Example:

            woodcase lint design.pen Dashboard/Header --theme "mode=dark" --json
        """
    )

    @Argument(help: "The .pen file to lint. Not read — and not accepted — with --list.")
    var file: PenFilePath?

    @Argument(help: "Lint only this subtree, by name path or id. Default: the whole document.")
    var node: String?

    @Flag(help: "List every check with its id and one-line description, and read no file.")
    var list: Bool = false

    @Flag(help: "Report one row per check that fired, with a count, instead of one line per finding.")
    var summary: Bool = false

    @Option(help: "Skip findings from this check id (e.g. clipped). Repeatable.")
    var exclude: [LintCheck] = []

    @Option(
        help: ArgumentHelp(
            "Report only findings at or above this severity (notice, warning, error). Default: warning; "
                + "a notice never makes lint exit 1."
        )
    )
    var severity: PenDiagnostic.Severity?

    @OptionGroup var themePin: ThemeOption

    @OptionGroup var output: OutputOptions

    /// Refuses the combinations that would silently do nothing.
    ///
    /// `--list` is the catalog of checks, not a read of a document: it takes no file,
    /// no subtree and no theme, and pairing it with `--summary` asks for two different
    /// reports at once. Everything else composes — `--exclude` and `--severity` narrow
    /// the catalog the same way they narrow a report, and `--summary` is the same run
    /// as the default counted rather than listed.
    func validate() throws {
        if list {
            guard !summary else {
                throw ValidationError(
                    "--list and --summary are two different reports: --list is the catalog of "
                        + "checks and --summary counts one file's findings. Pass one."
                )
            }
            guard file == nil, node == nil else {
                throw ValidationError(
                    "--list reads no file — it prints the checks themselves. Run `woodcase lint --list`, "
                        + "or drop --list to lint \(file?.path ?? "a file")."
                )
            }
            guard themePin.theme == nil else {
                throw ValidationError("--theme pins a document's variables, and --list settles no document.")
            }
        } else if file == nil {
            throw ValidationError(
                "Missing expected argument '<file>': the .pen file to lint. "
                    + "Run `woodcase lint --list` for the checks themselves."
            )
        }
    }

    func run() async throws {
        guard !list else {
            try print(catalog())
            return
        }
        // Unreachable: validate() has already refused a run with no file and no --list.
        // Spelled as a refusal rather than a `return` so it can never exit 0 in silence.
        guard let file else {
            throw ValidationError("Missing expected argument '<file>': the .pen file to lint.")
        }
        let url = try file.existingFile()
        try await runReportingFailures(editing: url) {
            let pins = try ThemePinParser.parse(themePin.theme)
            let diagnostics = PenDiagnosticCollector()
            let outcome = try await PenFileTransaction.read(at: url, diagnostics: diagnostics, fonts: .shared) { document in
                do {
                    return try DocumentLinter.findings(
                        in: document,
                        root: node,
                        theme: pins,
                        diagnostics: diagnostics.diagnostics
                    )
                } catch {
                    throw CommandFailure.describing(error, in: document, editing: url)
                }
            }

            let findings = outcome.value.filter(keeps)
            let report = try report(of: findings)
            if !report.isEmpty {
                print(report)
            }
            // A notice is printed when asked for and never fails the check: lint's
            // exit says whether the design has a problem, and a newer Pen is not one.
            guard !findings.contains(where: { $0.severity.meetsOrExceeds(.warning) }) else {
                throw ExitCode.cleanNegative
            }
        }
    }

    // MARK: - Reports

    /// The catalog, narrowed by the same two filters a report is narrowed by.
    private func catalog() throws -> String {
        let excluded = Set(exclude)
        let threshold = severity ?? .warning
        let checks = LintCheck.allCases.filter {
            !excluded.contains($0) && $0.severity.meetsOrExceeds(threshold)
        }
        return output.json ? try LintFormatter.listJSON(checks) : LintFormatter.list(checks)
    }

    /// The findings, as lines or as counted rows.
    private func report(of findings: [LintFinding]) throws -> String {
        switch (summary, output.json) {
        case (true, true): try LintFormatter.summaryJSON(findings)
        case (true, false): LintFormatter.summary(findings)
        case (false, true): try LintFormatter.json(findings)
        case (false, false): LintFormatter.text(findings)
        }
    }

    /// Whether a finding survives `--exclude` and `--severity`.
    private func keeps(_ finding: LintFinding) -> Bool {
        !Set(exclude).contains(finding.check) && finding.severity.meetsOrExceeds(severity ?? .warning)
    }
}
