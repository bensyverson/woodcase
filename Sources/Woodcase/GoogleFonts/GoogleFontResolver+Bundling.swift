//
//  GoogleFontResolver+Bundling.swift
//  Woodcase
//

import CoreText
import Foundation

/// Which files a package generated from a document carries for its text faces.
///
/// The chain is the renderer's, so a package draws in the faces `woodcase render` draws
/// with: a family the document declares (``PenDocument/fonts``) is its declared files; a
/// family the operating system ships is left to it; any other family is the Google Fonts
/// file of each face its views draw (``GoogleFontMetadata/entry(weight:style:)``) — from
/// the cache, downloaded into it first when it lacks one — and no file of a face nothing
/// draws. A family installed on this machine but not shipped with the OS is
/// still taken from Google Fonts, never copied from the machine's own fonts: a person's
/// licensed font is not the package's to redistribute, and a Google family's licence
/// lets it travel.
///
/// Nothing here registers a font; the files are the caller's to copy.
public extension GoogleFontResolver {
    /// The font files a generated package bundles for `faces`, the families it leaves to
    /// the system, and why any other family has no file.
    ///
    /// - Parameters:
    ///   - faces: The faces the package's views set (``EmitResult/fontFaces``).
    ///   - document: The document, whose ``PenDocument/fonts`` declarations come first.
    ///   - sourceURL: The .pen file a relative declared url resolves against, or `nil`.
    /// - Returns: The bundle; a family with no file is a ``PenFontBundle/Missing``, never
    ///   an error.
    func fontBundle(
        for faces: Set<PenFontFace>,
        declaredIn document: PenDocument,
        relativeTo sourceURL: URL?
    ) async -> PenFontBundle {
        var bundle = PenFontBundle()
        var files: Set<URL> = []
        for (family, familyFaces) in Dictionary(grouping: faces, by: \.family).sorted(by: { $0.key < $1.key }) {
            let declarations = (document.fonts ?? []).filter { $0.name == family }
            if !declarations.isEmpty {
                for declaration in declarations {
                    switch await declaredFile(declaration, relativeTo: sourceURL) {
                    case let .found(urls): files.formUnion(urls)
                    case let .missing(missing): bundle.missing.append(missing)
                    }
                }
            } else if Self.isSystemFamily(family) {
                bundle.systemFamilies.append(family)
            } else {
                switch await googleFiles(family: family, faces: Set(familyFaces)) {
                case let .found(urls): files.formUnion(urls)
                case let .missing(missing): bundle.missing.append(missing)
                }
            }
        }
        bundle.files = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return bundle
    }
}

/// What one lookup for a package's font files found.
private enum FontLookup {
    /// The files to bundle.
    case found([URL])
    /// No file, and why.
    case missing(PenFontBundle.Missing)
}

extension GoogleFontResolver {
    /// Whether the operating system ships `family`: Core Text resolves it, from a file
    /// under `/System/` or `/Library/Apple/`. A family installed by a person or an app,
    /// or registered from the font cache, is not.
    static func isSystemFamily(_ family: String) -> Bool {
        FontRegistryGate.withAccess {
            let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family] as CFDictionary)
            let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
            guard (CTFontCopyFamilyName(font) as String).lowercased() == family.lowercased(),
                  let url = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL
            else { return false }
            return url.path.hasPrefix("/System/") || url.path.hasPrefix("/Library/Apple/")
        }
    }

    /// A declared font's file: the local file, or the cached copy of a remote one,
    /// fetched into the cache when it is not there yet.
    private func declaredFile(
        _ declaration: PenFontDeclaration, relativeTo sourceURL: URL?
    ) async -> FontLookup {
        let missing = { (problem: String) in
            PenFontBundle.Missing(family: declaration.name, reason: "font \"\(declaration.name)\" \(problem); the package does not bundle it")
        }
        switch Self.location(of: declaration, relativeTo: sourceURL) {
        case let .local(url):
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .missing(missing("is declared at \(url.path), which does not exist"))
            }
            return .found([url])
        case let .remote(url):
            guard let cached = cachedDeclaredFontURL(for: declaration) else {
                return .missing(missing("is declared at \(url.absoluteString), which has no place in the font cache"))
            }
            if !FileManager.default.fileExists(atPath: cached.path) {
                do {
                    let data = try await fetcher.fetch(url: url)
                    try FileManager.default.createDirectory(at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: cached, options: .atomic)
                } catch {
                    return .missing(missing("is declared at \(url.absoluteString), which could not be downloaded into the font cache"))
                }
            }
            return .found([cached])
        case .unresolvable:
            return .missing(missing("is declared at \"\(declaration.url)\", which is not a path or URL a file can be read from"))
        }
    }

    /// The Google Fonts file of each of `faces`, downloading into the cache any it lacks.
    private func googleFiles(family: String, faces: Set<PenFontFace>) async -> FontLookup {
        let unwritable = PenFontBundle.Missing(
            family: family,
            reason: "font \"\(family)\" was downloaded but could not be written to the font cache at "
                + "\(cache.rootDirectory.path); the package does not bundle it"
        )
        do {
            var urls: [URL] = []
            for file in try await googleFaceFiles(family: family, faces: faces) {
                guard case let .disk(url) = file else { return .missing(unwritable) }
                urls.append(url)
            }
            guard !urls.isEmpty else {
                return .missing(PenFontBundle.Missing(family: family, reason: "font \"\(family)\" has no files on Google Fonts; the package does not bundle it"))
            }
            return .found(urls)
        } catch let error as GoogleFontError {
            return .missing(PenFontBundle.Missing(family: family, reason: Self.bundlingFailure(family: family, error)))
        } catch {
            return .missing(PenFontBundle.Missing(family: family, reason: Self.bundlingFailure(
                family: family, .networkUnavailable(family: family, failure: Self.fetchFailure(error))
            )))
        }
    }

    /// What to say about a Google family that could not be fetched for a package.
    private static func bundlingFailure(family: String, _ error: GoogleFontError) -> String {
        switch error {
        case .familyNotFound:
            "font \"\(family)\" is not shipped with the OS, and Google Fonts has no family named \"\(family)\"; "
                + "the package does not bundle it"
        case let .networkUnavailable(_, failure):
            "font \"\(family)\" could not be downloaded from Google Fonts: \(failure.reasonPhrase); "
                + "the package does not bundle it"
        default:
            "font \"\(family)\" could not be resolved from Google Fonts; the package does not bundle it"
        }
    }
}
