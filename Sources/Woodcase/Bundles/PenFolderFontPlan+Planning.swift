//
//  PenFolderFontPlan+Planning.swift
//  Woodcase
//

import Foundation

public extension PenFolderFontPlan {
    /// The plan for a document: every family its text draws, classified.
    ///
    /// The document's instances are expanded (``PenRefExpander/Purpose/canvas``) and its
    /// variables resolved under every theme (``ThemeCoverage``), so the families are the
    /// ones a reader can see. Each is then asked, in order:
    ///
    /// 1. **Declared?** A root `fonts` entry of the name makes it ``Source/declared``,
    ///    with its local files that exist; one whose only local file is missing is
    ///    ``Source/missing``. A declared local file Apple made (``PenFontMaker/isApple``)
    ///    makes the family ``Source/system`` instead.
    /// 2. **The system's?** Either ``GoogleFontResolver/isSystemFamily(_:)`` — Core Text
    ///    resolves it from a file under `/System/` or `/Library/Apple/` — or Apple made
    ///    the font Core Text draws a face of it in, wherever that file is: the SF Pro and
    ///    New York families from Apple's developer downloads live in `/Library/Fonts`,
    ///    and Apple's license lets nobody pass them on. Who made a font is read from the
    ///    font itself — its OS/2 vendor ID and its name table's manufacturer and
    ///    copyright — never from a list of family names.
    /// 3. **On Google Fonts?** The resolver's cached METADATA, or a fetch of it.
    /// 4. **Installed?** Core Text resolves each face drawn to a file of the family
    ///    elsewhere, which is the file that would ship.
    /// 5. Otherwise ``Source/missing``.
    ///
    /// - Parameters:
    ///   - document: The document, unexpanded and unresolved.
    ///   - sourceURL: The .pen file a relative declared url resolves against, or `nil`.
    ///   - fonts: The resolver asked whether Google Fonts has a family.
    /// - Returns: The plan.
    static func make(
        for document: PenDocument,
        relativeTo sourceURL: URL?,
        fonts: GoogleFontResolver
    ) async -> PenFolderFontPlan {
        await make(
            expanded: PenRefExpander.expand(document, for: .canvas),
            declarations: document.fonts ?? [],
            relativeTo: sourceURL,
            fonts: fonts
        )
    }
}

extension PenFolderFontPlan {
    /// The plan for a document already expanded, imported instances included.
    ///
    /// - Parameters:
    ///   - expanded: The document with every `ref` expanded, unresolved.
    ///   - declarations: The document's own root `fonts` declarations.
    ///   - sourceURL: The .pen file a relative declared url resolves against, or `nil`.
    ///   - fonts: The resolver asked whether Google Fonts has a family.
    /// - Returns: The plan.
    static func make(
        expanded: PenDocument,
        declarations: [PenFontDeclaration],
        relativeTo sourceURL: URL?,
        fonts: GoogleFontResolver
    ) async -> PenFolderFontPlan {
        let (faces, coverage) = drawnFaces(in: expanded)
        var families: [Family] = []
        for (name, familyFaces) in Dictionary(grouping: faces, by: \.family).sorted(by: { $0.key < $1.key }) {
            await families.append(family(
                name,
                faces: familyFaces.sorted(),
                declarations: declarations.filter { $0.name == name },
                relativeTo: sourceURL,
                fonts: fonts
            ))
        }
        return PenFolderFontPlan(families: families, themeCoverage: coverage)
    }

    /// One family's row, by the chain ``make(for:relativeTo:fonts:)`` lists.
    private static func family(
        _ name: String,
        faces: [PenFontFace],
        declarations: [PenFontDeclaration],
        relativeTo sourceURL: URL?,
        fonts: GoogleFontResolver
    ) async -> Family {
        if !declarations.isEmpty {
            var files: [FontFile] = []
            var isDeclaredRemotely = false
            var isAppleMade = false
            for declaration in declarations {
                switch GoogleFontResolver.location(of: declaration, relativeTo: sourceURL) {
                case let .local(url) where FileManager.default.fileExists(atPath: url.path):
                    let data = try? Data(contentsOf: url, options: .mappedIfSafe)
                    if data.flatMap(PenFontMaker.init(fontFile:))?.isApple == true { isAppleMade = true }
                    files.append(declaredFile(declaration, at: url, data: data))
                case .remote:
                    isDeclaredRemotely = true
                case .local, .unresolvable:
                    break
                }
            }
            if isAppleMade {
                return Family(name: name, faces: faces, source: .system, files: [])
            }
            let source: Source = files.isEmpty && !isDeclaredRemotely ? .missing : .declared
            return Family(name: name, faces: faces, source: source, files: sortedUnique(files))
        }
        if GoogleFontResolver.isSystemFamily(name) || faces.contains(where: isAppleMade) {
            return Family(name: name, faces: faces, source: .system, files: [])
        }
        let answer = await googleFontsAnswer(for: name, fonts: fonts)
        if answer == .listed {
            return Family(name: name, faces: faces, source: .googleFonts, files: [], googleFonts: answer)
        }
        let installed = sortedUnique(faces.compactMap(installedFile))
        return Family(
            name: name, faces: faces, source: installed.isEmpty ? .missing : .installed,
            files: installed, googleFonts: answer
        )
    }

    /// Whether Google Fonts has a family, from the resolver's cache or a fetch.
    private static func googleFontsAnswer(for family: String, fonts: GoogleFontResolver) async -> GoogleFontsAnswer {
        do {
            _ = try await fonts.familyMetadata(family: family)
            return .listed
        } catch GoogleFontError.familyNotFound {
            return .notListed
        } catch {
            return .unreachable
        }
    }

    /// `files` each once by url, sorted by file name.
    private static func sortedUnique(_ files: [FontFile]) -> [FontFile] {
        var seen: Set<URL> = []
        return files
            .filter { seen.insert($0.url.standardizedFileURL).inserted }
            .sorted { ($0.url.lastPathComponent, $0.url.path) < ($1.url.lastPathComponent, $1.url.path) }
    }

    /// A declared file as a row lists it: the declaration's style and weight, and what
    /// the file — whose bytes are `data`, or `nil` when unreadable — says about its
    /// family, embedding and license.
    private static func declaredFile(_ declaration: PenFontDeclaration, at url: URL, data: Data?) -> FontFile {
        let embedding = data.flatMap(PenFontEmbedding.init(fontFile:))
        let names = FontFileNames(fileAt: url)
        return FontFile(
            url: url,
            familyName: names?.family ?? declaration.name,
            style: declaration.style ?? .normal,
            weight: declaration.weight ?? .single(PenFontDeclaration.regularWeight),
            embedding: embedding,
            license: names?.license
        )
    }
}
