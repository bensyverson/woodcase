//
//  ChangeKey.swift
//  Woodcase
//

import Foundation

/// The smallest piece of a document one edit can change and another can contest.
///
/// A document session records who last wrote each key, and when, so an undo can tell
/// whether undoing would overwrite another author's later work. Keys are as fine as
/// the edit vocabulary allows: one property path on one node, one key of one override
/// entry, a node's place among its siblings, a node's existence. Two edits contest
/// each other exactly when their keys meet.
///
/// Property paths are the ``NodePropertyCodec`` vocabulary — `"common.name"`,
/// `"kind.width"`, a node's unmodeled `"extras.<key>"` — and the one whole-kind key
/// `"kind"`, which a change of node type writes. Document-level fields (fonts, version,
/// the file token, the root's unmodeled keys) are ``document(_:)``.
///
/// ```swift
/// let keys = try ChangeKey.keys(of: operation, in: document)
/// // [.property(node: "r1", path: "kind.width")]
/// ```
public enum ChangeKey: Friendly {
    /// One property of one node, addressed by property path.
    case property(node: String, path: String)
    /// One key of one descendant's override entry on a `ref` node.
    case override(ref: String, descendant: String, key: String)
    /// One root-override key on a `ref` node.
    case rootOverride(ref: String, key: String)
    /// Where a node sits: its parent and its place among its siblings.
    case placement(node: String)
    /// Whether a node exists at all.
    case existence(node: String)
    /// One document variable.
    case variable(name: String)
    /// One import alias.
    case importAlias(String)
    /// One theme axis.
    case themeAxis(String)
    /// One document-level field, such as `"fonts"` or a root `"extras.<key>"`.
    case document(String)

    /// The path a change of node type writes: the whole kind payload at once.
    public static let wholeKindPath = "kind"
}
