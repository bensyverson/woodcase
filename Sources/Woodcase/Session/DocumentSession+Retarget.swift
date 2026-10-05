//
//  DocumentSession+Retarget.swift
//  Woodcase
//

import Foundation

public extension DocumentSession {
    /// Points the session at its document's new file, keeping everything else.
    ///
    /// Call it when the app's document gets a new URL: the first save of an untitled
    /// document, Save As, Rename, Move To, a move in the Finder, a renamed bundle. The
    /// session stays the same session — its undo and redo stacks, its ledger, its
    /// sequence and what it knows of the file's contents are untouched — and only the
    /// file its activity rows name changes. It does no I/O: moving or writing the file
    /// is the caller's, before or after.
    ///
    /// What follows a move is decided by the file, not the session (see <doc:Session>
    /// under "Saving from an app"):
    ///
    /// - **The log.** A save resolves its log from the URL it is given, so the next save
    ///   lands in the new file's log. A bundle's log is inside the bundle and moves with
    ///   it. A bare `.pen` that moves to another log root — another repository, a folder
    ///   outside one — starts its rows in that root's log; the old log keeps the rows
    ///   it has, under the old path.
    /// - **Unsaved changes** made before the move are logged under the new file when
    ///   they are saved: ``PenFileTransaction/save(_:changes:to:log:timeout:)`` names
    ///   the file it writes in every row.
    /// - **The synced revision and merge base** stay as they are. A move does not change
    ///   the file's bytes; a first save or Save As writes the snapshot and reports it
    ///   with ``noteSynced(_:)`` as any save does.
    ///
    /// ```swift
    /// let snapshot = session.snapshot()
    /// try await PenFileTransaction.create(at: url, document: snapshot.document, identity: author.name)
    /// session.retarget(to: url)
    /// session.noteSynced(snapshot)
    /// ```
    ///
    /// - Parameter file: The document's new `.pen` file or `.umbra` bundle.
    func retarget(to file: URL) {
        self.file = file
    }
}
