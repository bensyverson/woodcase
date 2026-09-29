//
//  ScriptBridge.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation
    import Woodcase

    /// The read side of `doc`, as pure functions from a request to a response.
    ///
    /// Each one is the same answer the matching verb prints with `--json`, built from the
    /// same library call — `TreeView.rows`, `NodeLookup.find`, `DocumentLinter.findings`,
    /// `SchemaOverviewReport`. Nothing here decides anything a verb does not; a bridge
    /// that held an editing decision of its own would be the bug the principles warn
    /// about.
    ///
    /// The prelude has already checked the *shape* of every argument, so these check only
    /// *vocabulary* — is `clipped` a lint check, is `text` a node type — which is
    /// knowledge the prelude does not have.
    enum ScriptBridge {
        /// `doc.rev` — the document revision, live.
        static func rev(_ runner: ScriptRunner) throws -> String {
            try ScriptJSON.encode(runner.document.documentRevision)
        }

        /// `doc.tree(address, options)` — the rows `woodcase tree --json` prints.
        static func tree(_ request: String, _ runner: ScriptRunner) throws -> String {
            let call = try ScriptJSON.decode(TreeRequest.self, from: request)
            let theme = call.options.theme ?? [:]
            let settled = runner.settled.tree(for: theme, of: runner.document)
            do {
                let rows = try TreeView.rows(
                    of: runner.document,
                    settled: settled,
                    root: call.address,
                    depth: call.options.depth,
                    expandInstances: call.options.expand ?? false,
                    properties: call.options.props ?? []
                )
                return try ScriptJSON.encode(rows)
            } catch {
                throw runner.editingFailure(error)
            }
        }

        /// `doc.get(address, options)` — the report `woodcase get --json` prints.
        static func get(_ request: String, _ runner: ScriptRunner) throws -> String {
            let call = try ScriptJSON.decode(GetRequest.self, from: request)
            do {
                let found = try NodeLookup.find(
                    call.address,
                    in: runner.document,
                    expanding: call.options.expand ?? false
                )
                return try ScriptJSON.encode(found.report)
            } catch {
                throw runner.editingFailure(error)
            }
        }

        /// `doc.lint(address, options)` — the findings `woodcase lint --json` prints.
        ///
        /// The pipeline diagnostics come from the caller: they are produced when the file
        /// is *parsed*, which happened before the host was handed a document. The `js`
        /// verb passes its collector's; a library caller with none reports the checks
        /// alone.
        static func lint(_ request: String, _ runner: ScriptRunner) throws -> String {
            let call = try ScriptJSON.decode(LintRequest.self, from: request)
            let excluded = try Set(call.options.exclude.map(checks(in:)) ?? [])
            let threshold = try severity(call.options.severity)
            let theme = call.options.theme ?? [:]
            let settled = runner.settled.tree(for: theme, of: runner.document)
            do {
                let findings = try DocumentLinter.findings(
                    in: runner.document,
                    settled: settled,
                    theme: theme,
                    root: call.address,
                    diagnostics: runner.diagnostics
                )
                return try ScriptJSON.encode(findings.filter {
                    !excluded.contains($0.check) && $0.severity.meetsOrExceeds(threshold)
                })
            } catch {
                throw runner.editingFailure(error)
            }
        }

        /// `doc.schema(type)` — the table `woodcase schema --json` prints.
        static func schema(_ request: String, _: ScriptRunner) throws -> String {
            let call = try ScriptJSON.decode(SchemaRequest.self, from: request)
            guard let name = call.type else {
                return try ScriptJSON.encode(SchemaOverviewReport())
            }
            do {
                return try ScriptJSON.encode(SchemaTypeReport(type: SchemaLookup.type(named: name)))
            } catch let error as SchemaTypeNotFound {
                throw ScriptThrow(message: error.message, code: ScriptErrorCode.unknownNodeType)
            }
        }

        /// `console.log` and its siblings, already rendered by the prelude.
        static func log(_ request: String, _ runner: ScriptRunner) throws -> String? {
            let line = try ScriptJSON.decode(LogRequest.self, from: request)
            runner.record(.log(level: line.level, text: line.text))
            return nil
        }

        // MARK: - Vocabulary

        /// The lint checks a caller named, refusing an id the catalog does not have.
        private static func checks(in names: [String]) throws -> [LintCheck] {
            try names.map { name in
                guard let check = LintCheck(rawValue: name) else {
                    throw ScriptThrow(
                        message: """
                        \(name) is not a lint check — the checks are \
                        \(LintCheck.allCases.map(\.rawValue).joined(separator: ", ")); \
                        run `woodcase lint --list` for what each one looks for.
                        """,
                        code: ScriptErrorCode.badArgument
                    )
                }
                return check
            }
        }

        /// The severity threshold a caller named, defaulting to the verb's default.
        private static func severity(_ name: String?) throws -> PenDiagnostic.Severity {
            guard let name else { return .warning }
            guard let level = PenDiagnostic.Severity(rawValue: name) else {
                throw ScriptThrow(
                    message: """
                    \(name) is not a severity — they are \
                    \(PenDiagnostic.Severity.allCases.map(\.rawValue).joined(separator: ", ")); \
                    `severity` reports findings at or above the level you name.
                    """,
                    code: ScriptErrorCode.badArgument
                )
            }
            return level
        }

        // MARK: - Requests

        /// What `doc.tree` sends across.
        private struct TreeRequest: Decodable {
            let address: String?
            let options: Options

            struct Options: Decodable {
                let depth: Int?
                let expand: Bool?
                let props: [String]?
                let theme: [String: String]?
            }
        }

        /// What `doc.get` sends across.
        private struct GetRequest: Decodable {
            let address: String
            let options: Options

            struct Options: Decodable {
                let expand: Bool?
            }
        }

        /// What `doc.lint` sends across.
        private struct LintRequest: Decodable {
            let address: String?
            let options: Options

            struct Options: Decodable {
                let exclude: [String]?
                let severity: String?
                let theme: [String: String]?
            }
        }

        /// What `doc.schema` sends across.
        private struct SchemaRequest: Decodable {
            let type: String?
        }

        /// What `console` sends across, already joined and rendered.
        private struct LogRequest: Decodable {
            let level: ScriptLogLevel
            let text: String
        }
    }

#endif
