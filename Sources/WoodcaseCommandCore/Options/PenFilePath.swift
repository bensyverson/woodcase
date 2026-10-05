//
//  PenFilePath.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// A document named on the command line: a bare `.pen` file or a `.umbra` bundle.
///
/// Parsing never fails: any string is a path, and whether it names a readable file is
/// a question about the *world*, not about the invocation. Asking it at parse time
/// would make a missing file a `ValidationError`, and ArgumentParser turns those into
/// a usage exit — but the usage was fine. So a verb calls ``existingFile()`` when it
/// runs, and a missing file is ``ExitCode/targetFailure`` (4) with a message naming
/// the path.
///
/// ```swift
/// @Argument(help: "The .pen file to read.") var file: PenFilePath
/// // …
/// let url = try file.existingFile()
/// ```
struct PenFilePath: ExpressibleByArgument, Friendly, CustomStringConvertible {
    /// Wraps a path, expanding a leading `~`.
    ///
    /// - Parameter path: The path as typed. A leading tilde is expanded, because a
    ///   quoted `"~/design.pen"` reaches the process unexpanded by the shell.
    init(_ path: String) {
        self.path = (path as NSString).expandingTildeInPath
    }

    /// Wraps an argument. Never fails.
    ///
    /// - Parameter argument: The path as typed.
    init?(argument: String) {
        self.init(argument)
    }

    /// The path, with any leading tilde expanded.
    let path: String

    /// The path as a file URL, whether or not anything is there.
    var url: URL {
        URL(fileURLWithPath: path)
    }

    /// The path, for a message.
    var description: String {
        path
    }

    /// Checks that the path names a readable document, and returns the `.pen` to open.
    ///
    /// A `.umbra` bundle — or the `document.pen` inside one — answers with its
    /// `document.pen` (``Woodcase/PenLocation``), so every verb reads, writes, renders and
    /// resolves relative paths inside the bundle without knowing it is one. A bare `.pen`
    /// answers with itself, as it always has, after a warning on standard error when a
    /// bundle beside it was converted from it (``Woodcase/PenBundle/ConvertedFrom``).
    ///
    /// - Returns: The `.pen` file's URL.
    /// - Throws: ``CommandFailure`` with ``ExitCode/targetFailure`` when the path
    ///   names nothing, names a directory that is not a bundle, names a bundle with no
    ///   `document.pen`, or names a file this process cannot read.
    func existingFile() throws -> URL {
        let location = PenLocation(url)
        if location.kind == .bundle {
            return try existingBundleDocument(location)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            let parent = url.deletingLastPathComponent().path
            throw CommandFailure(
                message: "Cannot open \(path): no such file. Check the path — `ls \(parent)` "
                    + "lists what is there — or `woodcase new \(path)` creates it.",
                exitCode: .targetFailure
            )
        }
        guard !isDirectory.boolValue else {
            throw CommandFailure(
                message: "Cannot open \(path): it is a directory. Name one .pen file.",
                exitCode: .targetFailure
            )
        }
        guard FileManager.default.isReadableFile(atPath: path) else {
            throw CommandFailure(
                message: "Cannot open \(path): permission denied. Check the file's permissions.",
                exitCode: .targetFailure
            )
        }
        if let warning = PenBundle.ConvertedFrom.warning(for: url) {
            StandardError.write("woodcase: " + warning)
        }
        return url
    }

    /// The `document.pen` of the bundle the path names, once it is known to be there.
    private func existingBundleDocument(_ location: PenLocation) throws -> URL {
        var isDirectory: ObjCBool = false
        guard let bundle = location.bundle,
              FileManager.default.fileExists(atPath: bundle.path, isDirectory: &isDirectory)
        else {
            throw CommandFailure(
                message: "Cannot open \(path): no such bundle. Check the path — `ls \(location.containingDirectory.path)` "
                    + "lists what is there — or `woodcase new \(path)` creates it.",
                exitCode: .targetFailure
            )
        }
        guard isDirectory.boolValue else {
            throw CommandFailure(
                message: "Cannot open \(path): a .umbra bundle is a directory, and this is a file.",
                exitCode: .targetFailure
            )
        }
        let document = location.document
        guard FileManager.default.fileExists(atPath: document.path) else {
            throw CommandFailure(
                message: "Cannot open \(path): the bundle holds no \(PenLocation.documentName). "
                    + "`ls \(bundle.path)` lists what is there.",
                exitCode: .targetFailure
            )
        }
        guard FileManager.default.isReadableFile(atPath: document.path) else {
            throw CommandFailure(
                message: "Cannot open \(document.path): permission denied. Check the file's permissions.",
                exitCode: .targetFailure
            )
        }
        return document
    }
}
