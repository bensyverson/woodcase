//
//  PenBundle+Assets.swift
//  Woodcase
//

import Foundation

public extension PenBundle {
    /// The local files a document points at: every image fill and declared font that
    /// names a file rather than a remote URL or a variable, resolved against the
    /// document's ``PenLocation/resourceDirectory``.
    ///
    /// An app in the App Sandbox asks before a conversion or an export which of these it
    /// may read, and asks the user for the folders of the rest, since
    /// ``convert(_:to:identity:)`` and ``export(_:to:identity:history:)`` leave an unreadable
    /// file behind.
    ///
    /// - Parameter document: A bare `.pen`, or a `.umbra` bundle.
    /// - Returns: Each file once, standardized, in document order, whether or not it
    ///   exists.
    /// - Throws: ``PenParserError`` when the document cannot be read.
    static func localAssets(of document: URL) throws -> [URL] {
        let location = PenLocation(document)
        let parsed = try PenParser.parse(contentsOf: location.document)
        var files: [URL] = []
        for reference in try PenAssetReferences.collect(from: parsed) {
            guard let file = PenAssetGathering.localFile(reference.value, relativeTo: location.resourceDirectory),
                  !files.contains(file)
            else { continue }
            files.append(file)
        }
        return files
    }

    /// Copies a file into a bundle's folder for its kind — an installed font — and
    /// returns the relative reference a `fonts` entry or a fill should hold.
    ///
    /// The copy takes the file's own name, numbered (`Mono-2.ttf`) when the name is taken,
    /// so nothing in the bundle is ever overwritten. A file already inside the bundle is
    /// not copied: its own path is returned. A dropped or pasted image goes through
    /// ``storeImage(contentsOf:in:)`` instead, which stores it once by its content.
    ///
    /// ```swift
    /// let url = try PenBundle.importAsset(installed, as: .font, into: bundle)
    /// // "./fonts/Mono.ttf"
    /// ```
    ///
    /// - Parameters:
    ///   - file: The file to copy.
    ///   - kind: Whether it is an image or a font, which picks `images/` or `fonts/`.
    ///   - bundle: The `.umbra` bundle, or the `document.pen` inside it.
    /// - Returns: The reference, `./images/<name>` or `./fonts/<name>`.
    /// - Throws: ``PenBundleError/notABundle(_:)`` for a bare `.pen`;
    ///   ``PenFileError/writeFailed(url:reason:)`` when the copy fails.
    static func importAsset(_ file: URL, as kind: AssetKind, into bundle: URL) throws -> String {
        let directory = try resourceDirectory(of: bundle)
        let source = file.standardizedFileURL.resolvingSymlinksInPath()
        let root = directory.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        if source.path.hasPrefix(root) {
            return "./" + String(source.path.dropFirst(root.count))
        }
        return try store(kind, named: file.lastPathComponent, in: directory) { target in
            try FileManager.default.copyItem(at: file, to: target)
        }
    }

    /// Writes bytes into a bundle's folder for their kind under the name given, and
    /// returns the relative reference a fill or a `fonts` entry should hold. Pasted image
    /// bytes go through ``storeImage(_:fileExtension:in:)`` instead.
    ///
    /// - Parameters:
    ///   - data: The file's bytes.
    ///   - name: The file name to use, numbered (`Pasted-2.png`) when it is taken.
    ///   - kind: Whether it is an image or a font, which picks `images/` or `fonts/`.
    ///   - bundle: The `.umbra` bundle, or the `document.pen` inside it.
    /// - Returns: The reference, `./images/<name>` or `./fonts/<name>`.
    /// - Throws: ``PenBundleError/notABundle(_:)`` for a bare `.pen`;
    ///   ``PenFileError/writeFailed(url:reason:)`` when the write fails.
    static func importAsset(_ data: Data, named name: String, as kind: AssetKind, into bundle: URL) throws -> String {
        let directory = try resourceDirectory(of: bundle)
        return try store(kind, named: name, in: directory) { target in
            try data.write(to: target, options: .withoutOverwriting)
        }
    }

    // MARK: - Internal

    /// The first name in `folder` that nothing occupies: `name` itself, then
    /// `stem-2.ext`, `stem-3.ext` and on.
    ///
    /// - Parameters:
    ///   - name: The file name wanted.
    ///   - folder: The folder it goes in.
    /// - Returns: A free file name.
    internal static func freeName(_ name: String, in folder: URL) -> String {
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = name
        var number = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
            candidate = stem + "-\(number)" + (ext.isEmpty ? "" : "." + ext)
            number += 1
        }
        return candidate
    }

    // MARK: - Private

    /// The folder a bundle's references resolve against, refusing a bare file.
    private static func resourceDirectory(of bundle: URL) throws -> URL {
        let location = PenLocation(bundle)
        guard location.kind == .bundle else { throw PenBundleError.notABundle(bundle) }
        return location.resourceDirectory
    }

    /// Writes one file into the kind's folder under a free name with `write`.
    ///
    /// - Returns: The reference to it, `./<folder>/<name>`.
    private static func store(
        _ kind: AssetKind,
        named name: String,
        in directory: URL,
        write: (URL) throws -> Void
    ) throws -> String {
        let folder = directory.appendingPathComponent(kind.directoryName, isDirectory: true)
        let target = folder.appendingPathComponent(freeName(name, in: folder))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try write(target)
        } catch {
            throw PenFileError.writeFailed(url: target, reason: PenFileError.oneLineReason(error))
        }
        return "./" + kind.directoryName + "/" + target.lastPathComponent
    }
}
