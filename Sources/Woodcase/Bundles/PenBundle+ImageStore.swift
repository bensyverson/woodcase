//
//  PenBundle+ImageStore.swift
//  Woodcase
//

import CryptoKit
import Foundation

public extension PenBundle {
    /// How many hex digits of an image's SHA-256 name its file: 16, so 64 bits.
    ///
    /// Two different images in one bundle share a name with odds of about n² / 2⁶⁵ — one in
    /// 3.7 × 10¹¹ for ten thousand images — and even then nothing is lost:
    /// ``storeImage(_:fileExtension:in:)`` compares bytes before it reuses a file, and
    /// numbers the newcomer past one that differs. More digits would buy nothing a person
    /// could notice and make every reference longer to read.
    static let imageHashLength = 16

    /// Stores image bytes — a pasted or dropped image, a download — in a bundle's
    /// `images/` under their content hash, and returns the reference a fill should hold.
    ///
    /// The file is named ``imageFileName(for:fileExtension:)``: 16 hex digits of the bytes'
    /// SHA-256 and the extension their signature names. So the same image added twice is
    /// stored once, and every fill showing it references one file:
    ///
    /// ```swift
    /// let first = try PenBundle.storeImage(png, fileExtension: "png", in: bundle)
    /// let again = try PenBundle.storeImage(png, fileExtension: "png", in: bundle)
    /// // both "./images/5280ed5c223e2c4a.png", one file on disk
    /// ```
    ///
    /// A file already at that name is reused only when it holds exactly these bytes; one
    /// that differs is never overwritten, and the bytes go to the first of `<hash>-2.png`,
    /// `<hash>-3.png`… that holds them or is free. The file is written in the bundle's
    /// `.woodcase/` and linked into place, so a reader never sees half an image and two
    /// writers of one image end with one file.
    ///
    /// The reference is an ordinary relative path in a plain `document.pen`, so Pen and
    /// every other `.pen` tool read it as they read any image fill.
    ///
    /// - Parameters:
    ///   - data: The image's bytes.
    ///   - fileExtension: The extension the image came with (`"png"`), used only when
    ///     the bytes' signature names none; `nil` when there is none.
    ///   - bundle: The `.umbra` bundle, or the `document.pen` inside it.
    /// - Returns: The reference, `./images/<hash>.<ext>`.
    /// - Throws: ``PenBundleError/notABundle(_:)`` for a bare `.pen`;
    ///   ``PenFileError/writeFailed(url:reason:)`` when the write fails.
    static func storeImage(_ data: Data, fileExtension: String?, in bundle: URL) throws -> String {
        let location = PenLocation(bundle)
        guard location.kind == .bundle else { throw PenBundleError.notABundle(bundle) }
        let folder = location.resourceDirectory.appendingPathComponent(AssetKind.image.directoryName, isDirectory: true)
        let name = imageFileName(for: data, fileExtension: fileExtension)
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var staged: URL?
        defer {
            if let staged { try? FileManager.default.removeItem(at: staged) }
        }
        var number = 1
        while true {
            let candidate = number == 1 ? name : "\(stem)-\(number).\(ext)"
            let target = folder.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: target.path) {
                if (try? Data(contentsOf: target)) == data { return reference(to: candidate) }
                number += 1
                continue
            }
            do {
                let source = try staged ?? stage(data, in: location.temporaryDirectory)
                staged = source
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                if try place(source, at: target) { return reference(to: candidate) }
            } catch {
                throw PenFileError.writeFailed(url: target, reason: PenFileError.oneLineReason(error))
            }
            // Another writer took the name between the check and the link: look again.
        }
    }

    /// Stores a dropped image file in a bundle's `images/` under its content hash —
    /// ``storeImage(_:fileExtension:in:)`` with the file's bytes and extension — and
    /// returns the reference a fill should hold.
    ///
    /// A file already inside the bundle is not copied: its own path is returned, as
    /// ``importAsset(_:as:into:)`` does.
    ///
    /// - Parameters:
    ///   - file: The image file.
    ///   - bundle: The `.umbra` bundle, or the `document.pen` inside it.
    /// - Returns: The reference, `./images/<hash>.<ext>`, or the file's own path inside
    ///   the bundle.
    /// - Throws: ``PenBundleError/notABundle(_:)`` for a bare `.pen`;
    ///   ``PenFileError/cannotOpen(url:reason:)`` when the file cannot be read;
    ///   ``PenFileError/writeFailed(url:reason:)`` when the write fails.
    static func storeImage(contentsOf file: URL, in bundle: URL) throws -> String {
        let location = PenLocation(bundle)
        guard location.kind == .bundle else { throw PenBundleError.notABundle(bundle) }
        let source = file.standardizedFileURL.resolvingSymlinksInPath()
        let root = location.resourceDirectory.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        if source.path.hasPrefix(root) {
            return "./" + String(source.path.dropFirst(root.count))
        }
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw PenFileError.cannotOpen(url: file, reason: PenFileError.oneLineReason(error))
        }
        return try storeImage(data, fileExtension: file.pathExtension, in: bundle)
    }

    /// The file name ``storeImage(_:fileExtension:in:)`` gives image bytes:
    /// ``imageHashLength`` lowercase hex digits of their SHA-256, then the extension their
    /// signature names (`png`, `jpg`, `gif`, `webp`).
    ///
    /// Bytes no signature names keep `fileExtension`, lowercased, when it is plain
    /// letters and digits (`svg`), and take `img` otherwise. The bytes decide before the
    /// name they came with, so one image is one name whatever it was called.
    ///
    /// - Parameters:
    ///   - data: The image's bytes.
    ///   - fileExtension: The extension the image came with, or `nil`.
    /// - Returns: The name, `5280ed5c223e2c4a.png`.
    static func imageFileName(for data: Data, fileExtension: String?) -> String {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let hash = String(digest.prefix(imageHashLength))
        let given = fileExtension?.lowercased() ?? ""
        let ext = ImageFileFormat(sniffing: data)?.fileExtension
            ?? (given.wholeMatch(of: #/[a-z0-9]+/#) != nil ? given : "img")
        return hash + "." + ext
    }

    // MARK: - Private

    /// The reference to a file in `images/`.
    private static func reference(to name: String) -> String {
        "./" + AssetKind.image.directoryName + "/" + name
    }

    /// Writes `data` to a new temporary file in `directory`.
    private static func stage(_ data: Data, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("image-\(UUID().uuidString).tmp")
        try data.write(to: file, options: .withoutOverwriting)
        return file
    }

    /// Links the staged file in at `target`, which must not exist.
    ///
    /// A hard link fails atomically when the name is taken; a volume without hard links
    /// falls back to a copy.
    ///
    /// - Returns: `false` when another file took `target` first.
    private static func place(_ staged: URL, at target: URL) throws -> Bool {
        do {
            try FileManager.default.linkItem(at: staged, to: target)
            return true
        } catch CocoaError.fileWriteFileExists {
            return false
        } catch {
            guard !FileManager.default.fileExists(atPath: target.path) else { return false }
            try FileManager.default.copyItem(at: staged, to: target)
            return true
        }
    }
}
