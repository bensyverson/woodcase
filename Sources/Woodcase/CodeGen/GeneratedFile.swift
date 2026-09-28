//
//  GeneratedFile.swift
//  Woodcase
//

/// A file produced by a code generation emitter.
public struct GeneratedFile: Friendly {
    /// Controls whether a file is overwritten on subsequent generations.
    public enum WritePolicy: Friendly {
        /// Always overwrite the file (default for generated source).
        case always
        /// Only write if the file does not already exist (for scaffold files
        /// like `package.json` that the user may have customized).
        case scaffoldOnce
    }

    public init(path: String, content: String, writePolicy: WritePolicy = .always) {
        self.path = path
        self.content = content
        self.writePolicy = writePolicy
    }

    /// Relative path for the generated file (e.g., "components/StatCard.tsx").
    public var path: String

    /// The file content.
    public var content: String

    /// How the file should be written to disk on subsequent generations.
    public var writePolicy: WritePolicy
}
