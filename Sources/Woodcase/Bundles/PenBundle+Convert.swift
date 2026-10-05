//
//  PenBundle+Convert.swift
//  Woodcase
//

import Foundation

public extension PenBundle {
    /// Converts a bare `.pen` into a bundle beside it, in place — `woodcase bundle`.
    ///
    /// `Design.pen` becomes `Design.umbra/document.pen`. Every local image fill and
    /// declared font the document points at is copied into the bundle's `images/` and
    /// `fonts/` and its reference rewritten to `./images/…` or `./fonts/…`; a file
    /// already in the original folder's `images/` or `fonts/` keeps its relative path.
    /// Remote images and fonts are left as they are — ``embed(_:identity:fetcher:fonts:)``
    /// downloads them, and only when asked. The bundle records the original it came from
    /// (``ConvertedFrom``), its log starts with a `new` row, and the original is removed,
    /// so Git sees a rename. The original's history stays in the log it was written to.
    ///
    /// The original is locked for the whole conversion, so no other writer can slip an
    /// edit in between the read and the removal. If anything fails, the half-made bundle
    /// is removed and the original is left untouched.
    ///
    /// - Parameters:
    ///   - file: The bare `.pen` to convert.
    ///   - identity: The writer's name for the bundle's `new` row, or `nil`.
    /// - Returns: The bundle's document, its revision, how many files were copied, and
    ///   any reference whose file was missing.
    /// - Throws: ``PenBundleError`` when `file` is already in a bundle or the bundle's
    ///   path is taken; ``PenFileError`` or ``PenParserError`` when the original cannot
    ///   be read, or the bundle written.
    @discardableResult
    static func convert(_ file: URL, identity: String?) async throws -> Report {
        guard PenLocation(file).kind == .file else { throw PenBundleError.alreadyBundled(file) }
        let bundle = file.deletingPathExtension().appendingPathExtension(PenLocation.bundleExtension)
        guard !FileManager.default.fileExists(atPath: bundle.path) else {
            throw PenBundleError.destinationExists(bundle)
        }

        let lock = try await FileLock.acquire(file, mode: .exclusive, timeout: PenFileTransaction.defaultTimeout)
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
            try ConvertedFrom(file: file.lastPathComponent, revision: originalRevision, date: Date()).write(in: bundle)
            do {
                try FileManager.default.removeItem(at: file)
            } catch {
                throw PenFileError.writeFailed(url: file, reason: PenFileError.oneLineReason(error))
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
}
