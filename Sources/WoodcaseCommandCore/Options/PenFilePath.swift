//
//  PenFilePath.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// A `.pen` file named on the command line.
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

    /// Checks that the path names a readable file, and returns its URL.
    ///
    /// - Returns: The file's URL.
    /// - Throws: ``CommandFailure`` with ``ExitCode/targetFailure`` when the path
    ///   names nothing, names a directory, or names a file this process cannot read.
    func existingFile() throws -> URL {
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
        return url
    }
}
