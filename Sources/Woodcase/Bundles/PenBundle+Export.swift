//
//  PenBundle+Export.swift
//  Woodcase
//

import Foundation

public extension PenBundle {
    /// Copies a bundle out into a plain folder any `.pen` tool opens — `woodcase unbundle`.
    ///
    /// The folder gets `<name>.pen` — `Design.pen` for `Design.umbra` — beside `images/`
    /// and `fonts/` holding every local file the document points at, with relative
    /// references that resolve from there. Files inside the bundle keep their relative
    /// paths; a reference that reached outside the bundle is copied in too, so the folder
    /// stands alone. The bundle itself, its log and its ``ConvertedFrom`` record are
    /// left where they are; the new file's log starts with a `new` row, as any file
    /// woodcase creates does. Nothing in the folder is overwritten.
    ///
    /// - Parameters:
    ///   - bundle: The bundle to export.
    ///   - folder: Where to write. Created if missing; it may already hold other files.
    ///   - identity: The writer's name for the new file's `new` row, or `nil`.
    /// - Returns: The exported `.pen`, its revision, how many files were copied, and any
    ///   reference whose file was missing.
    /// - Throws: ``PenBundleError`` when `bundle` is not a bundle or `<name>.pen` exists
    ///   in `folder`; ``PenFileError`` or ``PenParserError`` when the bundle cannot be
    ///   read or the folder written.
    @discardableResult
    static func export(_ bundle: URL, to folder: URL, identity: String?) async throws -> Report {
        let location = PenLocation(bundle)
        guard location.kind == .bundle else { throw PenBundleError.notABundle(bundle) }
        let destination = folder.appendingPathComponent(location.name).appendingPathExtension("pen")
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw PenBundleError.destinationExists(destination)
        }

        let document = try await PenFileTransaction.read(at: location.document) { $0.materialize() }.value
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw PenFileError.writeFailed(url: folder, reason: PenFileError.oneLineReason(error))
        }
        var gathering = PenAssetGathering(from: location.resourceDirectory, into: folder)
        let exported = try PenAssetReferences.rewrite(document) { kind, value in
            try gathering.place(kind, value)
        }
        let created = try await PenFileTransaction.create(at: destination, document: exported, identity: identity)
        return Report(
            document: destination,
            revision: created.value,
            copied: gathering.copiedCount,
            missing: gathering.missing.map(\.value)
        )
    }
}
