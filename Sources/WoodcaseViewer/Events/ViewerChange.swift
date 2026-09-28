//
//  ViewerChange.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// A watched file changed — the payload of a `change` event.
///
/// It carries everything the page needs to refresh without asking a second question:
/// which file, which artboards to re-request, the new document revision, and — when the
/// write can be attributed — who did it and which nodes they touched.
///
/// ## Attribution is best-effort, by design
///
/// The watcher sees the write; the activity log explains it. They arrive in that order
/// and a moment apart, so a change is published with whatever the log has said by then.
/// A file saved or edited by any tool that does not log has ``identity``
/// `nil` and empty ``nodes`` — which is the truth, not a gap: nobody claimed it.
public struct ViewerChange: Friendly {
    /// Creates a change.
    ///
    /// - Parameters:
    ///   - file: The file's ``ViewerFile/id``.
    ///   - path: The file's absolute, canonical path.
    ///   - name: The file's name without its extension.
    ///   - revision: The document's revision after the change.
    ///   - artboards: The ids of the artboards the viewer re-rendered.
    ///   - changedArtboards: The ids of the artboards the edit actually touched.
    ///   - time: When the change was published.
    ///   - identity: Who made the edit, when the log says.
    ///   - op: The verb the log recorded, when it says.
    ///   - nodes: The node ids the edit touched.
    ///   - paths: Those nodes' name paths, in the same order.
    public init(
        file: String,
        path: String,
        name: String,
        revision: String,
        artboards: [String],
        changedArtboards: [String] = [],
        time: Date,
        identity: String? = nil,
        op: ActivityEvent.Kind? = nil,
        nodes: [String] = [],
        paths: [String] = []
    ) {
        self.file = file
        self.path = path
        self.name = name
        self.revision = revision
        self.artboards = artboards
        self.changedArtboards = changedArtboards
        self.time = time
        self.identity = identity
        self.op = op
        self.nodes = nodes
        self.paths = paths
    }

    /// The file's id, as it appears in every URL.
    public let file: String

    /// The file's absolute, canonical path.
    public let path: String

    /// The file's name without its extension.
    public let name: String

    /// The document's revision after the change — the same string
    /// ``EditableDocument/documentRevision`` and the activity log carry.
    public let revision: String

    /// The ids of the artboards the viewer re-rendered, so the page knows which images
    /// to re-request. Empty when the file could not be read at all.
    public let artboards: [String]

    /// The ids of the artboards this edit actually touched — where the changed nodes
    /// live, as ``PreparedDocument/artboardIDs(containing:)`` reads them off the settled
    /// tree.
    ///
    /// A subset of ``artboards``, and a different question: that one says what to
    /// re-request, this one says *where the news is*. It is what a page following an
    /// identity navigates to, and what puts an unread dot on an artboard nobody is
    /// looking at. Empty for a write nobody logged, because an unattributed change names
    /// no nodes and so points at no artboard in particular.
    public let changedArtboards: [String]

    /// When the change was published.
    public let time: Date

    /// Who made the edit, when a log event matched the write.
    public let identity: String?

    /// The verb the log recorded, when one matched.
    public let op: ActivityEvent.Kind?

    /// The node ids the edit touched, from the matched events.
    public let nodes: [String]

    /// Those nodes' name paths, in the same order as ``nodes``.
    public let paths: [String]

    /// The change a set of matched log events describes.
    ///
    /// - Parameters:
    ///   - file: The file that changed.
    ///   - revision: Its revision after the change.
    ///   - artboards: The artboards re-rendered.
    ///   - changedArtboards: The artboards the edit touched, from the settled tree.
    ///   - events: The log events that explain the write, oldest first. Their node ids
    ///     and paths are unioned, keeping order and dropping repeats; the identity and
    ///     verb come from the newest, because that is the edit that left the file in
    ///     the state now on disk.
    ///   - time: When the change was published.
    /// - Returns: The change to publish.
    public static func of(
        file: ViewerFile,
        revision: String,
        artboards: [String],
        changedArtboards: [String] = [],
        events: [ActivityEvent],
        time: Date = Date()
    ) -> ViewerChange {
        var nodes: [String] = []
        var paths: [String] = []
        for event in events {
            for (index, node) in event.nodes.enumerated() where !nodes.contains(node) {
                nodes.append(node)
                paths.append(index < event.paths.count ? event.paths[index] : node)
            }
        }
        return ViewerChange(
            file: file.id,
            path: file.path,
            name: file.name,
            revision: revision,
            artboards: artboards,
            changedArtboards: changedArtboards,
            time: time,
            identity: events.last?.identity,
            op: events.last?.op,
            nodes: nodes,
            paths: paths
        )
    }
}
