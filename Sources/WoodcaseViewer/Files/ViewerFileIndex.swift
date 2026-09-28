//
//  ViewerFileIndex.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// The set of files the viewer serves, and the id → file lookup every route uses.
///
/// `woodcase serve <file>…` names files explicitly; `woodcase serve` with none adopts
/// every .pen file the activity log has seen, which is the dashboard case — whatever
/// the agents in this session have been editing.
public actor ViewerFileIndex {
    /// Creates an index over the given files.
    ///
    /// - Parameter files: The .pen files to serve, in the order they should be listed.
    ///   Duplicates — including two spellings of one path — are collapsed.
    public init(files: [URL]) {
        wasGivenFiles = !files.isEmpty
        for file in files.map(ViewerFile.init(url:)) where byID[file.id] == nil {
            byID[file.id] = file
            ordered.append(file)
        }
    }

    /// Whether the caller named files, in which case the log adds none.
    private let wasGivenFiles: Bool

    /// The files, in the order they were added.
    private var ordered: [ViewerFile] = []

    /// The files by id.
    private var byID: [String: ViewerFile] = [:]

    /// The files being served, in order.
    public var files: [ViewerFile] {
        ordered
    }

    /// The file with an id.
    ///
    /// - Parameter id: The id from a URL.
    /// - Returns: The file, or `nil` if no watched file has that id.
    public func file(id: String) -> ViewerFile? {
        byID[id]
    }

    /// The file at a path, whatever spelling it arrives in.
    ///
    /// - Parameter url: The file's URL.
    /// - Returns: The file, or `nil` if it is not being served.
    public func file(at url: URL) -> ViewerFile? {
        byID[ViewerFile(url: url).id]
    }

    /// Adopts every .pen file the activity logs name, unless files were given explicitly.
    ///
    /// The history pass, run once at startup. ``adopt(_:)`` is its live counterpart: a
    /// file first named *after* the server started is adopted as the log names it, which
    /// is what makes an agent's `woodcase new` appear on an open dashboard. A file in a
    /// log that no longer exists is skipped: a dashboard listing a file it cannot open
    /// would be a plausible wrong answer. One log handed over twice adds its files once,
    /// because ``insert(_:)`` is by id.
    ///
    /// - Parameter logs: The logs to read, in the order their files should be listed.
    public func adoptFilesFromLogs(_ logs: [ActivityLog]) {
        guard !wasGivenFiles else { return }
        for log in logs {
            guard let page = try? ActivityReader(log: log).read() else { continue }
            for event in page.events {
                adopt(URL(fileURLWithPath: event.file))
            }
        }
    }

    /// Adopts one file the log has just named, if it is new and there is one to adopt.
    ///
    /// The dashboard serves "whatever the agents in this session have been editing", and
    /// an agent creating a file mid-session is that case exactly — so the log's live tail
    /// inserts as well as the startup read. Three things refuse: files named on the
    /// command line (that list is the whole list, on purpose), a file already indexed,
    /// and a path with nothing on disk.
    ///
    /// - Parameter url: The file the log named.
    /// - Returns: The newly indexed file, or `nil` if nothing was added — which is the
    ///   caller's signal to watch and warm it, or not to.
    @discardableResult
    public func adopt(_ url: URL) -> ViewerFile? {
        guard !wasGivenFiles else { return nil }
        let file = ViewerFile(url: url)
        guard byID[file.id] == nil else { return nil }
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        insert(file)
        return file
    }

    /// Adds a file if it is not already indexed.
    private func insert(_ file: ViewerFile) {
        guard byID[file.id] == nil else { return }
        byID[file.id] = file
        ordered.append(file)
    }
}
