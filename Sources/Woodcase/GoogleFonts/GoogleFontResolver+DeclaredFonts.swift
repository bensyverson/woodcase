//
//  GoogleFontResolver+DeclaredFonts.swift
//  Woodcase
//

import Foundation

/// The fonts a document declares in its root `fonts` array, registered **ahead of**
/// Google Fonts.
///
/// A declaration names a family and a file (``PenFontDeclaration``). Registering that
/// file makes the family available to Core Text, and the Google chain skips a family
/// Core Text already resolves — so a declared face is measured and drawn wherever its
/// file can be reached, and Google Fonts is only asked for a declared family whose file
/// could not be.
///
/// Where a file comes from decides which path may reach it:
///
/// - **A local file** — a path relative to the .pen file, or absolute — is registered
///   straight from its URL, on every read. Core Text only registers file-backed fonts,
///   so the bytes are never loaded here.
/// - **A remote file** (`https://…`) is fetched into the font cache, under
///   `declared/`, only on the render path (``prepareFonts(for:relativeTo:diagnostics:)``),
///   and read back from that cache offline on every read
///   (``registerDeclaredFonts(of:relativeTo:diagnostics:)``) — a read never touches the
///   network, as `lint` promises.
///
/// A declaration that cannot be registered is reported once, naming the family and
/// where its file was looked for, at ``PenDiagnostic/Stage/fontResolution``.
public extension GoogleFontResolver {
    /// Registers the declared fonts this machine can reach without the network: local
    /// files, and remote ones already in the cache.
    ///
    /// - Parameters:
    ///   - document: The document whose ``PenDocument/fonts`` to register.
    ///   - sourceURL: The .pen file the document was read from, which a relative url
    ///     resolves against; `nil` for a document with no file.
    ///   - diagnostics: Where to report a declaration that cannot be registered. `nil`
    ///     writes the warning to standard error instead, once per family.
    /// - Returns: The declared families Core Text now resolves, sorted.
    @discardableResult
    func registerDeclaredFonts(
        of document: PenDocument,
        relativeTo sourceURL: URL?,
        diagnostics: PenDiagnosticCollector? = nil
    ) -> [String] {
        for declaration in document.fonts ?? [] {
            switch Self.location(of: declaration, relativeTo: sourceURL) {
            case let .local(url):
                register(declaration, from: url, diagnostics: diagnostics)
            case let .remote(url):
                if let cached = cachedDeclaredFontURL(for: declaration),
                   FileManager.default.fileExists(atPath: cached.path)
                {
                    register(declaration, from: cached, diagnostics: diagnostics)
                } else if !PenTextMeasurer.fontFamilyAvailable(declaration.name) {
                    reportDeclared(
                        declaration,
                        "is declared at \(url.absoluteString), which is not in the font cache yet; "
                            + "`woodcase render` or `woodcase shot` downloads it",
                        diagnostics: diagnostics
                    )
                }
            case .unresolvable:
                reportDeclared(
                    declaration,
                    "is declared at \"\(declaration.url)\", a relative path with no .pen file to resolve it against",
                    diagnostics: diagnostics
                )
            }
        }
        return Set((document.fonts ?? []).map(\.name))
            .filter(PenTextMeasurer.fontFamilyAvailable)
            .sorted()
    }

    /// Registers the declared fonts — fetching any remote one the cache lacks — and then
    /// runs the Google Fonts chain for every family still missing.
    ///
    /// The render path's entry point, for `shot`, `render` and the viewer: it may reach
    /// the network, because it is about to draw.
    ///
    /// - Parameters:
    ///   - document: The document to prepare, after expansion and variable resolution.
    ///   - sourceURL: The .pen file the document was read from, which a relative font
    ///     url resolves against; `nil` for a document with no file.
    ///   - diagnostics: Where to report what could not be resolved.
    func prepareFonts(
        for document: PenDocument,
        relativeTo sourceURL: URL?,
        diagnostics: PenDiagnosticCollector? = nil
    ) async {
        for declaration in document.fonts ?? [] {
            guard case let .remote(url) = Self.location(of: declaration, relativeTo: sourceURL),
                  let cached = cachedDeclaredFontURL(for: declaration),
                  !FileManager.default.fileExists(atPath: cached.path)
            else { continue }
            await download(declaration, from: url, into: cached, diagnostics: diagnostics)
        }
        registerDeclaredFonts(of: document, relativeTo: sourceURL, diagnostics: diagnostics)
        await prepareFonts(for: document, diagnostics: diagnostics)
    }

    /// Where a remote declaration's file is kept in the font cache: under `declared/`,
    /// named by a hash of its url, so two documents declaring the same url share it.
    ///
    /// - Parameter declaration: The declaration.
    /// - Returns: The cache file's URL, or `nil` when the declaration is not remote.
    func cachedDeclaredFontURL(for declaration: PenFontDeclaration) -> URL? {
        guard case let .remote(url) = Self.location(of: declaration, relativeTo: nil) else { return nil }
        var hasher = FNV1aHasher()
        hasher.combine(url.absoluteString)
        let ext = url.pathExtension.isEmpty ? "ttf" : url.pathExtension
        return cache.rootDirectory
            .appendingPathComponent(Self.declaredDirectoryName, isDirectory: true)
            .appendingPathComponent(hasher.hexString)
            .appendingPathExtension(ext)
    }
}

public extension GoogleFontResolver {
    /// Registers the declared fonts that are local files, with no resolver and no
    /// cache — what a document read with no ``PenReadContext/fonts`` settles through.
    ///
    /// A declared file is the document's own data, not this machine's cache, so a read
    /// that consults no cache still measures in it. Remote declarations need the cache,
    /// and are left alone; nothing is reported, because a read with no resolver
    /// reports nothing about fonts at all.
    ///
    /// - Parameters:
    ///   - document: The document whose ``PenDocument/fonts`` to register.
    ///   - sourceURL: The .pen file a relative url resolves against, or `nil`.
    static func registerLocalDeclaredFonts(of document: PenDocument, relativeTo sourceURL: URL?) {
        for declaration in document.fonts ?? [] {
            guard case let .local(url) = location(of: declaration, relativeTo: sourceURL),
                  FileManager.default.fileExists(atPath: url.path)
            else { continue }
            PenFontRegistry.registerFont(at: url)
        }
    }
}

extension GoogleFontResolver {
    /// The directory, inside the font cache, remote declared fonts are kept in.
    static let declaredDirectoryName = "declared"

    /// Where a declaration's file is.
    enum DeclaredLocation {
        /// A file on this machine.
        case local(URL)
        /// A file to fetch.
        case remote(URL)
        /// A relative path with no .pen file to resolve it against, or a blank url.
        case unresolvable
    }

    /// Where a declaration's file is, resolving a relative path against the .pen
    /// file's directory.
    ///
    /// - Parameters:
    ///   - declaration: The declaration.
    ///   - sourceURL: The .pen file, or `nil`.
    /// - Returns: The location.
    static func location(of declaration: PenFontDeclaration, relativeTo sourceURL: URL?) -> DeclaredLocation {
        let directory = sourceURL?.deletingLastPathComponent()
        let isRelative = !declaration.url.hasPrefix("/")
            && declaration.url.prefixMatch(of: #/[A-Za-z][A-Za-z0-9+.\-]*:\/\//#) == nil
        if isRelative, directory == nil { return .unresolvable }
        guard let url = declaration.resolvedURL(relativeTo: directory ?? URL(fileURLWithPath: "/")) else {
            return .unresolvable
        }
        switch url.scheme?.lowercased() {
        case "http", "https": return .remote(url)
        case "file", nil: return .local(url)
        default: return .unresolvable
        }
    }

    /// Registers one declaration's file, and reports it if Core Text does not then
    /// resolve the family it names.
    private func register(_ declaration: PenFontDeclaration, from url: URL, diagnostics: PenDiagnosticCollector?) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            reportDeclared(declaration, "is declared at \(url.path), which does not exist", diagnostics: diagnostics)
            return
        }
        registerFont(at: url)
        guard PenTextMeasurer.fontFamilyAvailable(declaration.name) else {
            reportDeclared(
                declaration,
                "is declared at \(url.path), but that file is not a font Core Text can register "
                    + "under the family name \"\(declaration.name)\"",
                diagnostics: diagnostics
            )
            return
        }
    }

    /// Fetches a remote declaration into the cache, reporting a failure rather than
    /// throwing: a font that cannot be downloaded falls back like any other.
    private func download(
        _ declaration: PenFontDeclaration,
        from url: URL,
        into cached: URL,
        diagnostics: PenDiagnosticCollector?
    ) async {
        let data: Data
        do {
            data = try await fetcher.fetch(url: url)
        } catch {
            reportDeclared(
                declaration,
                "is declared at \(url.absoluteString), which could not be downloaded (\(Self.fetchFailure(error)))",
                diagnostics: diagnostics
            )
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: cached.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: cached, options: .atomic)
        } catch {
            // An unwritable cache is never a reason to lose the face: register the bytes
            // from a scratch file for the life of the process, as a Google font would be.
            logCacheFallbackOnce()
            registerFont(data: data)
        }
    }

    /// Reports a declaration that could not be registered, once per family on standard
    /// error when no collector is given.
    private func reportDeclared(_ declaration: PenFontDeclaration, _ problem: String, diagnostics: PenDiagnosticCollector?) {
        let fallback = PenTextMeasurer.defaultFontFamily
        reportFallback(
            family: declaration.name,
            message: "font \"\(declaration.name)\" \(problem); its text is measured and drawn in \(fallback) "
                + "unless Google Fonts has a family of that name.",
            diagnostics: diagnostics
        )
    }
}
