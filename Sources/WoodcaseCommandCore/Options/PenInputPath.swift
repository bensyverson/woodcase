//
//  PenInputPath.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// A `.pen` file *or* a directory to search, named on the command line.
///
/// The sibling of ``PenFilePath``, for a verb that takes both: `migrate` walks a
/// directory tree as readily as it rewrites a single file, so ``PenFilePath`` — whose
/// `existingFile()` refuses a directory outright — does not fit. The rules are
/// otherwise identical. Parsing never fails, because any string is a path, and whether
/// something is *there* is a question about the world, not about the invocation:
/// asking it at parse time would make a missing path a `ValidationError`, which
/// ArgumentParser turns into a usage exit with a usage block, blaming a command line
/// that was fine. So a verb calls ``existingTarget()`` when it runs.
///
/// The two refusals land on different codes on purpose:
///
/// | The path | Code |
/// |---|---|
/// | names nothing | ``ExitCode/targetFailure`` (4) — the same sentence ``PenFilePath`` uses |
/// | names a file that is not a .pen file | ``ExitCode/usage`` (2) — the wrong *kind* of argument |
///
/// ```swift
/// @Argument(help: "The .pen files, or directories to search recursively.")
/// var inputs: [PenInputPath]
/// // …
/// for input in inputs {
///     switch try input.existingTarget() {
///     case let .file(url): …
///     case let .directory(url): …
///     }
/// }
/// ```
///
/// Readability is deliberately *not* checked here, unlike ``PenFilePath``: a verb that
/// walks a tree reports one unreadable file and carries on with the rest, and a check
/// up front would turn that into a run that migrates nothing.
struct PenInputPath: ExpressibleByArgument, Friendly, CustomStringConvertible {
    /// What a path turned out to name.
    enum Target: Friendly {
        /// A `.pen` file to work on directly.
        case file(URL)

        /// A directory to search for `.pen` files.
        case directory(URL)
    }

    /// Wraps a path, expanding a leading `~`.
    ///
    /// - Parameter path: The path as typed. A leading tilde is expanded, because a
    ///   quoted `"~/designs"` reaches the process unexpanded by the shell.
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

    /// Checks that the path names something usable, and says which of the two it is.
    ///
    /// - Returns: The file or directory the path names, standardized.
    /// - Throws: ``CommandFailure`` with ``ExitCode/targetFailure`` when the path names
    ///   nothing, and with ``ExitCode/usage`` when it names a file that is not a `.pen`
    ///   file.
    func existingTarget() throws -> Target {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw CommandFailure(
                message: "Cannot open \(path): no such file. Check the path — `ls \(parent)` "
                    + "lists what is there.",
                exitCode: .targetFailure
            )
        }
        guard !isDirectory.boolValue else {
            return .directory(url.standardizedFileURL)
        }
        guard url.pathExtension == "pen" else {
            throw CommandFailure(
                message: "Cannot open \(path): it is not a .pen file. Name a .pen file, or a "
                    + "directory to search — `ls \(parent)/*.pen` lists the .pen files there.",
                exitCode: .usage
            )
        }
        return .file(url.standardizedFileURL)
    }

    /// The directory holding the path, for the `ls` a message sends the reader to.
    private var parent: String {
        url.deletingLastPathComponent().path
    }
}
