//
//  GoogleFontResolver+Embedding.swift
//  Woodcase
//

import Foundation

extension GoogleFontResolver {
    /// One Google Fonts file to copy into a bundle, with what its declaration says.
    struct EmbeddableFile: Friendly {
        /// The file's name in google/fonts, `Inter[opsz,wght].ttf`.
        var filename: String
        /// Its bytes.
        var data: Data
        /// The style its METADATA gives it.
        var style: PenFontDeclaration.Style
        /// The weight it serves: its METADATA weight for a static file, the span of the
        /// document's weights it serves for a variable one.
        var weight: PenFontDeclaration.Weight
    }

    /// The Google Fonts files a document's faces of `family` draw in, from the cache or
    /// downloaded into it, ready to embed.
    ///
    /// The same files ``fontBundle(for:declaredIn:relativeTo:)`` picks for a generated
    /// package — CSS matching over the family's METADATA — with the style and weight
    /// a declaration of each needs.
    ///
    /// - Parameters:
    ///   - family: The family.
    ///   - faces: The faces of it the document draws.
    /// - Returns: One file per distinct METADATA entry the faces map to, in file-name order.
    /// - Throws: ``GoogleFontError`` when the metadata cannot be had, and the fetcher's
    ///   error when a file cannot be downloaded.
    func embeddableFiles(family: String, faces: Set<PenFontFace>) async throws -> [EmbeddableFile] {
        let (metadata, _) = try await familyMetadata(family: family)
        var entries: [String: GoogleFontMetadata.FontEntry] = [:]
        var weights: [String: [Int]] = [:]
        for face in faces {
            guard let entry = metadata.entry(weight: face.weight, style: face.style) else { continue }
            entries[entry.filename] = entry
            weights[entry.filename, default: []].append(face.weight)
        }
        return try await googleFaceFiles(family: family, faces: faces).compactMap { file in
            guard let entry = entries[file.name], let data = file.contents else { return nil }
            let served = weights[entry.filename] ?? [entry.weight]
            let isVariable = entry.filename.contains("[")
            let low = Double(served.min() ?? entry.weight)
            let high = Double(served.max() ?? entry.weight)
            return EmbeddableFile(
                filename: entry.filename,
                data: data,
                style: entry.style == PenFontDeclaration.Style.italic.rawValue ? .italic : .normal,
                weight: isVariable && low != high ? .range(from: low, to: high) : .single(isVariable ? low : Double(entry.weight))
            )
        }
    }
}
