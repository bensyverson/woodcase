//
//  RepositoryIgnoreFile.swift
//  Woodcase
//

import Foundation

/// A repository root's `.gitignore`, as far as this package needs one: does it already
/// ignore a pattern, and if not, append it.
///
/// Generated local state belongs to the machine, not the history, so the first write that
/// creates `.woodcase/` inside a checkout leaves the ignore line behind rather than
/// waiting for somebody to notice an untracked directory in `git status`. Only *missing*
/// patterns are appended, so it is safe to call on every write.
///
/// ```swift
/// try RepositoryIgnoreFile(root: root).addIfMissing(
///     ".woodcase/", comment: "Woodcase activity log"
/// )
/// ```
///
/// It reads and writes the file and nothing else: no `git` process, no index, no config.
/// A repository whose ignore rules live somewhere else — `.git/info/exclude`, a global
/// excludes file — gets a redundant line, which is harmless.
public struct RepositoryIgnoreFile: Friendly {
    /// Addresses the `.gitignore` at a repository root.
    ///
    /// - Parameter root: The repository root, the directory holding `.git`.
    public init(root: URL) {
        self.root = root
    }

    /// The repository root.
    public let root: URL

    /// The ignore file itself, whether or not it exists.
    public var url: URL {
        root.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    /// Whether a pattern is already listed.
    ///
    /// Compared line by line, ignoring surrounding whitespace, a leading `/` and a
    /// trailing `/` — `.woodcase`, `/.woodcase` and `.woodcase/` all ignore the same
    /// directory, and appending a fourth spelling would help nobody.
    ///
    /// - Parameter pattern: The pattern to look for.
    /// - Returns: `true` if a line already carries it.
    public func lists(_ pattern: String) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let wanted = Self.normalized(pattern)
        return text.split(separator: "\n").contains { Self.normalized(String($0)) == wanted }
    }

    /// Appends a pattern unless it is already listed, creating the file if needed.
    ///
    /// - Parameters:
    ///   - pattern: The pattern to add, for example `.woodcase/`.
    ///   - comment: A one-line comment written above it, so a reader of the file knows
    ///     what put it there.
    /// - Returns: `true` if the file was changed.
    /// - Throws: ``PenFileError/writeFailed(url:reason:)`` if the file cannot be written.
    @discardableResult
    public func addIfMissing(_ pattern: String, comment: String) throws -> Bool {
        guard !lists(pattern) else { return false }

        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var text = existing
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        if !text.isEmpty { text += "\n" }
        text += "# \(comment)\n\(pattern)\n"

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw PenFileError.writeFailed(url: url, reason: PenFileError.oneLineReason(error))
        }
        return true
    }

    // MARK: - Private

    /// The file's name at a repository root.
    private static let fileName = ".gitignore"

    /// A pattern reduced to what it matches, so two spellings of one directory compare equal.
    private static func normalized(_ line: String) -> String {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        while trimmed.hasPrefix("/") {
            trimmed.removeFirst()
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }
}
