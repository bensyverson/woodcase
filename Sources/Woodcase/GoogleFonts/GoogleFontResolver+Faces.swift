//
//  GoogleFontResolver+Faces.swift
//  Woodcase
//

import Foundation

/// Resolving the faces a document draws: registering what the cache holds, and fetching
/// the file each missing face needs.
public extension GoogleFontResolver {
    /// Makes `faces` available to Core Text, downloading what the cache lacks.
    ///
    /// For each family: faces Core Text already has a font for, or a family the
    /// operating system ships, need nothing. Otherwise every file the cache holds for the
    /// family is registered, and for each face still missing the file its METADATA.pb
    /// names (``GoogleFontMetadata/entry(weight:style:)``) is downloaded, cached and
    /// registered — each static face its own file, a variable family its italic file
    /// only when italic is drawn. The METADATA is read from the cache when an earlier
    /// run left it there, so a face the family does not ship (a 900 where it stops at
    /// 700) is answered by its nearest face without asking the network again.
    ///
    /// Each face is attempted once per resolver: a face that failed is not retried.
    ///
    /// - Parameter faces: The faces to resolve, of any families.
    /// - Returns: The font files this call handed to Core Text — cache files, or scratch
    ///   copies of memory-only ones — whether or not Core Text accepted them.
    @discardableResult
    func resolve(_ faces: Set<PenFontFace>) async -> [URL] {
        var files: [URL] = []
        for (family, familyFaces) in Dictionary(grouping: faces, by: \.family).sorted(by: { $0.key < $1.key }) {
            files += await resolve(family: family, faces: Set(familyFaces))
        }
        return files
    }
}

extension GoogleFontResolver {
    /// ``resolve(_:)`` for the faces of one family.
    ///
    /// - Parameters:
    ///   - family: The family.
    ///   - faces: Faces of `family`.
    /// - Returns: The font files handed to Core Text.
    @discardableResult
    func resolve(family: String, faces: Set<PenFontFace>) async -> [URL] {
        let pending = state.withLock { faces.subtracting($0.attemptedFaces) }
        guard !pending.isEmpty else { return [] }
        defer { state.withLock { $0.attemptedFaces.formUnion(pending) } }

        if PenTextMeasurer.availableFaces(pending) == pending || Self.isSystemFamily(family) { return [] }
        var files = registerCachedFiles(family: family)
        let missing = pending.subtracting(PenTextMeasurer.availableFaces(pending))
        guard !missing.isEmpty else { return files }
        do {
            for file in try await googleFaceFiles(family: family, faces: missing) {
                if let url = register(file, family: family), !files.contains(url) {
                    files.append(url)
                }
            }
        } catch {
            let failure = error as? GoogleFontError
                ?? .networkUnavailable(family: family, failure: Self.fetchFailure(error))
            state.withLock { $0.downloadFailures[family] = failure }
        }
        return files
    }

    /// The Google Fonts file each of `faces` needs, from the cache or downloaded into it.
    ///
    /// The family's METADATA.pb comes from the cache when it is there, and is fetched
    /// and cached otherwise. A file the cache cannot be written to is kept in memory for
    /// the life of the process (``GoogleFontMemoryFallback``), and the first such
    /// failure prints one notice.
    ///
    /// - Parameters:
    ///   - family: The family.
    ///   - faces: Faces of `family`.
    /// - Returns: One file per distinct entry the faces map to, in file-name order.
    /// - Throws: ``GoogleFontError`` when the metadata cannot be had, and the fetcher's
    ///   error when a file cannot be downloaded.
    func googleFaceFiles(family: String, faces: Set<PenFontFace>) async throws -> [CachedFontFile] {
        let (metadata, license) = try await familyMetadata(family: family)
        let filenames = Set(faces.compactMap { metadata.entry(weight: $0.weight, style: $0.style)?.filename })
        var files: [CachedFontFile] = []
        for filename in filenames.sorted() {
            if let cached = cachedFile(family: family, named: filename) {
                files.append(cached)
                continue
            }
            let data = try await downloadFontFile(family: family, filename: filename, license: license)
            files.append(store(data, family: family, filename: filename))
        }
        return files
    }

    /// A family's METADATA.pb and the google/fonts license directory its files are
    /// under: from the cache when an earlier run left it there, fetched and cached
    /// otherwise.
    ///
    /// A cached METADATA whose license names no directory leaves the directory `nil`,
    /// and a download then probes each in turn.
    private func familyMetadata(family: String) async throws -> (GoogleFontMetadata, String?) {
        if let cached = cachedFile(family: family, named: GoogleFontCache.metadataFilename),
           let data = cached.contents,
           let metadata = try? GoogleFontMetadata.parse(data)
        {
            return (metadata, metadata.licenseDirectory)
        }
        let (metadata, license, data) = try await fetchMetadataData(family: family)
        _ = store(data, family: family, filename: GoogleFontCache.metadataFilename)
        return (metadata, license)
    }

    /// Downloads one font file, from `license`'s directory or, when that is unknown,
    /// the first license directory that has it.
    private func downloadFontFile(family: String, filename: String, license: String?) async throws -> Data {
        let directory = GoogleFontCache.directoryName(for: family)
        var lastError: Error = GoogleFontError.familyNotFound(family)
        for candidate in license.map({ [$0] }) ?? Self.licenseDirectories {
            var components = URLComponents(string: "\(Self.githubBaseURL)/\(candidate)/\(directory)/")!
            components.path += filename
            guard let url = components.url else { continue }
            do {
                return try await fetcher.fetch(url: url)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// The cache's copy of one of `family`'s files, on disk or in memory.
    private func cachedFile(family: String, named filename: String) -> CachedFontFile? {
        let url = cache.fontFileURL(family: family, filename: filename)
        if FileManager.default.fileExists(atPath: url.path) { return .disk(url) }
        let memory = GoogleFontMemoryFallback.files(rootDirectory: cache.rootDirectory, family: family)
        return memory[filename].map { .memory(name: filename, data: $0) }
    }

    /// Writes one of `family`'s files to the cache, or — when the cache cannot be
    /// written — to the in-process store, printing the one-time notice.
    private func store(_ data: Data, family: String, filename: String) -> CachedFontFile {
        do {
            try cache.cache(data: data, family: family, filename: filename)
            return .disk(cache.fontFileURL(family: family, filename: filename))
        } catch {
            GoogleFontMemoryFallback.store(data, rootDirectory: cache.rootDirectory, family: family, filename: filename)
            logCacheFallbackOnce()
            return .memory(name: filename, data: data)
        }
    }
}
