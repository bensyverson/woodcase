//
//  WriteReport.swift
//  Woodcase
//

import Foundation

/// What a mutating verb answers with, in one shape for all six of them.
///
/// A write's answer has to save the next command a lookup, so it carries three
/// things: *what* the verb touched, the revision to guard the next edit of it with,
/// and the document's revision. Creating verbs lead with the name → id tree of what
/// they made; the rest lead with the node they acted on.
///
/// ```text
/// Hero  k2Bq9
///   Caption  Tz01m
/// rev  61b1a0c2d4e5f607
/// document  a1b2c3d4e5f60718
/// ```
///
/// ```text
/// Canvas/Title  Ttl01
/// rev  4f2a1b0c9d8e7f60
/// document  a1b2c3d4e5f60718
/// ```
///
/// `rm` prints no `rev` line, because the node it names is gone and a revision for
/// it would be a plausible wrong answer. `override` names the *instance* it wrote
/// to rather than the descendant path it was given, because the instance is where
/// the override is stored and what `--rev` guards.
///
/// A `--dry-run` prints the same report between a marker and the findings it would
/// introduce, and neither revision line — for `rm`'s reason, doubled: the file is still
/// at the revision it had, and the one this edit would have made names nothing.
///
/// ```text
/// dry run  nothing written
/// Canvas/Cards/First  Cd101
/// warning clipped  Canvas/Cards/First (Cd101)  0,0 900×60 sits partly outside Cards …
/// ```
///
/// This is a plain data value: the `woodcase` CLI renders it as text or `--json`, and
/// a library caller — the scripting host's `doc.set`, `doc.add` and friends — gets the
/// same struct back rather than a string to reparse.
public struct WriteReport: Friendly {
    /// Creates a report.
    ///
    /// - Parameters:
    ///   - created: The subtrees the verb made, or empty for a verb that made none.
    ///   - path: The full name path of the node the verb acted on.
    ///   - id: That node's id.
    ///   - nodeRevision: That node's revision after the edit, or `nil` when it no
    ///     longer exists.
    ///   - documentRevision: The document's revision after the edit.
    ///   - warnings: Non-fatal things the write is telling the caller about — today,
    ///     the artboards it left overlapping. Empty for the ordinary write.
    ///   - node: The node as the write left it, for a caller that diffs it itself.
    ///     `--json` only; the text form never prints it.
    ///   - divergences: How the result differs from the write as it was asked for.
    ///     Empty for the ordinary write, which is what keeps the answer terse.
    ///   - dryRun: Whether this was a rehearsal. A rehearsal drops both revisions —
    ///     the file is still at the one it had, and the one this edit would have made
    ///     names nothing — and gains the marker and the findings.
    ///   - lint: The findings the write would introduce, from ``LintPreview``. Only a
    ///     dry run has any.
    public init(
        created: [CreatedNode] = [],
        path: String? = nil,
        id: String? = nil,
        nodeRevision: String? = nil,
        documentRevision: String,
        warnings: [String] = [],
        node: PenNode? = nil,
        divergences: [WriteDivergence] = [],
        dryRun: Bool = false,
        lint: [LintFinding] = []
    ) {
        self.created = created.isEmpty ? nil : created
        self.path = path
        self.id = id
        self.nodeRevision = dryRun ? nil : nodeRevision
        self.documentRevision = dryRun ? nil : documentRevision
        self.warnings = warnings.isEmpty ? nil : warnings
        self.node = node
        self.divergences = divergences.isEmpty ? nil : divergences
        self.dryRun = dryRun ? true : nil
        self.lint = dryRun ? lint : nil
    }

    /// The subtrees the verb made, or `nil` for a verb that made none.
    public let created: [CreatedNode]?

    /// The full name path of the node the verb acted on.
    ///
    /// For a write whose subject is not a node — a variable, a theme axis — this is the
    /// name that was written, and ``id`` is `nil`. A transcript line has to be able to
    /// say *which* variable moved, and a report with nothing but a document revision
    /// would read the same for every one of them.
    public let path: String?

    /// That node's id.
    public let id: String?

    /// That node's revision after the edit, or `nil` when it no longer exists.
    public let nodeRevision: String?

    /// The document's revision after the edit, or `nil` for a dry run — which made no
    /// revision, and leaves the file at the one it already had.
    public let documentRevision: String?

    /// What the write wants the caller to read but did not fail over, or `nil` when
    /// there is nothing — the same shape ``created`` uses, so a clean write's JSON
    /// carries no empty key.
    ///
    /// The lines are already whole sentences, in the form `lint` prints a finding, so a
    /// caller can show them without knowing what produced them. They are on standard
    /// error as well: stdout is the answer, and a warning is not part of it.
    public let warnings: [String]?

    /// The node as the write left it, or `nil` when it no longer exists and for the
    /// verbs that answer with a whole created tree instead.
    ///
    /// Carried for `--json` only — a caller that would rather diff the node than
    /// re-read it — so the text form is unchanged by its presence. It is the stored
    /// node, children stripped, which is the shape `woodcase get` prints.
    public let node: PenNode?

    /// How the result differs from the write as it was asked for, or `nil` when it does
    /// not — the ordinary write, which stays terse. See ``WriteDivergence``.
    public let divergences: [WriteDivergence]?

    /// `true` when nothing was written, `nil` when something was.
    ///
    /// `nil` rather than `false` so a real write's `--json` is exactly the bytes it was
    /// before `--dry-run` existed.
    public let dryRun: Bool?

    /// The lint findings the write would introduce, or `nil` for a real write.
    ///
    /// The *new* ones only — see ``LintPreview`` — so a file that already lints dirty
    /// does not bury what this write is about to do to it.
    public let lint: [LintFinding]?
}
