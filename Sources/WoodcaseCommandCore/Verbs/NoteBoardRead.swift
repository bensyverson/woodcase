//
//  NoteBoardRead.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// What `notes`, `comments` and `prompts` share: read the board under a shared lock,
/// check the identity filters, print the listing, and exit 1 when it is empty.
///
/// The verbs differ only in which rows they keep and how those print, so each passes
/// a closure that filters the board and renders it; this owns the read, the refusals
/// and the exit code, so the three cannot drift.
enum NoteBoardRead {
    /// The rows a listing kept, ready to print.
    struct Listing {
        /// How many rows the listing kept; zero is a clean negative.
        var count: Int
        /// The bytes to print.
        var text: String
    }

    /// Reads a file's board, lists it, and prints the listing.
    ///
    /// An empty listing prints nothing and exits ``ArgumentParser/ExitCode/cleanNegative``,
    /// as `find` does, so `woodcase comments design.pen --mentions claude && …` branches
    /// on whether there is anything to do.
    ///
    /// - Parameters:
    ///   - command: The verb, which reports failures the house way.
    ///   - file: The file.
    ///   - identities: The identity filters given — flag to value — checked against the
    ///     identities the file names before anything is listed.
    ///   - list: Lists the board: given the board, the identity filters' names (an `@`
    ///     dropped) and the document's revision, the rows to print.
    /// - Throws: A usage failure for a misspelled identity; ``ArgumentParser/ExitCode/cleanNegative``
    ///   when the listing is empty; whatever the read throws.
    static func run(
        _ command: some ParsableCommand,
        file: URL,
        identities: [(option: String, value: String?)],
        list: @escaping @Sendable (PenNoteBoard, [String: String], String) throws -> Listing
    ) async throws {
        try await command.runReportingFailures(editing: file) {
            let diagnostics = PenDiagnosticCollector()
            defer { StandardError.write(diagnostics) }
            let listing = try await CommandTransaction.read(at: file, diagnostics: diagnostics, fonts: .shared) { document in
                let board: PenNoteBoard
                do {
                    board = try PenNoteBoard(document: document)
                } catch {
                    throw CommandFailure.describing(error, in: document, editing: file)
                }
                var names: [String: String] = [:]
                for (option, value) in identities {
                    guard let value else { continue }
                    names[option] = try checked(value, for: option, in: board)
                }
                return try list(board, names, document.documentRevision)
            }.value
            guard listing.count > 0 else { throw ExitCode.cleanNegative }
            print(listing.text)
        }
    }

    /// An identity filter's value as the file names it, refusing a misspelling.
    ///
    /// A name the file does not hold, and nothing close to, is not refused — it lists
    /// nothing — but standard error says who the file does name, so an empty answer
    /// is never mistaken for a typo that went unnoticed.
    private static func checked(_ value: String, for option: String, in board: PenNoteBoard) throws -> String {
        do {
            switch try board.identity(value, for: option) {
            case let .known(name):
                return name
            case let .unknown(name, known):
                let names = known.isEmpty ? "no one yet" : known.joined(separator: ", ")
                StandardError.write("\(option) \(name): no one by that name appears in this file; it names \(names).")
                return name
            }
        } catch let error as PenNoteBoard.FilterError {
            throw CommandFailure(message: error.message, exitCode: .usage)
        }
    }
}
