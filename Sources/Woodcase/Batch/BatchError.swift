//
//  BatchError.swift
//  Woodcase
//

import Foundation

/// A failure in the batch grammar itself, as opposed to one the document raised.
///
/// ``EditingError`` covers everything an edit can be refused for. These are the
/// failures that happen *before* an edit exists: a line that will not decode, a
/// subtree that cannot be addressed once inserted, an address pointing at the
/// wrong kind of place for the verb that used it, and a ``BatchGuard`` whose premise
/// the transaction found already broken at the door.
public enum BatchError: Error, Equatable, Sendable {
    /// A line of the batch file would not decode.
    ///
    /// `line` is 1-based, matching what an editor shows.
    case malformedLine(line: Int, reason: String)

    /// A row of a `cp`'s copy list would not decode as a JSON object of properties.
    ///
    /// `row` is 1-based, matching what an editor shows and what the rest of a `cp`'s
    /// refusals count in.
    case malformedRow(row: Int, reason: String)

    /// A `cp` property key names a path that is not inside the node being copied.
    ///
    /// Checked against the *source*, before anything is written: a copy is name-for-name
    /// the source it came from, so a path that names nothing there will name nothing in
    /// the copy either — and saying so first is what lets a whole `--each` be refused
    /// with the file untouched. `row` is the 1-based row it came from, or `nil` for a
    /// single copy.
    case copyPathNotInSource(row: Int?, key: String, source: String)

    /// A key names a parameter the component publishes, but the path that parameter
    /// declares names nothing inside the component.
    ///
    /// The declaration is `common.metadata._props`, and a stale one is the failure
    /// worth catching early: the key is meaningful — the component really does publish
    /// that name — so storing it as an ordinary override would apply, read back, and
    /// draw nothing. Raised before anything is written, naming both halves of the
    /// declaration.
    case parameterPathNotFound(name: String, path: String, component: String)

    /// A `cp` was given a copy list with no rows in it.
    ///
    /// Copying nothing is never what a caller meant, and a silent success would read as
    /// one — an empty rows file is usually a generator that produced nothing.
    case emptyCopyRows

    /// A `cp` line declares a `tag` and an `each` at once.
    ///
    /// A tag names one node for later lines to address; `each` makes several, so there
    /// is no one node for the tag to be.
    case copyTagWithRows(tag: String)

    /// A node in an `add` subtree has no name, so nothing could address it later.
    ///
    /// `type` is the node's .pen type name; `locator` is the path of names down
    /// to it from the subtree's root, so the caller can find it in their JSON.
    case unnamedNode(type: String, locator: String)

    /// A `ref` in an authored subtree carries a literal `rootOverrides` key.
    ///
    /// The format has no such key: a ref writes its root overrides as its own top-level
    /// keys, so the decoder sweeps every non-reserved key into `rootOverrides` — and a
    /// literal one lands there as an override *named* `rootOverrides`, patching a
    /// property no node has. It applies, it reads back, and it does nothing, which is
    /// exactly the failure worth refusing.
    ///
    /// `locator` is the path of names down to the offending ref from the subtree's root.
    case literalRootOverridesKey(locator: String)

    /// A `replace` subtree wrote a root `id` that is not the target's.
    ///
    /// The target's id is kept whatever the subtree says, so a different one can only
    /// mean the caller expected something the verb does not do. Refused rather than
    /// silently ignored.
    case replacementIDMismatch(address: String, supplied: String, kept: String)

    /// A `set` was addressed at a node inside a component instance.
    ///
    /// Such a node has no storage of its own, so the edit has to be written as
    /// an override on the instance instead.
    case setInsideInstance(address: String, instancePath: String)

    /// A structural verb — `rm`, `mv`, `cp` — was addressed at a child an instance
    /// injected into a slot.
    ///
    /// Such a node is one entry in the `children` value the instance wrote onto the
    /// slot frame, not a node with a place in any tree, so it is added, removed and
    /// reordered by writing that list again.
    case structureInsideSlot(address: String, slotPath: String)

    /// An `override` was addressed at a node that is neither a component instance nor
    /// inside one.
    case overrideOutsideInstance(address: String, path: String)

    /// An `override` line carried neither a property to write nor a key to unset.
    ///
    /// Applied, it would change nothing and report success — the silent no-op an
    /// address typo or a dropped field produces, and the one a caller cannot see.
    case overrideWithoutProperties(address: String)

    /// A node was addressed as a parent, but it is inside a component instance.
    ///
    /// A component's children belong to the component; adding to an instance
    /// would have nowhere to be stored.
    case parentInsideInstance(address: String, instancePath: String)

    /// The document changed since the caller last read it.
    ///
    /// The document-wide counterpart of
    /// ``EditingError/revisionConflict(nodeID:expected:actual:)``, raised for a
    /// root-level line whose `rev` guards the whole document.
    case documentRevisionConflict(expected: String, actual: String)

    /// A ``BatchGuard``'s premise no longer holds: someone else moved what the caller
    /// read.
    ///
    /// Raised at transaction entry, so nothing has been applied and nothing will be.
    /// `node` is the pinned node named the way a message names one, and `address` is
    /// what to hand a command to read it again — `nil` for a document-wide pin, which
    /// no single address names. `writer` is who moved it, when the activity log says:
    /// `nil` when it cannot say, and ``ActivityEvent/unattributed`` (the empty string)
    /// for a write that claimed no name.
    case guardConflict(node: String, address: String?, expected: String, actual: String, writer: String?)

    /// A ``BatchGuard`` names a node the document does not hold.
    ///
    /// Either it was removed since the caller read it — the world changing underneath,
    /// which is what a guard exists to catch — or the address is wrong. The remedy is
    /// the same for both.
    case guardNodeMissing(node: String)

    /// A ``BatchGuard`` names a batch tag.
    ///
    /// Guards are checked before any line runs, so nothing a line creates exists yet.
    case guardOnTag(tag: String)

    /// A bare ``BatchGuard`` on a line that acts on no node — a variable, a theme axis
    /// — so there is nothing for it to pin.
    case guardWithoutTarget(verb: String)
}
