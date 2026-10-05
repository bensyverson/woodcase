//
//  PenBundle+Convert.swift
//  Woodcase
//

import Foundation

public extension PenBundle {
    /// Converts a bare `.pen` into a bundle beside it, in place — `woodcase bundle`.
    ///
    /// `Design.pen` becomes `Design.umbra/document.pen`, as
    /// ``convert(_:to:identity:)`` makes it, and the original is then removed, so Git
    /// sees a rename. The original's history stays in the log it was written to.
    ///
    /// The original is locked exclusively for the whole conversion, so no other writer
    /// can slip an edit in between the read and the removal. If anything fails, the
    /// half-made bundle is removed and the original is left untouched.
    ///
    /// - Parameters:
    ///   - file: The bare `.pen` to convert.
    ///   - identity: The writer's name for the bundle's `new` row, or `nil`.
    /// - Returns: The bundle's document, its revision, how many files were copied, and
    ///   any reference whose file was missing or unreadable.
    /// - Throws: ``PenBundleError`` when `file` is already in a bundle or the bundle's
    ///   path is taken; ``PenFileError`` or ``PenParserError`` when the original cannot
    ///   be read, or the bundle written.
    @discardableResult
    static func convert(_ file: URL, identity: String?) async throws -> Report {
        let bundle = file.deletingPathExtension().appendingPathExtension(PenLocation.bundleExtension)
        return try await convert(file, to: bundle, identity: identity, removingOriginal: true)
    }

    /// Converts a bare `.pen` into a new bundle wherever the caller chose, and leaves the
    /// original where it is — an app's Convert…, whose save panel named the bundle.
    ///
    /// The bundle gets `document.pen`. Every local image fill and declared font the
    /// document points at is copied into the bundle's `images/` and `fonts/` and its
    /// reference rewritten to `./images/…` or `./fonts/…`; a file already in the original
    /// folder's `images/` or `fonts/` keeps its relative path. A file that is missing, or
    /// that this process may not read — a sandboxed app without a grant for its folder —
    /// is left as it was and reported in ``Report/missing``. Remote images and fonts are
    /// left as they are; ``embed(_:identity:fetcher:fonts:)`` downloads them, and only
    /// when asked. The bundle's log starts with a `new` row, and the bundle records the
    /// original (``ConvertedFrom``) by its path relative to the bundle's folder, so the
    /// CLI warns anyone who goes on editing the original when the two sit together.
    ///
    /// The original is only read, under a shared lock. If anything fails, the half-made
    /// bundle is removed.
    ///
    /// - Parameters:
    ///   - file: The bare `.pen` to convert.
    ///   - bundle: The `.umbra` bundle to create. Its folder must exist; nothing may be
    ///     at the path itself.
    ///   - identity: The writer's name for the bundle's `new` row, or `nil`.
    /// - Returns: The bundle's document, its revision, how many files were copied, and
    ///   any reference whose file was missing or unreadable.
    /// - Throws: ``PenBundleError`` when `file` is already in a bundle, `bundle` is not a
    ///   `.umbra` path, or its path is taken; ``PenFileError`` or ``PenParserError`` when
    ///   the original cannot be read, or the bundle written.
    @discardableResult
    static func convert(_ file: URL, to bundle: URL, identity: String?) async throws -> Report {
        try await convert(file, to: bundle, identity: identity, removingOriginal: false)
    }

    // MARK: - Private

    /// Both conversions: the one the CLI runs in place, and the one an app runs to a
    /// chosen bundle.
    private static func convert(
        _ file: URL,
        to bundle: URL,
        identity: String?,
        removingOriginal: Bool
    ) async throws -> Report {
        guard PenLocation(file).kind == .file else { throw PenBundleError.alreadyBundled(file) }
        guard PenLocation.isBundle(bundle) else { throw PenBundleError.notABundle(bundle) }
        guard !FileManager.default.fileExists(atPath: bundle.path) else {
            throw PenBundleError.destinationExists(bundle)
        }

        let lock = try await FileLock.acquire(
            file, mode: removingOriginal ? .exclusive : .shared, timeout: PenFileTransaction.defaultTimeout
        )
        defer { lock.release() }
        let original = try PenFileTransaction.parse(lock)
        let originalRevision = EditableDocument(from: original).documentRevision

        do {
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: false)
        } catch {
            throw PenFileError.writeFailed(url: bundle, reason: PenFileError.oneLineReason(error))
        }
        do {
            var gathering = PenAssetGathering(from: file.deletingLastPathComponent(), into: bundle)
            let moved = try PenAssetReferences.rewrite(original) { kind, value in
                try gathering.place(kind, value)
            }
            let created = try await PenFileTransaction.create(at: bundle, document: moved, identity: identity)
            let recorded = relativePath(of: file, from: bundle.deletingLastPathComponent())
            try ConvertedFrom(file: recorded, revision: originalRevision, date: Date()).write(in: bundle)
            if removingOriginal {
                do {
                    try FileManager.default.removeItem(at: file)
                } catch {
                    throw PenFileError.writeFailed(url: file, reason: PenFileError.oneLineReason(error))
                }
            }
            return Report(
                document: PenLocation(bundle).document,
                revision: created.value,
                copied: gathering.copiedCount,
                missing: gathering.missing.map(\.value)
            )
        } catch {
            try? FileManager.default.removeItem(at: bundle)
            throw error
        }
    }

    /// `file`'s path relative to `folder`: `Design.pen` beside it, `../project/Design.pen`
    /// one folder over.
    private static func relativePath(of file: URL, from folder: URL) -> String {
        let target = file.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let base = folder.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let shared = zip(target, base).prefix { $0 == $1 }.count
        let up = Array(repeating: "..", count: base.count - shared)
        return (up + target.dropFirst(shared)).joined(separator: "/")
    }
}
