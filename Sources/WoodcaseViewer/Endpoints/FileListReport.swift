//
//  FileListReport.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// The body of `GET /files`: every file the viewer is serving, with its artboards and
/// its last recorded edit.
///
/// This is the dashboard's data and the first request any consumer makes — the ids in it
/// are what every other URL is built from.
///
/// A file that cannot be parsed is listed with ``Summary/error`` set rather than left
/// out: a dashboard that silently drops a broken file tells you nothing is wrong.
public struct FileListReport: Friendly {
    /// Creates a report.
    ///
    /// - Parameter files: The files, in the order they are served.
    public init(files: [Summary]) {
        self.files = files
    }

    /// One file.
    public struct Summary: Friendly {
        /// Creates a summary.
        ///
        /// - Parameters:
        ///   - id: The file's id, as it appears in every URL.
        ///   - path: Its absolute, canonical path.
        ///   - name: Its name without the extension.
        ///   - revision: The document's revision, or `nil` if it could not be read.
        ///   - artboards: Its top-level frames, with settled sizes.
        ///   - lastChange: The most recent activity-log event for it, if any.
        ///   - error: Why it could not be read, when it could not.
        public init(
            id: String,
            path: String,
            name: String,
            revision: String?,
            artboards: [Artboard],
            lastChange: LastChange?,
            error: String?
        ) {
            self.id = id
            self.path = path
            self.name = name
            self.revision = revision
            self.artboards = artboards
            self.lastChange = lastChange
            self.error = error
        }

        /// The file's id, as it appears in every URL.
        public let id: String
        /// Its absolute, canonical path.
        public let path: String
        /// Its name without the extension.
        public let name: String
        /// The document's revision, or `nil` if it could not be read.
        public let revision: String?
        /// Its top-level frames, with settled sizes. Empty when it could not be read.
        public let artboards: [Artboard]
        /// The most recent activity-log event for it, if any.
        public let lastChange: LastChange?
        /// Why the file could not be read, when it could not.
        public let error: String?

        /// The artboard that stands for this file — the one a dashboard card renders as
        /// its thumbnail. `nil` when the file has no artboards, which includes every
        /// file that could not be read.
        ///
        /// Derived rather than stored, so the report's JSON keeps one spelling of the
        /// artboards and a consumer that wants the cover applies the same rule the page
        /// does — see ``Artboard/cover(of:)``.
        public var cover: Artboard? {
            Artboard.cover(of: artboards)
        }
    }

    /// The last recorded edit to a file.
    public struct LastChange: Friendly {
        /// Creates a last change.
        ///
        /// - Parameters:
        ///   - time: When it happened.
        ///   - identity: Who made it.
        ///   - op: The verb it was recorded as.
        ///   - nodes: The node ids it touched.
        ///   - paths: Those nodes' name paths.
        public init(time: Date, identity: String, op: ActivityEvent.Kind, nodes: [String], paths: [String]) {
            self.time = time
            self.identity = identity
            self.op = op
            self.nodes = nodes
            self.paths = paths
        }

        /// When it happened.
        public let time: Date
        /// Who made it — the `--as` name.
        public let identity: String
        /// The verb it was recorded as.
        public let op: ActivityEvent.Kind
        /// The node ids it touched.
        public let nodes: [String]
        /// Those nodes' name paths, in the same order.
        public let paths: [String]

        /// The last change an activity event describes.
        ///
        /// - Parameter event: The event.
        public init(_ event: ActivityEvent) {
            self.init(
                time: event.time,
                identity: event.identity,
                op: event.op,
                nodes: event.nodes,
                paths: event.paths
            )
        }
    }

    /// The files, in the order they are served.
    public let files: [Summary]
}
