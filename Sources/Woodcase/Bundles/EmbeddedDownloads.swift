//
//  EmbeddedDownloads.swift
//  Woodcase
//

import Foundation

/// What ``PenBundle/embed(_:identity:fetcher:fonts:)`` downloaded into a bundle, and the
/// edit that makes the document use it.
///
/// Downloads happen before the document is locked — a transaction's body cannot wait on
/// the network — so this keeps the outcome as a table from each remote reference to its
/// local copy, plus the font declarations to add, and turns them into operations against
/// whatever the document holds once it is locked.
struct EmbeddedDownloads {
    /// Starts an empty set of downloads into a bundle.
    ///
    /// - Parameter bundle: The bundle directory files are written into.
    init(bundle: URL) {
        self.bundle = bundle
    }

    /// The bundle directory.
    let bundle: URL

    /// Each remote reference's local replacement, `./images/…` or `./fonts/…`.
    private(set) var replacements: [String: String] = [:]

    /// The declarations to add for the Google Fonts files copied in.
    private(set) var declarations: [PenFontDeclaration] = []

    /// How many files were written.
    private(set) var count = 0

    /// The references and families that could not be downloaded.
    private(set) var missing: [String] = []

    /// Downloads one remote image or declared font into the bundle.
    ///
    /// - Parameters:
    ///   - reference: The remote reference.
    ///   - fetcher: What downloads it.
    mutating func fetch(_ reference: PenAssetReferences.Reference, with fetcher: any RemoteDataFetching) async {
        guard replacements[reference.value] == nil, let url = URL(string: reference.value) else { return }
        do {
            let data = try await fetcher.fetch(url: url)
            let relative = try store(data, named: Self.fileName(for: url, data: data), kind: reference.kind)
            replacements[reference.value] = "./" + relative
            count += 1
        } catch {
            missing.append(reference.value)
        }
    }

    /// Copies the Google Fonts file of each face of a family into the bundle, and
    /// declares it.
    ///
    /// - Parameters:
    ///   - family: The family.
    ///   - faces: The faces of it the document draws.
    ///   - resolver: Where the files come from.
    mutating func embedGoogleFamily(_ family: String, faces: Set<PenFontFace>, from resolver: GoogleFontResolver) async {
        do {
            let files = try await resolver.embeddableFiles(family: family, faces: faces)
            guard !files.isEmpty else {
                missing.append(family)
                return
            }
            for file in files {
                let relative = try store(file.data, named: file.filename, kind: .font)
                declarations.append(PenFontDeclaration(
                    name: family, url: "./" + relative, style: file.style, weight: file.weight
                ))
                count += 1
            }
        } catch {
            missing.append(family)
        }
    }

    /// The operations that make `document` use what was downloaded: a subtree
    /// replacement for each top-level node whose fills changed, and one write of the
    /// root `fonts` array.
    ///
    /// - Parameter document: The document as the locked file holds it.
    /// - Returns: The operations, empty when there is nothing to change.
    /// - Throws: Whatever rewriting or encoding the document throws.
    func operations(rewriting document: PenDocument) throws -> [EditOperation] {
        var rewritten = try PenAssetReferences.rewrite(document) { _, value in replacements[value] }
        let existing = Set((rewritten.fonts ?? []).map(\.url))
        let added = declarations.filter { !existing.contains($0.url) }
        if !added.isEmpty {
            rewritten.fonts = (rewritten.fonts ?? []) + added
        }
        var operations: [EditOperation] = []
        for (before, after) in zip(document.children, rewritten.children) where before != after {
            operations.append(.replaceSubtree(EditOperation.ReplaceSubtree(node: after)))
        }
        if rewritten.fonts != document.fonts {
            let fonts = try JSONDecoder().decode(AnyCodable.self, from: JSONEncoder().encode(rewritten.fonts ?? []))
            operations.append(.setDocumentProperties(EditOperation.SetDocumentProperties(properties: ["fonts": fonts])))
        }
        return operations
    }

    // MARK: - Private

    /// Writes one downloaded file into the kind's folder under a free name.
    ///
    /// - Returns: Its path relative to the bundle.
    private func store(_ data: Data, named name: String, kind: PenAssetReferences.Kind) throws -> String {
        let folder = bundle.appendingPathComponent(kind.directoryName, isDirectory: true)
        let candidate = PenBundle.freeName(name, in: folder)
        let target = folder.appendingPathComponent(candidate)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: target, options: .withoutOverwriting)
        } catch {
            throw PenFileError.writeFailed(url: target, reason: PenFileError.oneLineReason(error))
        }
        return kind.directoryName + "/" + candidate
    }

    /// A file name for a download: the URL's own last component when it is a plain name
    /// with an extension, otherwise `remote-<hash>` with an extension sniffed from the
    /// bytes.
    static func fileName(for url: URL, data: Data) -> String {
        let last = url.lastPathComponent
        if !url.pathExtension.isEmpty, last.wholeMatch(of: #/[A-Za-z0-9._\-\[\],]+/#) != nil {
            return last
        }
        return "remote-\(fnv1a(url.absoluteString))" + sniffedExtension(data)
    }

    /// The extension the bytes' signature implies, with its dot, or `.img`.
    private static func sniffedExtension(_ data: Data) -> String {
        ImageFileFormat(sniffing: data).map { "." + $0.fileExtension } ?? ".img"
    }

    /// Sixteen hex digits of the string's FNV-1a hash: stable across processes, unlike
    /// `Hasher`.
    private static func fnv1a(_ string: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(format: "%016llx", hash)
    }
}
