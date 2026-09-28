//
//  LintPreview.swift
//  Woodcase
//

import Foundation

/// The lint findings an edit would *introduce*, taken across it.
///
/// A dry run's most valuable sentence is the one no read can produce: "this write would
/// leave `Cards/First` hanging outside its parent." Running ``DocumentLinter`` over the
/// settled result would say that — buried in every finding the file already had, which
/// on a real design system is hundreds. So a preview is a difference, exactly as
/// overlapping artboards are reported as a difference: snapshot before the edit, lint
/// again after, and report what is new.
///
/// ```swift
/// let preview = try LintPreview(of: document)
/// try recorder.apply(edit)
/// let introduced = try preview.introduced(in: document)
/// ```
///
/// It lives beside ``PenFileTransaction`` rather than with the linter because it is a
/// property of a *write* — the thing being previewed — not a check of its own. The
/// checks are ``DocumentLinter``'s, unchanged and unfiltered.
///
/// ## What counts as the same finding
///
/// A check and the node it fired on, not the sentence. Almost every write moves a
/// measurement — set a heading's text and the frame below it shifts by three points —
/// and a finding whose numbers changed is not a new problem. So a node that already
/// tripped `clipped` still trips it, however differently the sentence reads, and a node
/// that has just started tripping it is the answer this exists to give. A finding about
/// the document rather than a node names no node, so those compare by their sentence.
///
/// The cost is that a *different* fault of the same check on the same node is not
/// reported. The node was already failing that check, and `woodcase lint` is one command
/// away for the whole picture.
///
/// ## What it does not see
///
/// Nothing is passed for ``DocumentLinter``'s `diagnostics`, so the pipeline's own
/// warnings — the version gate's, the legacy migrator's — are not reported. They are
/// properties of the bytes on disk, identical on both sides of the edit, and a
/// difference would drop them anyway. `woodcase lint` is where they are read.
public struct LintPreview {
    /// Lints `document` as it stands, to compare a later state against.
    ///
    /// Call this *before* the edit, inside the transaction, so the snapshot describes
    /// the same bytes the edit is about to change.
    ///
    /// - Parameters:
    ///   - document: The document as it is before the edit.
    ///   - theme: Theme axes to pin for variable resolution. `nil` — the default — uses
    ///     the document's own default theme, which is the theme a write is judged in.
    /// - Throws: Whatever ``DocumentLinter/findings(in:root:theme:diagnostics:)`` throws.
    public init(of document: EditableDocument, theme: [String: String]? = nil) throws {
        self.theme = theme
        before = try Set(DocumentLinter.findings(in: document, theme: theme).map(Signature.init))
    }

    /// The theme the snapshot was taken in, and the one the comparison uses.
    private let theme: [String: String]?

    /// What the document was already failing before the edit.
    private let before: Set<Signature>

    /// The findings `document` has now that it did not have when the snapshot was taken.
    ///
    /// - Parameter document: The same document, after the edit.
    /// - Returns: The new findings, in ``DocumentLinter``'s own document order. Empty
    ///   when the edit broke nothing.
    /// - Throws: Whatever ``DocumentLinter/findings(in:root:theme:diagnostics:)`` throws.
    public func introduced(in document: EditableDocument) throws -> [LintFinding] {
        try DocumentLinter.findings(in: document, theme: theme)
            .filter { !before.contains(Signature($0)) }
    }

    /// What makes two findings across an edit the same finding.
    private struct Signature: Hashable {
        init(_ finding: LintFinding) {
            check = finding.check
            subject = finding.nodeID ?? finding.message
        }

        /// The check that fired.
        let check: LintCheck

        /// The node it is about — or, for a document-level finding that names none, its
        /// sentence, which is all there is to tell two of those apart.
        let subject: String
    }
}

public extension WriteEffect {
    /// The snapshot a dry run needs, or `nil` for a write that is really going to happen.
    ///
    /// This is the one line every verb adds before its edit; the matching
    /// ``LintPreview/introduced(in:)`` is the one it adds after. A committing write
    /// lints nothing, so it costs the ordinary path nothing.
    ///
    /// - Parameters:
    ///   - document: The document as it is before the edit.
    ///   - theme: Theme axes to pin for variable resolution, as ``LintPreview`` takes them.
    /// - Returns: A snapshot for ``dryRun``, `nil` for ``commit``.
    /// - Throws: Whatever ``LintPreview/init(of:theme:)`` throws.
    func preview(of document: EditableDocument, theme: [String: String]? = nil) throws -> LintPreview? {
        self == .dryRun ? try LintPreview(of: document, theme: theme) : nil
    }
}
