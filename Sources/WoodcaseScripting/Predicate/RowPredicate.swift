//
//  RowPredicate.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation
    import JavaScriptCore
    import Woodcase

    /// Filters settled tree rows with a JavaScript predicate.
    ///
    /// The read side of the host at its smallest: one arrow function, taking one
    /// ``Woodcase/TreeRow`` and answering truthy or not. It is what `woodcase find` runs,
    /// and it is deliberately *less* than a script — there is no `doc`, no `console` and
    /// nothing to write, so a query cannot change a file by accident.
    ///
    /// ```swift
    /// let rows = try TreeView.rows(of: document)
    /// let outcome = RowPredicate.match(rows, where: .text("r => r.type === 'text'", name: "<argv>"))
    /// print(TreeFormatter.text(outcome.rows))
    /// ```
    ///
    /// The predicate is compiled once, in a fresh `JSContext`, and then called per row;
    /// the rows cross as one JSON array — ``ScriptJSON``'s road, so the values a
    /// predicate compares are the same values `tree --json` prints and the two cannot
    /// drift.
    ///
    /// ## Nothing fails silently
    ///
    /// Each row arrives as a `Proxy` that refuses a member the row type does not have.
    /// That is the point of the type: `r.fontSize` written for `r.props['kind.fontSize']`
    /// is `undefined` on a plain object, `undefined < 12` is `false`, and the run would
    /// print nothing and exit "no matches" for a question nobody asked. It is the same
    /// row ``ScriptHost``'s `doc.tree` hands a script — see ``RowViewPrelude`` for the
    /// traps and the sentences they carry, and ``RowPredicatePrelude`` for what this
    /// route adds.
    public enum RowPredicate {
        /// What a predicate answered: the rows it kept, or why it could not be run.
        ///
        /// A failure keeps no rows at all, even when some had already matched: a
        /// half-answered query is not an answer, and the caller's exit code says so.
        public struct Outcome: Friendly {
            /// Records an outcome.
            ///
            /// - Parameters:
            ///   - rows: The rows the predicate answered truthy for, in the order given.
            ///   - error: Why the run ended early, or `nil` when it did not.
            ///   - failingRow: The row the predicate threw on, when it threw on one. `nil`
            ///     for a failure that happened before any row was seen — a source that
            ///     did not parse, or a predicate that is not a function.
            public init(rows: [TreeRow], error: ScriptError? = nil, failingRow: TreeRow? = nil) {
                self.rows = rows
                self.error = error
                self.failingRow = failingRow
            }

            /// The rows the predicate kept.
            public let rows: [TreeRow]

            /// Why the run ended early, with the sentence and — for a throw out of the
            /// predicate's own code — the line it happened on.
            public let error: ScriptError?

            /// The row the predicate threw on.
            public let failingRow: TreeRow?
        }

        /// Runs a predicate over rows.
        ///
        /// Never throws: everything that can go wrong is part of the answer, as it is for
        /// ``ScriptHost/run(_:over:remedy:diagnostics:recorder:deadline:sink:)``.
        ///
        /// - Parameters:
        ///   - rows: The rows to filter, as ``Woodcase/TreeView`` produced them.
        ///   - source: The predicate — one JavaScript expression evaluating to a function
        ///     of one row, named for the report a failure lands in.
        ///   - properties: The property paths the rows were read with, which is what
        ///     `r.props` is allowed to name. Anything else is refused rather than read as
        ///     `undefined`.
        /// - Returns: The rows that answered truthy, or the failure that stopped the run.
        public static func match(
            _ rows: [TreeRow],
            where source: ScriptSource,
            properties: [String] = []
        ) -> Outcome {
            let text: String
            switch source {
            case let .file(url):
                guard let read = try? String(contentsOf: url, encoding: .utf8) else {
                    return Outcome(rows: [], error: ScriptError(
                        message: "\(url.path) could not be read as UTF-8 text — check the path "
                            + "and the file's encoding, then run it again.",
                        code: ScriptErrorCode.sourceUnreadable,
                        source: url.path
                    ))
                }
                text = read
            case let .text(body, _):
                text = body
            }
            guard let context = JSContext(), let helpers = install(properties, into: context) else {
                return Outcome(rows: [], error: ScriptError(
                    message: "a JavaScript context could not be created; this is a bug in woodcase.",
                    code: ScriptErrorCode.scriptError
                ))
            }
            return run(text, from: source, over: rows, with: helpers, in: context)
        }

        // MARK: - The context

        /// Evaluates the prelude and binds it to this run's property columns.
        ///
        /// - Parameters:
        ///   - properties: The property paths `r.props` may name.
        ///   - context: The context to build in.
        /// - Returns: The prelude's helpers, or `nil` if the prelude itself failed — which
        ///   is a bug in woodcase, not in anyone's predicate.
        private static func install(_ properties: [String], into context: JSContext) -> JSValue? {
            context.exception = nil
            let prelude = context.evaluateScript(
                RowPredicatePrelude.javaScript,
                withSourceURL: URL(fileURLWithPath: "<woodcase find prelude>")
            )
            guard context.exception == nil, let prelude else {
                context.exception = nil
                return nil
            }
            let helpers = prelude.call(withArguments: [properties])
            guard context.exception == nil, let helpers, !helpers.isUndefined else {
                context.exception = nil
                return nil
            }
            return helpers
        }

        // MARK: - The run

        /// Compiles the predicate and calls it over every row.
        private static func run(
            _ text: String,
            from source: ScriptSource,
            over rows: [TreeRow],
            with helpers: JSValue,
            in context: JSContext
        ) -> Outcome {
            var evaluated = ScriptFailure.Evaluated()
            let url = URL(fileURLWithPath: source.name)
            evaluated.add(text, name: source.name, url: url)

            // Evaluated as written, so a line number and a quoted line are the caller's
            // own. An arrow function is an expression statement and needs nothing; only
            // `function (r) { … }` — a nameless function *declaration* — does not parse,
            // and it is retried in parentheses rather than refused for a spelling.
            context.exception = nil
            var compiled = context.evaluateScript(text, withSourceURL: url)
            if let thrown = context.exception {
                context.exception = nil
                compiled = context.evaluateScript("(\(text)\n)", withSourceURL: url)
                if context.exception != nil {
                    context.exception = nil
                    if let identifier = bareIdentifier(referencedBy: thrown) {
                        return Outcome(rows: [], error: notAFunctionExpression(reading: identifier, source: source))
                    }
                    return Outcome(
                        rows: [],
                        error: ScriptFailure.describe(thrown, in: source, sources: evaluated)
                    )
                }
            }
            guard let compiled,
                  helpers.invokeMethod("isFunction", withArguments: [compiled])?.toBool() == true
            else {
                return Outcome(rows: [], error: notAFunction(compiled, helpers: helpers, source: source))
            }

            guard let rowsJSON = try? ScriptJSON.encode(rows),
                  let answer = helpers.invokeMethod("match", withArguments: [compiled, rowsJSON]),
                  context.exception == nil
            else {
                context.exception = nil
                return Outcome(rows: [], error: ScriptError(
                    message: "the rows could not be handed to the predicate; this is a bug in woodcase.",
                    code: ScriptErrorCode.scriptError,
                    source: source.name
                ))
            }
            return read(answer, over: rows, from: source, sources: evaluated)
        }

        /// Turns what `match` answered into an outcome.
        private static func read(
            _ answer: JSValue,
            over rows: [TreeRow],
            from source: ScriptSource,
            sources: ScriptFailure.Evaluated
        ) -> Outcome {
            let thrown = answer.objectForKeyedSubscript("error")
            if let thrown, !thrown.isNull, !thrown.isUndefined {
                let index = Int(answer.objectForKeyedSubscript("index")?.toInt32() ?? -1)
                let row = rows.indices.contains(index) ? rows[index] : nil
                return Outcome(rows: [], error: describe(thrown, from: source, sources: sources), failingRow: row)
            }
            let indices = (answer.objectForKeyedSubscript("matched")?.toArray() as? [NSNumber] ?? [])
                .map(\.intValue)
            return Outcome(rows: indices.compactMap { rows.indices.contains($0) ? rows[$0] : nil })
        }

        /// The failure a throw out of the predicate describes.
        ///
        /// A refusal this host built carries no useful location — a JavaScriptCore `Error`
        /// records the line it was *constructed* on, which for one of ours is a line of the
        /// prelude — so its sentence stands alone. Everything else is the predicate's own
        /// throw, and keeps the line and the quoted source ``ScriptFailure`` recovers.
        private static func describe(
            _ thrown: JSValue,
            from source: ScriptSource,
            sources: ScriptFailure.Evaluated
        ) -> ScriptError {
            guard thrown.objectForKeyedSubscript("woodcaseFind")?.toBool() == true else {
                return ScriptFailure.describe(thrown, in: source, sources: sources)
            }
            return ScriptError(
                message: thrown.objectForKeyedSubscript("message")?.toString() ?? "the predicate refused.",
                code: thrown.objectForKeyedSubscript("code")?.toString() ?? ScriptErrorCode.scriptError,
                source: source.name
            )
        }

        /// The bare identifier a `ReferenceError` names, when evaluating the predicate
        /// text on its own threw one.
        ///
        /// Evaluating a function literal — an arrow function or `function (r) { … }` —
        /// never touches the free variables in its body; the body only runs when the
        /// function is *called*. So a `ReferenceError` thrown by evaluating the whole
        /// predicate text, on both the plain and the parenthesised attempt, can only
        /// mean the text is not a function literal at all: it is a bare expression
        /// whose row variable was never bound by an arrow function it was never
        /// wrapped in. That is true of any predicate that reaches here, not only ones
        /// naming `r` — a caller may spell the row parameter however it likes.
        ///
        /// - Parameter thrown: The exception the first evaluation attempt raised.
        /// - Returns: The identifier JavaScriptCore could not find, or `nil` when the
        ///   thrown value is not that specific shape of `ReferenceError`.
        private static func bareIdentifier(referencedBy thrown: JSValue) -> String? {
            guard thrown.objectForKeyedSubscript("name")?.toString() == "ReferenceError",
                  let message = thrown.objectForKeyedSubscript("message")?.toString(),
                  let match = try? /Can't find variable: ([A-Za-z_$][A-Za-z0-9_$]*)/.wholeMatch(in: message)
            else { return nil }
            return String(match.1)
        }

        /// The sentence for a predicate that is a bare expression, not a function.
        ///
        /// - Parameters:
        ///   - identifier: The row parameter the text reads outside any function.
        ///   - source: The predicate's source, for the report it lands in.
        /// - Returns: A ``ScriptError`` naming the arrow-function shape a predicate
        ///   needs, in the CLI's own words for it.
        private static func notAFunctionExpression(reading identifier: String, source: ScriptSource) -> ScriptError {
            ScriptError(
                message: "a predicate is a JavaScript arrow function of one row — "
                    + "`\(identifier) => …` — not a bare expression; \(identifier) only exists "
                    + "inside that arrow function's parameter list",
                code: ScriptErrorCode.badArgument,
                source: source.name
            )
        }

        /// The sentence for a predicate that evaluated to something other than a function.
        private static func notAFunction(
            _ value: JSValue?,
            helpers: JSValue,
            source: ScriptSource
        ) -> ScriptError {
            let kind = value.flatMap { helpers.invokeMethod("kindOf", withArguments: [$0])?.toString() }
                ?? "nothing"
            return ScriptError(
                message: "a predicate is a JavaScript arrow function taking one row, like "
                    + "`r => r.type === 'text' && r.rect.height < 2`; this one is a \(kind). "
                    + "`woodcase tree <file> --json` prints one row whole, so you can see what "
                    + "the function is given.",
                code: ScriptErrorCode.badArgument,
                source: source.name
            )
        }
    }

#endif
