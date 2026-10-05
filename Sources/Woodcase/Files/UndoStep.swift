//
//  UndoStep.swift
//  Woodcase
//

import Foundation

/// What an undo does about one step of the activity log, scanning the log's tail
/// newest-first.
///
/// This enum *is* the undo rule; ``ActivityUndo`` around it only loops, and the CLI
/// around that only turns a refusal into a sentence and an exit code. These can be
/// true of the next step down:
///
/// | Step | Meaning |
/// |---|---|
/// | ``undo(_:)`` | The file is in exactly the state this step produced. Replay its inverse. |
/// | ``stepOverUndo`` | The step is itself an undo. Never replayed — that would be a redo. |
/// | ``stepOverUndone`` | An earlier undo already reversed this step. Keep looking. |
/// | ``blockedByOther(_:)`` | Somebody else edited later. Refuse, and name them. |
/// | ``blockedByStale(_:)`` | The file moved since this step, and no undo explains it. Refuse. |
/// | ``blockedByExternal(_:)`` | Somebody rewrote the file outside woodcase. There is no inverse to replay. Refuse. |
/// | ``stepOverRewrite`` | A `migrate` row: the bytes changed, the document did not. Pass over it. |
/// | ``stepOverMerge`` | A `merge` row: work folded into an app's save. Pass over it, for every identity. |
/// | ``reachedCreation`` | A `new` row: the file's history begins here. Stop. |
///
/// The decision is made on **one event**: the last event of the step. For
/// ``UndoUnit/event`` that is the only event there is; for ``UndoUnit/transaction`` it
/// is the newest event of the batch, which is the one whose revision the file holds and
/// whose identity the reader is being blocked by.
///
/// ## Why the revision check is not a guess
///
/// An ``ActivityEvent/revision`` is the document's revision *after* that operation, so
/// ``LogLineage/explains(_:at:)`` proves the file holds precisely the state the event
/// produced, and its ``ActivityEvent/inverse`` therefore restores precisely the state
/// before it. Nothing is inferred from timestamps or ordering.
///
/// Contiguity falls out of the same check: after step *k* is reversed, the document's
/// revision equals the last event's revision of step *k−1*, so the next iteration
/// matches only if *k−1* really is the edit that came before. A later edit by anyone
/// breaks the chain, which is what makes ``blockedByOther(_:)``, ``blockedByStale(_:)``
/// and ``blockedByExternal(_:)`` reachable at all.
///
/// ## The one heuristic, and why it stayed
///
/// ``stepOverUndone`` is not proved from the log's own text: once the scan has passed
/// an undo event, a candidate whose revision does not match is *taken* to be one that
/// undo reversed. The log records no link from an undo back to the event it reversed,
/// so the alternative would be to refuse every second `undo` on a file — an undo would
/// poison the tail forever.
///
/// It survives the arrival of ``ActivityEvent/Kind/external`` rather than being
/// replaced by it, because the two answer different questions. What the external row
/// *does* remove is the heuristic's cost: an edit made outside woodcase used to hide
/// behind it, surfacing as "nothing left to undo" on a file that had ever been undone.
/// Now every transaction records the outside edit it found, so the scan meets a row it
/// must refuse rather than a mismatch it may explain away — and the assumption is left
/// standing over the one case it was written for.
public enum UndoStep: Friendly {
    /// The file is in the state this step produced; replay its inverse.
    case undo(ActivityEvent)

    /// The step is an undo of something else. An undo steps over it rather than
    /// replaying it, because an undo's own inverse is a redo.
    case stepOverUndo

    /// An undo the scan already passed reversed this step; keep looking further back.
    case stepOverUndone

    /// Another identity edited after this point. Refuse, and name them.
    case blockedByOther(ActivityEvent)

    /// The file's revision does not match, and no undo accounts for the difference:
    /// something changed it outside the log. Refuse.
    case blockedByStale(ActivityEvent)

    /// The step is the record of an edit made outside woodcase. It has no inverse —
    /// nothing woodcase did can be replayed backwards — so the walk ends here.
    case blockedByExternal(ActivityEvent)

    /// The step rewrote the file's bytes without changing its document — a
    /// ``ActivityEvent/Kind/migrate``. There is nothing to reverse, and every edit
    /// before it is still exact against the document, so the walk passes over it
    /// whoever wrote it, and it does not count as a step.
    case stepOverRewrite

    /// The step is a ``ActivityEvent/Kind/merge`` row: work folded into a save that is
    /// nobody's command. The walk neither replays it nor stops at it, whoever wrote it,
    /// and it does not count as a step; see ``ActivityUndo`` for how the rows before
    /// it are judged.
    case stepOverMerge

    /// The step created the file — ``ActivityEvent/Kind/new``. Nothing before it is
    /// this file's history, so the walk ends here with nothing left to undo.
    case reachedCreation

    /// What the walk knows past a ``ActivityEvent/Kind/merge`` row, for judging the
    /// event below it.
    public struct Unfolded: Friendly {
        /// Creates the knowledge.
        ///
        /// - Parameters:
        ///   - revision: The document's revision with the folded-in work taken out.
        ///   - touchesFoldedWork: Whether the event's node is, or holds, a node the
        ///     folded-in work touched.
        public init(revision: String, touchesFoldedWork: Bool) {
            self.revision = revision
            self.touchesFoldedWork = touchesFoldedWork
        }

        /// The document's revision with the folded-in work taken out.
        public var revision: String

        /// Whether the event's node is, or holds, a node the folded-in work touched.
        public var touchesFoldedWork: Bool
    }

    /// Decides what to do about one step of the log.
    ///
    /// - Parameters:
    ///   - event: The step's last event, from the log's tail.
    ///   - currentRevision: The document's revision right now — after everything this
    ///     run has already reversed.
    ///   - identity: The `--as` name running the undo.
    ///   - allIdentities: Whether every identity's events are candidates, not only the
    ///     one running the undo. Undo events stay ``stepOverUndo`` either way, and an
    ///     external event stays ``blockedByExternal(_:)``.
    ///   - afterUndo: Whether the scan has already passed an undo event.
    ///   - unfolded: Once the scan has passed a ``ActivityEvent/Kind/merge`` row with an
    ///     inverse, the revision the document would have without the work that row
    ///     folded in, and whether this event's node holds any of that work; `nil`
    ///     otherwise. An event this revision explains is undone even though the
    ///     document's own revision no longer does — unless it would take the folded-in
    ///     work with it.
    /// - Returns: The step to take.
    public static func decide(
        _ event: ActivityEvent,
        currentRevision: String,
        identity: String,
        allIdentities: Bool,
        afterUndo: Bool,
        unfolded: Unfolded? = nil
    ) -> UndoStep {
        if event.op == .undo {
            return .stepOverUndo
        }
        // Nobody's command, whoever saved it: never replayed, never in the way.
        if event.op == .merge {
            return .stepOverMerge
        }
        // Neither is anybody's edit of the document: a migrate is transparent to what
        // came before it, and a new is where the file's history begins.
        if event.op == .migrate {
            return .stepOverRewrite
        }
        if event.op == .new {
            return .reachedCreation
        }
        // Before the identity check, because an external event is unattributed by
        // definition: blaming "" for getting in the way would be a worse sentence than
        // the true one, and --all must not make an inverse-less row look replayable.
        if event.op == .external {
            return .blockedByExternal(event)
        }
        // Identity is checked before the revision so that the refusal can name the
        // person who got in the way rather than only quoting two hashes.
        if !allIdentities, event.identity != identity {
            return .blockedByOther(event)
        }
        if LogLineage.explains(event, at: currentRevision) {
            return .undo(event)
        }
        if let unfolded, !unfolded.touchesFoldedWork, LogLineage.explains(event, at: unfolded.revision) {
            return .undo(event)
        }
        return afterUndo ? .stepOverUndone : .blockedByStale(event)
    }
}
