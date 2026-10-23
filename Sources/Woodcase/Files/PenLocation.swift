//
//  PenLocation.swift
//  Woodcase
//

import Foundation

/// Where a document named by a path lives: the `.pen` file to read and write, the folder
/// its relative paths resolve against, and where its own state goes.
///
/// A document is either a **bare `.pen` file** or a **`.umbra` bundle** — a directory
/// holding `document.pen`, the `images/` and `fonts/` it uses, a `history/` with one
/// shared log file per writer, and a `.woodcase/` with local, uncommitted state — views,
/// cursors and temporary files. Every entry point that takes a document's path
/// resolves it here — every CLI verb, ``PenParser/parse(contentsOf:diagnostics:)``,
/// ``PenFileTransaction``, ``ActivityLogLocation``, ``FileWatcher`` — so a bundle works
/// wherever a `.pen` does, and there is one rule rather than one per call site.
///
/// ```swift
/// let location = PenLocation(URL(fileURLWithPath: "Design.umbra"))
/// location.document            // Design.umbra/document.pen
/// location.resourceDirectory   // Design.umbra — "./images/hero.png" resolves here
/// location.historyDirectory    // Design.umbra/history
/// location.stateDirectory      // Design.umbra/.woodcase
/// ```
///
/// The answer comes from the path alone, never from the disk: a path ending in `.umbra`
/// is a bundle, and so is a `document.pen` directly inside one, so naming either reaches
/// the same document. Any other path is a bare file and is returned exactly as given, so
/// a bare `.pen` behaves as it always has. See <doc:PenBundles>.
public struct PenLocation: Friendly {
    /// What kind of document a path names.
    public enum Kind: String, Friendly, CaseIterable {
        /// A bare `.pen` file.
        case file
        /// A `.umbra` bundle directory.
        case bundle
    }

    /// Resolves a path someone named.
    ///
    /// - Parameter url: A bare `.pen`, a `.umbra` bundle, or the `document.pen` inside
    ///   one. Nothing need exist there yet.
    public init(_ url: URL) {
        if Self.isBundle(url) {
            kind = .bundle
            self.url = Self.directoryURL(url)
        } else if url.lastPathComponent == Self.documentName, Self.isBundle(url.deletingLastPathComponent()) {
            kind = .bundle
            self.url = Self.directoryURL(url.deletingLastPathComponent())
        } else {
            kind = .file
            self.url = url
        }
    }

    /// Whether the path names a bundle or a bare file.
    public let kind: Kind

    /// The document as named: the bundle directory for a bundle, however it was spelled,
    /// or the bare file exactly as given.
    public let url: URL

    /// The bundle's file extension, `umbra`.
    public static let bundleExtension = "umbra"

    /// The name of the `.pen` file inside every bundle. Always this name, because the
    /// bundle itself may be renamed at any time.
    public static let documentName = "document.pen"

    /// The bundle folder image fills are copied into.
    public static let imagesDirectoryName = "images"

    /// The bundle folder declared fonts are copied into.
    public static let fontsDirectoryName = "fonts"

    /// Whether a path names a bundle, judged from its extension alone.
    ///
    /// - Parameter url: The path.
    /// - Returns: `true` when the last component ends in `.umbra`, in any case.
    public static func isBundle(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == bundleExtension
    }

    /// The `.pen` file to read and write: `document.pen` inside a bundle, or the bare
    /// file itself.
    public var document: URL {
        bundle?.appendingPathComponent(Self.documentName, isDirectory: false) ?? url
    }

    /// The bundle directory, or `nil` for a bare file.
    public var bundle: URL? {
        kind == .bundle ? url : nil
    }

    /// The folder relative paths in the document — image fills, declared fonts,
    /// imports — resolve against: the folder holding ``document``.
    public var resourceDirectory: URL {
        document.deletingLastPathComponent()
    }

    /// The folder the document sits in, as a person sees it: the bundle's parent, or
    /// the bare file's. Output that is not part of the document — a render, an export —
    /// goes here by default.
    public var containingDirectory: URL {
        url.deletingLastPathComponent()
    }

    /// The document's name without its extension: `Design` for `Design.umbra` and for
    /// `Design.pen`.
    public var name: String {
        url.deletingPathExtension().lastPathComponent
    }

    /// The bundle's own `.woodcase/` — local state that is never committed: views,
    /// cursors and temporary files — or `nil` for a bare file, whose log
    /// ``ActivityLogLocation`` places by the project.
    public var stateDirectory: URL? {
        bundle?.appendingPathComponent(ActivityLog.directoryName, isDirectory: true)
    }

    /// The bundle's shared history, `history/`: one append-only file per writer, meant
    /// to be committed and synced with the document — or `nil` for a bare file. See
    /// <doc:WoodcaseActivityLog>.
    public var historyDirectory: URL? {
        bundle?.appendingPathComponent(ActivityLog.historyDirectoryName, isDirectory: true)
    }

    /// Where a write stages its temporary file before renaming it over ``document``:
    /// the bundle's ``stateDirectory``, so a crash never leaves debris beside
    /// `document.pen`; beside the bare file otherwise. Always on the document's volume,
    /// so the rename is atomic.
    public var temporaryDirectory: URL {
        stateDirectory ?? resourceDirectory
    }

    /// A bundle path as a directory URL, standardized and without a trailing slash, so
    /// every spelling of one bundle compares equal.
    private static func directoryURL(_ url: URL) -> URL {
        URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true)
    }
}
