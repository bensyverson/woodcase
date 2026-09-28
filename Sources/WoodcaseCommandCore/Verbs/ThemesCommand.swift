import ArgumentParser
import Foundation
import Woodcase

/// Prints the theme axes a .pen file defines, and the options each one takes.
struct Themes: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Read: the theme axes and options a .pen file defines.",
        discussion: """
        A read verb, and the one that says what --theme will accept elsewhere: every \
        axis with its options, the first of each being the one that is active when \
        nothing pins it. A file that defines no themes says so and exits 0.

          woodcase themes design.pen
        """
    )

    @Argument(help: "The .pen file to read.")
    var input: PenFilePath

    /// Reads the file and prints one line per theme axis.
    ///
    /// - Throws: ``CommandFailure`` when the .pen file cannot be read, `CleanExit` when
    ///   the document defines no themes, and whatever the parser throws.
    func run() async throws {
        let url = try input.existingFile()
        let document = try PenParser.parse(contentsOf: url)

        guard let output = ThemeFormatter.format(document.themes) else {
            throw CleanExit.message("No themes defined in \(url.lastPathComponent).")
        }

        print(output)
    }
}
