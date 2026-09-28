//
//  ScriptJSON.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation

    /// The one road values travel between Swift and the script: JSON text.
    ///
    /// Not `toDictionary()` and not `JSExport`. Two reasons, both load-bearing. The
    /// library's report types are already `Codable`, so encoding them is the answer the
    /// verbs already give and the two forms cannot drift. And it is what makes a script's
    /// values *typed*: an integer written in JavaScript arrives as an integer and is
    /// stored as one, not as `10.0`, and the document revision depends on that.
    enum ScriptJSON {
        /// Encodes a value as the response JSON a native returns.
        ///
        /// - Parameter value: The value to encode.
        /// - Returns: Its JSON text.
        /// - Throws: Whatever `JSONEncoder` throws.
        static func encode(_ value: some Encodable) throws -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return try String(decoding: encoder.encode(value), as: UTF8.self)
        }

        /// Decodes the request JSON the prelude sent.
        ///
        /// A failure here is a bug in the prelude, not in anyone's script — the prelude
        /// has already checked the shape — so it surfaces as a plain
        /// ``ScriptErrorCode/scriptError`` naming the request.
        ///
        /// - Parameters:
        ///   - type: What to decode.
        ///   - json: The request text.
        /// - Returns: The decoded request.
        /// - Throws: ``ScriptThrow`` when the text is not the request it should be.
        static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
            do {
                return try JSONDecoder().decode(type, from: Data(json.utf8))
            } catch {
                throw ScriptThrow(
                    message: "the script host could not read its own call (\(error)); "
                        + "this is a bug in woodcase — please report it with the script.",
                    code: ScriptErrorCode.scriptError
                )
            }
        }
    }

#endif
