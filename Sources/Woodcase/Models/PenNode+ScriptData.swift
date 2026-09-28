//
//  PenNode+ScriptData.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    // MARK: Script

    /// Type-specific data for a `script` node — a sized placeholder that runs a
    /// user-authored JavaScript file inside Pen.
    ///
    /// Woodcase treats a script like any other sized leaf: it occupies the layout
    /// space its ``width``/``height`` declare, but it is never executed. The
    /// renderer draws nothing for it and the React emitter emits an empty
    /// placeholder element sized to match.
    struct ScriptData: Friendly {
        public init(
            scriptUri: String? = nil,
            inputs: [String: PenScriptInput]? = nil,
            clip: PenValue<Bool>? = nil,
            width: PenSizing? = nil,
            height: PenSizing? = nil
        ) {
            self.scriptUri = scriptUri
            self.inputs = inputs
            self.clip = clip
            self.width = width
            self.height = height
        }

        /// The script file's URL, relative to the .pen file (e.g. `"bars.js"`).
        public var scriptUri: String?
        /// Named input values passed to the script; the script itself declares
        /// each input's type and default.
        public var inputs: [String: PenScriptInput]?
        /// Whether the script's drawing is clipped to its own box.
        public var clip: PenValue<Bool>?
        public var width: PenSizing?
        public var height: PenSizing?
    }
}

/// A single input value passed to a ``PenNode/ScriptData`` script.
///
/// A script input is whichever JSON scalar the .pen file wrote — a number, a
/// plain string, a boolean, or a `$variable` reference — decoded without
/// knowing the script's own declared type (that lives inside the referenced
/// JavaScript file, which Woodcase never reads).
public enum PenScriptInput: Friendly {
    /// A numeric literal.
    case number(Double)
    /// A plain string literal.
    case string(String)
    /// A boolean literal.
    case bool(Bool)
    /// A reference to a named variable (without the `$` prefix).
    case variable(String)
}

// MARK: - Codable

public extension PenScriptInput {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            let string = try container.decode(String.self)
            if string.hasPrefix("$") {
                self = .variable(String(string.dropFirst()))
            } else {
                self = .string(string)
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .variable(name):
            try container.encode("$\(name)")
        }
    }
}
