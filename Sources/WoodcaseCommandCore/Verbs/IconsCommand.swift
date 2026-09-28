import ArgumentParser
import Foundation
import Woodcase

/// `woodcase icons <library> [query]` — read: the icon names a bundled or registered
/// icon library defines, or the ones ranked nearest a query.
struct Icons: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Read: the icon names an icon library defines.",
        discussion: """
        Offline — no .pen file is read, only the codepoint tables Woodcase carries for \
        `library`. With no query every name is printed, sorted, one per line for \
        `grep`. With a query, names are ranked best first: an exact match, then a \
        substring match, then a fuzzy match on shared name tokens or a close edit \
        distance — the same ranking the `unknown-icon` lint check proposes fixes from.

        An unknown library is refused (exit 2) naming the ones this build knows. A \
        query that matches nothing prints nothing and exits 1, the clean negative.

          woodcase icons lucide
          woodcase icons lucide check
          woodcase icons lucide check-circle-2 --json
        """
    )

    @Argument(help: "The icon library to search.")
    var library: String

    @Argument(help: "Only names ranked against this query. Omit to list every name.")
    var query: String?

    @OptionGroup var output: OutputOptions

    /// Looks up `library`'s names and prints them, filtered and ranked by `query`
    /// when one is given.
    ///
    /// - Throws: ``CommandFailure`` (exit 2) naming the known libraries when
    ///   `library` is none of them; `ExitCode.cleanNegative` when a query matches
    ///   nothing.
    func run() throws {
        let registry = PenIconFontRegistry.shared
        guard let names = registry.names(in: library) else {
            throw CommandFailure(message: Self.unknownLibraryMessage(library, registry: registry), exitCode: .usage)
        }

        let matched = query.map { IconNameMatcher.matches(names, query: $0) } ?? names.sorted()

        if output.json {
            try print(Self.json(matched))
        } else if !matched.isEmpty {
            print(matched.joined(separator: "\n"))
        }

        if query != nil, matched.isEmpty {
            throw ExitCode.cleanNegative
        }
    }

    /// The refusal for a library this build knows nothing about, naming the ones it does.
    private static func unknownLibraryMessage(_ library: String, registry: PenIconFontRegistry) -> String {
        "`\(library)` is not a bundled or registered icon library — the libraries are: "
            + "\(registry.libraries.joined(separator: ", "))."
    }

    /// Names as a JSON array of strings.
    private static func json(_ names: [String]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try String(decoding: encoder.encode(names), as: UTF8.self)
    }
}
