//
//  PenAssetGathering.swift
//  Woodcase
//

import Foundation

/// Copies the local files a document points at into one folder's `images/` and
/// `fonts/`, and answers the relative path each reference should then hold.
///
/// It is what `woodcase bundle` and `woodcase unbundle` share: both move a document to a
/// new folder and must take its files along. A file already in the source folder's
/// `images/` (or `fonts/`) keeps its relative path; any other — elsewhere in the folder,
/// beside it, absolute — is copied in under its own name, made unique when two files
/// share one. Nothing at the destination is ever overwritten.
///
/// ```swift
/// var gathering = PenAssetGathering(from: penFolder, into: bundle)
/// let moved = try PenAssetReferences.rewrite(document) { kind, value in
///     try gathering.place(kind, value)
/// }
/// ```
struct PenAssetGathering {
    /// Gathers files referenced relative to `source` into `destination`.
    ///
    /// - Parameters:
    ///   - source: The folder the references resolve against — the document's
    ///     ``PenLocation/resourceDirectory`` before the move.
    ///   - destination: The folder the document will live in.
    init(from source: URL, into destination: URL) {
        self.source = source.standardizedFileURL
        self.destination = destination.standardizedFileURL
    }

    /// The folder references resolve against.
    let source: URL

    /// The folder files are copied into.
    let destination: URL

    /// The references whose file was not there or could not be read, left as they were.
    private(set) var missing: [PenAssetReferences.Reference] = []

    /// How many files were copied.
    private(set) var copiedCount = 0

    /// Copies the file one reference names, and returns the reference's new value.
    ///
    /// - Parameters:
    ///   - kind: An image or a font.
    ///   - value: The reference as the document writes it.
    /// - Returns: `./images/<name>` or `./fonts/<name>`, or `nil` to leave the reference
    ///   alone: it is remote, a variable, or names a file that does not exist or cannot
    ///   be read.
    /// - Throws: ``PenFileError/writeFailed(url:reason:)`` when the copy fails.
    mutating func place(_ kind: PenAssetReferences.Kind, _ value: String) throws -> String? {
        guard let file = Self.localFile(value, relativeTo: source) else { return nil }
        // A file this process may not read — a sandboxed app without a grant for its
        // folder — is left behind like a missing one, rather than failing the move.
        guard FileManager.default.fileExists(atPath: file.path), FileManager.default.isReadableFile(atPath: file.path)
        else {
            missing.append(PenAssetReferences.Reference(kind: kind, value: value))
            return nil
        }
        if let placed = placed[file.path] { return "./" + placed }
        let relative = destinationPath(for: file, kind: kind)
        let target = destination.appendingPathComponent(relative)
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: file, to: target)
        } catch {
            throw PenFileError.writeFailed(url: target, reason: PenFileError.oneLineReason(error))
        }
        placed[file.path] = relative
        copiedCount += 1
        return "./" + relative
    }

    /// The local file a reference names, or `nil` for one that names no local file —
    /// a remote URL, a `data:` URL, a variable, an empty string.
    ///
    /// A relative reference resolves against `directory` the way the renderer resolves
    /// an image fill; an absolute path or a `file://` URL is taken as it is.
    ///
    /// - Parameters:
    ///   - value: The reference.
    ///   - directory: The folder it resolves against.
    /// - Returns: The file's standardized URL.
    static func localFile(_ value: String, relativeTo directory: URL) -> URL? {
        let address = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, !address.hasPrefix("$") else { return nil }
        if let scheme = address.prefixMatch(of: #/([A-Za-z][A-Za-z0-9+.\-]*):/#)?.1, scheme.count > 1 {
            guard scheme.lowercased() == "file", let url = URL(string: address), url.isFileURL else { return nil }
            return url.standardizedFileURL
        }
        if address.hasPrefix("/") {
            return URL(fileURLWithPath: address).standardizedFileURL
        }
        return directory.appendingPathComponent(address).standardizedFileURL
    }

    // MARK: - Private

    /// Each copied file's path at the destination, relative to it, by its source path.
    private var placed: [String: String] = [:]

    /// The relative path a file takes at the destination: its own, when it already sits
    /// in the source's folder for its kind; its name in that folder otherwise, numbered
    /// until it is free.
    private func destinationPath(for file: URL, kind: PenAssetReferences.Kind) -> String {
        let folder = source.appendingPathComponent(kind.directoryName).path + "/"
        if file.path.hasPrefix(folder) {
            let kept = kind.directoryName + "/" + String(file.path.dropFirst(folder.count))
            if isFree(kept) { return kept }
        }
        let stem = file.deletingPathExtension().lastPathComponent
        let ext = file.pathExtension
        var candidate = kind.directoryName + "/" + file.lastPathComponent
        var number = 2
        while !isFree(candidate) {
            candidate = kind.directoryName + "/" + stem + "-\(number)" + (ext.isEmpty ? "" : "." + ext)
            number += 1
        }
        return candidate
    }

    /// Whether nothing has been placed at a relative path and nothing exists there.
    private func isFree(_ relative: String) -> Bool {
        !placed.values.contains(relative)
            && !FileManager.default.fileExists(atPath: destination.appendingPathComponent(relative).path)
    }
}
