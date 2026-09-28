//
//  ScriptFailure.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation
    import JavaScriptCore
    import Woodcase

    /// Turns an uncaught JavaScript exception into a ``ScriptError`` a report can print.
    ///
    /// The job is to keep everything a reader needs and lose nothing on the way: the
    /// sentence, the machine-readable `code` when the throw was a `WoodcaseError`, the
    /// candidates it carried, and — the part a stack trace usually swallows — *which
    /// source*, which line, which column, and what that line actually says.
    enum ScriptFailure {
        /// Describes an uncaught exception.
        ///
        /// - Parameters:
        ///   - exception: What JavaScriptCore threw out.
        ///   - source: The source being evaluated when it escaped.
        ///   - sources: Every source evaluated so far — its text keyed by name, and the
        ///     source URL each was given keyed back to that name. A throw from a helper
        ///     file called by a later one quotes the *helper's* line, which is only
        ///     possible because both are kept.
        /// - Returns: The failure, located.
        static func describe(
            _ exception: JSValue,
            in source: ScriptSource,
            sources: Evaluated
        ) -> ScriptError {
            // The line and the source have to come from the *same* place. A refusal the
            // prelude raised — `doc.setProps(…)` — carries the prelude's own line and a
            // sourceURL nothing maps, so taking the line anyway locates a one-line script
            // at line 19: a reader sent to a line that does not exist. Where the URL
            // maps, the location is the script's and every field of it is real.
            let located = string(exception, "sourceURL").flatMap { sources.names[$0] }
            let name = located ?? source.name
            let line = located == nil ? nil : number(exception, "line")
            let column = located == nil ? nil : number(exception, "column")
            let text = sources.texts[name]
            let quoted = line.flatMap { quote(line: $0, of: text) }
            let message = string(exception, "message") ?? exception.toString() ?? "the script threw."
            let syntax = string(exception, "name") == "SyntaxError"

            if syntax, let sentence = modulesSentence(in: sources.texts[source.name] ?? "") {
                return ScriptError(
                    message: sentence,
                    code: ScriptErrorCode.synchronousOnly,
                    source: name, line: line, column: column,
                    sourceLine: quoted
                )
            }

            return ScriptError(
                message: message,
                code: string(exception, "code")
                    ?? (syntax ? ScriptErrorCode.syntaxError : ScriptErrorCode.scriptError),
                source: name,
                line: line,
                column: column,
                sourceLine: quoted,
                candidates: candidates(of: exception)
            )
        }

        // MARK: - Reading the exception

        /// A string property of the exception, or `nil` when it has none.
        private static func string(_ value: JSValue, _ key: String) -> String? {
            guard let found = value.objectForKeyedSubscript(key), found.isString else { return nil }
            return found.toString()
        }

        /// A whole-number property of the exception, or `nil` when it has none.
        private static func number(_ value: JSValue, _ key: String) -> Int? {
            guard let found = value.objectForKeyedSubscript(key), found.isNumber else { return nil }
            return Int(found.toInt32())
        }

        /// The candidate list a `WoodcaseError` carries, as values.
        ///
        /// Read back through JSON rather than `toArray()`, for the same reason everything
        /// else crosses that way: one decoder, and the shape is the library's own.
        private static func candidates(of value: JSValue) -> [NodeAddressCandidate] {
            guard let found = value.objectForKeyedSubscript("candidates"), found.isArray,
                  let context = value.context,
                  let json = context.objectForKeyedSubscript("JSON")?
                  .invokeMethod("stringify", withArguments: [found])?.toString()
            else { return [] }
            return (try? JSONDecoder().decode([NodeAddressCandidate].self, from: Data(json.utf8))) ?? []
        }

        // MARK: - Locating it

        /// What has been evaluated so far, in the two shapes a failure needs.
        ///
        /// `sourceURL` comes back from JavaScriptCore as the *URL* the source was
        /// evaluated with, which is not the name the caller gave: a relative name is
        /// resolved against the working directory, and `<stdin>` comes back with that
        /// directory in front of it. Guessing the name back from the URL is how a report
        /// ends up naming a file nobody wrote, so the mapping is recorded on the way in
        /// rather than reconstructed on the way out.
        struct Evaluated {
            /// Each source's text, keyed by ``ScriptSource/name``.
            var texts: [String: String] = [:]

            /// Each source's name, keyed by the source URL it was evaluated with.
            var names: [String: String] = [:]

            /// Records one source before it is evaluated.
            ///
            /// - Parameters:
            ///   - text: The source's body.
            ///   - name: The name a failure should report it under.
            ///   - url: The URL it is being evaluated with.
            mutating func add(_ text: String, name: String, url: URL) {
                texts[name] = text
                names[url.absoluteString] = name
            }
        }

        /// One line of a source, verbatim.
        private static func quote(line: Int, of text: String?) -> String? {
            guard let text, line > 0 else { return nil }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            guard line <= lines.count else { return nil }
            return String(lines[line - 1])
        }

        /// The sentence for a source that tried to be a module, or `nil` if it did not.
        ///
        /// A `SyntaxError` is the only face `import` and `export` ever show: they are
        /// statements, so no global can be defined to intercept them the way `require` is.
        /// The parse failed, which means the error carries no useful message of its own —
        /// so the source is read back for the line that caused it and the sentence is
        /// written here.
        private static func modulesSentence(in text: String) -> String? {
            let keyword = text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .compactMap { line -> String? in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("import ") || trimmed.hasPrefix("import{")
                        || trimmed.hasPrefix("import*")
                    {
                        return "import"
                    }
                    return trimmed.hasPrefix("export ") || trimmed.hasPrefix("export{")
                        ? "export"
                        : nil
                }
                .first
            guard let keyword else { return nil }
            return """
            \(keyword) is not available: a woodcase script is not a module — there is \
            nothing to load from and nothing to load into, because the whole run is one \
            file transaction. Put shared code in its own file and pass it first, \
            `woodcase js file.pen -F helpers.js -F run.js`; top-level `const` from the \
            first file is visible to the second.
            """
        }
    }

#endif
