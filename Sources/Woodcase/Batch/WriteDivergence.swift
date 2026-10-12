//
//  WriteDivergence.swift
//  Woodcase
//

import Foundation

/// One way a write's result differs from the write that was asked for.
///
/// Every write line reports three-way: **requested → applied-as → the line's
/// ``BatchLineStatus``**. When all three agree there is nothing here and the report is
/// exactly the terse line it has always been; a divergence is the only thing that earns
/// extra output.
///
/// What a divergence says is the *interpreted* meaning of what was stored, never a raw
/// echo of the stored form. A plain echo-back is proven insufficient: `get` faithfully
/// confirmed a swallowed `rootOverrides` key back to the very agent that wrote it, and
/// the mistake still surfaced in pixels a day later. So ``note`` is a whole sentence in
/// the form `lint` prints a finding — what the write now means, and the remedy where
/// there is one — while ``requested`` and ``applied`` carry the two ends of the
/// comparison for a caller that would rather branch than read.
///
/// ```text
/// line 0  applied  Title
///         kind.content resolved $v-muted as a reference to the color variable v-muted — write \$v-muted for the literal
/// ```
///
/// Divergences are produced while a line is planned, from the operation and the
/// document as it stands, and are reported only on a line that went on to apply — a
/// line that failed changed nothing, so it has nothing to diverge from.
///
/// ## Two tiers
///
/// ``severity`` splits them. A ``Severity/divergence`` is the sentence above: what was
/// stored means something other than the plain reading of the write. A
/// ``Severity/note`` is the opposite claim — the write means exactly what it looks
/// like, and one fact about it is worth stating — and ``reportLine`` marks it so it
/// cannot be read as a reprimand for using a feature.
public struct WriteDivergence: Friendly {
    /// The families of divergence a write can report.
    ///
    /// A caller branching on the answer reads this rather than parsing ``note``.
    public enum Kind: String, Friendly, CaseIterable {
        /// A `$name` was stored as a reference to a variable the document defines,
        /// where the same characters could have been meant as a literal.
        case variableReference

        /// A value changed type on the way in — today, a number written to a property
        /// that takes text, stored as the text it spells.
        case coercion

        /// An override named a property the component's definition does not set, so it
        /// adds a value rather than replacing one — or one the node's type has no room
        /// for at all, which nothing will ever read.
        ///
        /// The two read differently, and ``WriteDivergence/severity`` is what tells
        /// them apart: adding a property is a ``Severity/note``, and a key nothing will
        /// read is a ``Severity/divergence``.
        case unsetOverrideProperty

        /// An override wrote null over a value the component's definition sets, taking
        /// that value away rather than removing the override.
        case nullOverride

        /// An override carried a `type` key, which turns the whole entry from a patch
        /// into a replacement of the node.
        case overrideReplacesNode

        /// A key named a parameter the component publishes *and* a property the node
        /// already has, so the property was written and the parameter was not.
        case shadowedParameter

        /// A root-level node was given coordinates it did not ask for, so that it does
        /// not land on top of an artboard already there.
        case rootPlacement

        /// A delete detached the component's live instances into standalone copies
        /// before removing it.
        case detachedInstances

        /// A `var` line carried a themed value: several values on one line, one per
        /// theme option, plus whatever axes the document had to grow to hold them.
        case themedVariable

        /// An override addressed content an instance wrote into its own slot, so it was
        /// written into that slot's `children` — the only place Pen reads it — rather
        /// than as a `descendants` key Pen would drop. ``WriteDivergence/applied`` is the
        /// slot's name path.
        case slotFillRewrite
    }

    /// How loudly a report says it.
    ///
    /// Both tiers print, and both are on stdout — the difference is what the sentence
    /// is claiming. This is what a caller branches on when it wants to act on the
    /// warnings and merely relay the rest, and what ``reportLine`` renders.
    ///
    /// The tier exists because one entry on the list is not a warning at all: adding a
    /// property the component leaves unset (`enabled=false` on an instance's
    /// descendant) is *how* a variant differs from its component. Reported as a
    /// divergence it read as a reprimand for using the feature, which is the same
    /// mistake the `children` message made about slots.
    public enum Severity: String, Friendly, CaseIterable {
        /// The stored form means something other than the plain reading of the write.
        case divergence

        /// The write means exactly what it looks like, and one fact about it is worth
        /// stating.
        case note
    }

    /// Creates a divergence.
    ///
    /// - Parameters:
    ///   - kind: Which family it belongs to.
    ///   - severity: Whether the sentence is a divergence or a note. Defaults to
    ///     ``Severity/divergence``, which is what every family but one always is.
    ///   - target: The property path, raw override key or node name it is about.
    ///   - requested: The interpreted form of what the caller asked for.
    ///   - applied: The interpreted form of what the document now holds.
    ///   - note: One whole sentence: what the write means, and the remedy if any.
    public init(
        kind: Kind,
        severity: Severity = .divergence,
        target: String,
        requested: String,
        applied: String,
        note: String
    ) {
        self.kind = kind
        self.severity = severity
        self.target = target
        self.requested = requested
        self.applied = applied
        self.note = note
    }

    /// Which family this divergence belongs to.
    public var kind: Kind

    /// Whether the sentence is a divergence or a note.
    public var severity: Severity

    /// The property path, raw override key or node name the divergence is about.
    public var target: String

    /// The interpreted form of what was asked for.
    public var requested: String

    /// The interpreted form of what the document now holds.
    public var applied: String

    /// One whole sentence saying what the write means and, where there is one, the
    /// remedy — the only part a report prints.
    public var note: String

    /// The line a report prints: the sentence, marked when that is all it is.
    ///
    /// A ``Severity/divergence`` is the bare sentence, byte for byte what it has always
    /// been. A ``Severity/note`` carries a `note` marker in the house's `key  value`
    /// shape — the same reason ``LintFinding``'s line leads with its severity — so a
    /// reader scanning a write's answer can tell at the left margin which sentences are
    /// telling them something is off and which are telling them what they did.
    public var reportLine: String {
        severity == .note ? "note  \(note)" : note
    }
}
