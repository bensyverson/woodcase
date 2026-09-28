//
//  PageData.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// The reads every page and every JSON endpoint share, in one place.
///
/// A page component is a pure function of its props; this is where those props come
/// from. Keeping the gathering here rather than in each handler is what lets `GET /files`
/// and the dashboard page report the same thing by construction — they call the same
/// function — instead of by two implementations that agree today.
public enum PageData {
    /// How many activity events a page shows when nothing says otherwise.
    public static let activityLimit = 50

    /// Every file being served, with its artboards and its last recorded change.
    ///
    /// A file that cannot be parsed is listed with its error rather than left out: a
    /// dashboard that silently drops a broken file reports that all is well.
    ///
    /// - Parameter context: The server's file index, render cache and log.
    /// - Returns: The report `GET /files` serves and the dashboard renders.
    public static func files(_ context: ViewerContext) async -> FileListReport {
        var summaries: [FileListReport.Summary] = []

        for file in await context.files.files {
            let lastChange = context.tail(count: 1, file: file.url).last
                .map(FileListReport.LastChange.init)
            do {
                let prepared = try await context.renders.prepared(file)
                summaries.append(FileListReport.Summary(
                    id: file.id,
                    path: file.path,
                    name: file.name,
                    revision: prepared.revision,
                    artboards: prepared.artboards,
                    lastChange: lastChange,
                    error: nil
                ))
            } catch {
                summaries.append(FileListReport.Summary(
                    id: file.id,
                    path: file.path,
                    name: file.name,
                    revision: nil,
                    artboards: [],
                    lastChange: lastChange,
                    error: String(describing: error)
                ))
            }
        }
        return FileListReport(files: summaries)
    }

    /// Who has been writing, folded out of the log the same way the event stream folds
    /// it — so the page a browser loads and the `presence` event it then receives cannot
    /// disagree about who is here or what order they arrived in.
    ///
    /// - Parameter context: The server's log and file index.
    /// - Returns: The identities, in order of first appearance.
    public static func presence(_ context: ViewerContext) async -> [ViewerPresence.Identity] {
        var tracker = PresenceTracker()
        for event in context.allEvents() {
            let fileID = await context.files.file(at: URL(fileURLWithPath: event.file))?.id
            tracker.record(event, fileID: fileID)
        }
        return tracker.snapshot().identities
    }

    /// The most recent events, oldest first.
    ///
    /// - Parameters:
    ///   - context: The server's log.
    ///   - file: The file to filter to, or `nil` for every file.
    ///   - limit: How many to read.
    /// - Returns: The events, or none when the log cannot be read — an unreadable log
    ///   makes the feed empty, never the page an error.
    public static func events(
        _ context: ViewerContext,
        file: URL? = nil,
        limit: Int = activityLimit
    ) -> [ActivityEvent] {
        context.tail(count: limit, file: file)
    }

    /// Where the activity logs live, for a header line.
    ///
    /// - Parameter context: The server's logs.
    /// - Returns: The paths, comma-separated, each with the home directory abbreviated
    ///   to `~`. Serving one project — the ordinary case — that is one path.
    public static func logPath(_ context: ViewerContext) -> String {
        context.logs.map { abbreviate($0.fileURL.path) }.joined(separator: ", ")
    }

    /// A path with the user's home directory written as `~`.
    ///
    /// - Parameter path: The absolute path.
    /// - Returns: The abbreviated path.
    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        guard !home.isEmpty, path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
