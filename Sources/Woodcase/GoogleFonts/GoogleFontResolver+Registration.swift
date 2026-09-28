//
//  GoogleFontResolver+Registration.swift
//  Woodcase
//

import Foundation

/// Cache lookup and CoreText registration — the offline half of resolution, and the
/// step that makes a resolved font actually visible to text measurement.
extension GoogleFontResolver {
    /// Makes one family's faces available from what this machine already holds, or says
    /// the family cannot be.
    ///
    /// The system registry first, then every file the caches hold for the family —
    /// never the network. A face already registered, or a family the operating system
    /// ships, needs nothing; otherwise every cached file of the family is registered,
    /// since each is one of its faces. Availability is re-checked *after* registration
    /// rather than assumed from it: a cache file that turns out to carry a different
    /// family name, or bytes Core Text refuses, must read as a fallback, because that is
    /// what the measurement will be.
    ///
    /// A family this cannot place is deliberately **not** remembered: a miss here means
    /// "not on disk", not "attempted", and a `render` later in the same process still has
    /// to be able to fetch it. A face the cache lacks while its family is placed is not
    /// reported — the family draws, in its nearest face, until a render fetches the
    /// right one.
    ///
    /// - Parameters:
    ///   - family: The font family name.
    ///   - faces: The faces of `family` the document draws.
    /// - Returns: `true` when Core Text now resolves that exact family.
    func resolveFromCache(family: String, faces: Set<PenFontFace>) -> Bool {
        let settled = state.withLock { $0.placedFamilies.contains(family) && faces.isSubset(of: $0.offlineFaces) }
        if settled { return true }
        if PenTextMeasurer.availableFaces(faces) != faces, !Self.isSystemFamily(family) {
            registerCachedFiles(family: family)
        }
        guard PenTextMeasurer.fontFamilyAvailable(family) else { return false }
        state.withLock {
            $0.placedFamilies.insert(family)
            $0.offlineFaces.formUnion(faces)
        }
        return true
    }

    /// A font file found in, or just written to, one of the caches.
    enum CachedFontFile: Friendly {
        /// A file on disk, in the font cache.
        case disk(URL)
        /// Bytes held only in the in-process fallback store, under their google/fonts
        /// file name.
        case memory(name: String, data: Data)

        /// The file's name in the google/fonts repository.
        var name: String {
            switch self {
            case let .disk(url): url.lastPathComponent
            case let .memory(name, _): name
            }
        }

        /// The file's bytes, read from disk when it lives there.
        var contents: Data? {
            switch self {
            case let .disk(url): try? Data(contentsOf: url)
            case let .memory(_, data): data
            }
        }
    }

    /// Registers every font file the caches hold for `family`, each once per resolver.
    ///
    /// - Parameter family: The font family name.
    /// - Returns: The registered files' URLs — a memory-only file's scratch copy.
    @discardableResult
    func registerCachedFiles(family: String) -> [URL] {
        let memory = GoogleFontMemoryFallback.files(rootDirectory: cache.rootDirectory, family: family)
            .filter { $0.key != GoogleFontCache.metadataFilename }
            .sorted { $0.key < $1.key }
            .map { CachedFontFile.memory(name: $0.key, data: $0.value) }
        return (cache.fontFileURLs(family: family).map(CachedFontFile.disk) + memory)
            .compactMap { register($0, family: family) }
    }

    /// Registers one cached file, unless this resolver already has.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - family: Its family, which scopes a memory file's scratch copy.
    /// - Returns: The URL Core Text was given, or `nil` when a memory file could not be
    ///   staged.
    @discardableResult
    func register(_ file: CachedFontFile, family: String) -> URL? {
        switch file {
        case let .disk(url):
            let isNew = state.withLock { $0.registeredFiles.insert(url).inserted }
            if isNew { registerFont(at: url) }
            return url
        case let .memory(name, data):
            let key = "\(GoogleFontCache.directoryName(for: family))/\(name)"
            if let staged = state.withLock({ $0.stagedMemoryFiles[key] }) { return staged }
            guard let staged = registerFont(data: data) else { return nil }
            state.withLock { $0.stagedMemoryFiles[key] = staged }
            return staged
        }
    }

    /// How many times this resolver has actually printed the cache-fallback notice —
    /// 0 or 1, since ``logCacheFallbackOnce()`` only ever increments it once. Not
    /// `private`, so a test can confirm "once, never per font" without capturing real
    /// standard error, the way ``FontResolutionCache``'s compute counters do for its
    /// own cache.
    var cacheFallbackNoticeCount: Int {
        state.withLock { $0.cacheFallbackNoticeCount }
    }

    /// Prints, once per resolver, the notice that the on-disk font cache could not be
    /// written.
    ///
    /// In practice this is once per *process*, since ``shared`` is the only instance
    /// any caller uses — but the guard lives on the instance so two resolvers in the
    /// same test do not interfere with each other. Never once per font: a document
    /// naming a dozen fonts that all miss the same unwritable directory would
    /// otherwise print the same line a dozen times.
    func logCacheFallbackOnce() {
        let shouldLog = state.withLock { current -> Bool in
            guard current.cacheFallbackNoticeCount == 0 else { return false }
            current.cacheFallbackNoticeCount += 1
            return true
        }
        guard shouldLog else { return }
        StandardErrorLine.write("""
        woodcase: cannot write the font cache at \(cache.rootDirectory.path); caching \
        downloaded fonts in memory for this process instead.
        """)
    }

    /// Registers a TTF file with CoreText for the current process, through
    /// ``PenFontRegistry/registerFont(at:)`` — the one registration every resolver path,
    /// and a declared font read with no resolver, goes through. It takes a URL because
    /// Core Text silently refuses fonts registered from data; `GoogleFontResolverTests`
    /// pins the working path.
    ///
    /// An "already registered" answer is as good as success — the face is available
    /// either way, which is all a caller needs — but only an added face moves the font
    /// generation.
    ///
    /// - Parameter url: The TTF file to register.
    func registerFont(at url: URL) {
        PenFontRegistry.registerFont(at: url)
    }

    /// Registers TTF data that has no on-disk home by giving it one.
    ///
    /// CoreText only registers file-backed fonts (see ``registerFont(at:)``), so the
    /// bytes are written to a scratch file first. This is the memory-fallback case:
    /// the real cache directory was unwritable, and ``ScratchDirectory`` is the next
    /// best place for the life of the process — never
    /// `FileManager.default.temporaryDirectory` directly, which ignores `$TMPDIR` on
    /// macOS and lands somewhere the Claude Code sandbox denies writing to.
    ///
    /// - Parameters:
    ///   - data: The TTF bytes to register.
    ///   - environment: The environment ``ScratchDirectory`` reads. Defaults to this
    ///     process's; a test overrides it to prove staging follows `$TMPDIR` without
    ///     mutating the real environment.
    /// - Returns: The scratch file registered, or `nil` when it could not be written.
    @discardableResult
    func registerFont(data: Data, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let url = ScratchDirectory.url(in: environment)
            .appendingPathComponent("woodcase-font-\(UUID().uuidString)")
            .appendingPathExtension("ttf")
        guard (try? data.write(to: url)) != nil else { return nil }
        registerFont(at: url)
        return url
    }
}
