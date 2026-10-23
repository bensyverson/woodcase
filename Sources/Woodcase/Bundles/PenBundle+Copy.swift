//
//  PenBundle+Copy.swift
//  Woodcase
//

import Foundation

public extension PenBundle {
    /// Copies a bundle to a new bundle — an app's Save As, Duplicate and Save To.
    ///
    /// The copy is the same design: `document.pen` byte for byte (so the same revision),
    /// every file in `images/` and `fonts/`, and anything else a person put at the
    /// bundle's root. With `history` ``HistoryInclusion/included`` it also takes every
    /// writer's file from `history/`, so the copy carries on the one shared history;
    /// ``HistoryInclusion/omitted`` starts it with none. The `converted-from.json` record
    /// is re-rooted so it still names the original from the copy's folder.
    ///
    /// Never copied, whichever `history` is passed: the bundle's `.woodcase/` local state
    /// and its own `.gitignore` (the copy writes its own on its first edit), and any
    /// other hidden file. The source is only read, under a shared lock; if anything
    /// fails, the half-made copy is removed.
    ///
    /// - Parameters:
    ///   - bundle: The bundle to copy.
    ///   - destination: The `.umbra` bundle to create. Its folder must exist; nothing may
    ///     be at the path itself.
    ///   - history: Whether the writers' history files go with it.
    /// - Returns: The copy's document and revision, how many image and font files it
    ///   holds, and how many history files were copied.
    /// - Throws: ``PenBundleError`` when `bundle` is not a bundle, `destination` is not a
    ///   `.umbra` path, or its path is taken; ``PenFileError`` or ``PenParserError`` when
    ///   the source cannot be read or the copy written.
    @discardableResult
    static func copy(_ bundle: URL, to destination: URL, history: HistoryInclusion) async throws -> Report {
        let source = PenLocation(bundle)
        guard source.kind == .bundle else { throw PenBundleError.notABundle(bundle) }
        guard PenLocation.isBundle(destination) else { throw PenBundleError.notABundle(destination) }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw PenBundleError.destinationExists(destination)
        }

        let lock = try await FileLock.acquire(source.document, mode: .shared, timeout: PenFileTransaction.defaultTimeout)
        defer { lock.release() }
        let revision = try EditableDocument(from: PenFileTransaction.parse(lock)).documentRevision

        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        } catch {
            throw PenFileError.writeFailed(url: destination, reason: PenFileError.oneLineReason(error))
        }
        do {
            let target = PenLocation(destination)
            try copyDesign(from: source, to: target)
            try reroot(ConvertedFrom.read(in: source.url), from: source, to: target)
            let historyCopied = history == .included
                ? try copyHistory(from: source.url, into: target.historyDirectory ?? destination)
                : 0
            return Report(
                document: target.document,
                revision: revision,
                copied: assetCount(in: target),
                historyCopied: historyCopied
            )
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    // MARK: - Private

    /// Every entry at the source's root that is part of the design: not hidden (local
    /// state, `.gitignore`), not `history/` (the caller's choice) and not the
    /// converted-from record (re-rooted separately).
    private static func copyDesign(from source: PenLocation, to target: PenLocation) throws {
        let skipped: Set<String> = [ActivityLog.historyDirectoryName, ConvertedFrom.fileName]
        do {
            let names = try FileManager.default.contentsOfDirectory(atPath: source.url.path)
            for name in names where !name.hasPrefix(".") && !skipped.contains(name) {
                try FileManager.default.copyItem(
                    at: source.url.appendingPathComponent(name), to: target.url.appendingPathComponent(name)
                )
            }
        } catch {
            throw PenFileError.writeFailed(url: target.url, reason: PenFileError.oneLineReason(error))
        }
    }

    /// Writes the copy's converted-from record, naming the same original relative to the
    /// copy's folder.
    private static func reroot(_ record: ConvertedFrom?, from source: PenLocation, to target: PenLocation) throws {
        guard let record else { return }
        let original = URL(fileURLWithPath: record.file, relativeTo: source.containingDirectory)
        let relative = relativePath(of: original, from: target.containingDirectory)
        try ConvertedFrom(file: relative, revision: record.revision, date: record.date).write(in: target.url)
    }

    /// How many files `images/` and `fonts/` hold.
    private static func assetCount(in bundle: PenLocation) -> Int {
        [AssetKind.image, .font].reduce(0) { total, kind in
            let folder = bundle.url.appendingPathComponent(kind.directoryName, isDirectory: true)
            let files = FileManager.default.enumerator(atPath: folder.path)?.allObjects as? [String] ?? []
            return total + files.count(where: { name in
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path, isDirectory: &isDirectory)
                return !isDirectory.boolValue
            })
        }
    }
}
