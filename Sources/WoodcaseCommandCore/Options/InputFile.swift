//
//  InputFile.swift
//  WoodcaseCommandCore
//

import Foundation

/// The `-F <file>` body a verb reads its structured input from.
///
/// Bodies come from files, never from an inline `-m "…"`: the shell sees a quoted
/// argument first, and a subtree or a property map has quotes in it. `-` reads
/// standard input, so a body can be piped:
///
/// ```bash
/// woodcase add design.pen Canvas -F hero.json
/// jq '.children[0]' other.pen | woodcase add design.pen Canvas -F -
/// ```
///
/// A body that cannot be *read* is ``ExitCode/targetFailure`` (4) — the invocation
/// was fine, the world was not. A body that cannot be *understood* is the caller's
/// verb to report as a usage error, because only it knows what shape it wanted.
enum InputFile {
    /// The path that means standard input.
    static let standardInput = "-"

    /// Reads a body, from a file or from standard input.
    ///
    /// Read through a `FileHandle` rather than `Data(contentsOf:)`, which refuses
    /// anything that is not a regular file: `-F /dev/null` — the way a caller says "no
    /// operations" — and `-F <(jq …)`, a process substitution, are both what they look
    /// like, an empty body and a piped one, not a permissions failure.
    ///
    /// - Parameter path: The path as typed, or `-` for standard input.
    /// - Returns: The bytes read. Standard input is read to end of file.
    /// - Throws: ``CommandFailure`` with ``ExitCode/targetFailure`` when the path names
    ///   nothing, names a directory, or names a file this process cannot read.
    static func data(at path: String) throws -> Data {
        guard path != standardInput else {
            return FileHandle.standardInput.readDataToEndOfFile()
        }
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) else {
            let parent = URL(fileURLWithPath: expanded).deletingLastPathComponent().path
            throw CommandFailure(
                message: "Cannot read \(path): no such file. Check the path — `ls \(parent)` "
                    + "lists what is there, and `-F -` reads standard input.",
                exitCode: .targetFailure
            )
        }
        guard !isDirectory.boolValue else {
            throw CommandFailure(
                message: "Cannot read \(path): it is a directory. Name one file.",
                exitCode: .targetFailure
            )
        }
        do {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: expanded))
            defer { try? handle.close() }
            return try handle.readToEnd() ?? Data()
        } catch {
            throw CommandFailure(
                message: "Cannot read \(path): \(error.localizedDescription)",
                exitCode: .targetFailure
            )
        }
    }
}
