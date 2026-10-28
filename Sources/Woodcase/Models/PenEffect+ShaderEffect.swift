//
//  PenEffect+ShaderEffect.swift
//  Woodcase
//

import Foundation

public extension PenEffect {
    /// A fragment shader that post-processes the rendered node (format 2.21, Pen 1.2.16).
    ///
    /// Pen renders the node, its children and its earlier effects into a texture, runs the
    /// shader over the node's visual bounds — strokes, shadows, blur and unclipped children
    /// included — and draws its output in place of the node; several shader effects chain in
    /// list order. A `sampler2D` uniform set to `"pencil:object"` is bound to the rendered
    /// node, and `@resolution` is the size of the visual bounds. The shader format is the
    /// shader fill's (``PenFill/PenShaderFill``), and so is the uniforms type.
    ///
    /// Woodcase preserves a shader effect losslessly but never runs it: every target draws
    /// the node unprocessed, as if the effect were absent, and says so — ``ShaderFills``
    /// names each enabled one, as it does a shader fill. It has no `blendMode` or `opacity`,
    /// unlike the fill.
    struct PenShaderEffect: Friendly {
        /// Creates a shader effect.
        ///
        /// - Parameters:
        ///   - enabled: Whether the effect runs; absent means it does.
        ///   - url: The shader file, relative to the .pen file.
        ///   - uniforms: The shader's uniform values, by name.
        ///   - extras: Keys a file wrote on the effect that the model does not claim.
        public init(
            enabled: PenValue<Bool>? = nil,
            url: String,
            uniforms: PenShaderUniforms? = nil,
            extras: PenExtras = PenExtras()
        ) {
            self.enabled = enabled
            self.url = url
            self.uniforms = uniforms
            self.extras = extras
        }

        /// Whether the effect runs. Absent means it does.
        public var enabled: PenValue<Bool>?
        /// The shader file's URL, relative to the .pen file (e.g. `"./post.frag"`).
        public var url: String
        /// Named uniform values passed to the shader, the same type a shader fill's take.
        public var uniforms: PenShaderUniforms?

        /// Keys the file wrote on this effect that the model does not claim. See ``PenExtras``.
        public var extras = PenExtras()

        /// The keys this payload claims; any other key of its object is an extra.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case enabled, url, uniforms
        }
    }
}
