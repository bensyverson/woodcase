//
//  ScriptCompletion.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation
    import JavaScriptCore
    import Woodcase

    /// The completion value of the last source, on its way into ``ScriptRun/result``.
    ///
    /// A script hands its caller a structured answer by *ending in an expression* — no
    /// wrapping function and no top-level `return`, so a one-liner from standard input
    /// works unchanged. `JSON.stringify` in the script's own context is the crossing, and
    /// the decision about whether a value can make it is taken there too, because that is
    /// where the value lives.
    enum ScriptCompletion {
        /// The result a run reports for a completion value.
        ///
        /// - Parameters:
        ///   - value: The last source's completion value.
        ///   - internals: The prelude's helper object.
        ///   - report: Called with the sentence when the value cannot cross.
        /// - Returns: The value as JSON, or `nil` — for a script that ended in a statement
        ///   (ordinary, no warning) or in something JSON cannot carry (warned about).
        static func value(
            of value: JSValue,
            internals: JSValue,
            report: (String) -> Void
        ) -> AnyCodable? {
            guard let described = internals.invokeMethod("result", withArguments: [value]),
                  let json = described.toString(),
                  let outcome = try? JSONDecoder().decode(Outcome.self, from: Data(json.utf8))
            else {
                report(
                    "the script's last expression could not be read back at all; this is a "
                        + "bug in woodcase — please report it with the script."
                )
                return nil
            }

            switch outcome.kind {
            case .empty:
                return nil
            case .unstringifiable:
                report(outcome.message ?? "the script's last expression could not cross into the result.")
                return nil
            case .value:
                guard let text = outcome.json,
                      let decoded = try? JSONDecoder().decode(AnyCodable.self, from: Data(text.utf8))
                else {
                    report(
                        "the script's last expression encoded as JSON that could not be read "
                            + "back; this is a bug in woodcase — please report it with the script."
                    )
                    return nil
                }
                return decoded
            }
        }

        /// What the prelude's `result` helper answers with.
        private struct Outcome: Decodable {
            /// Which of the three answers this is.
            enum Kind: String, Decodable {
                /// The script ended in a statement, so there is no value. Not a problem.
                case empty
                /// The value crossed; ``Outcome/json`` carries it.
                case value
                /// The value could not cross; ``Outcome/message`` says why.
                case unstringifiable
            }

            let kind: Kind
            let json: String?
            let message: String?
        }
    }

#endif
