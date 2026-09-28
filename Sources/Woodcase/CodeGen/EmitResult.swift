//
//  EmitResult.swift
//  Woodcase
//

/// The result of an emitter's run: the generated files, alongside metadata about
/// dependencies discovered during emission.
public struct EmitResult: Friendly {
    /// The generated source files.
    public var files: [GeneratedFile]

    /// Icon library family names used (e.g. `"lucide"`, `"phosphor"`).
    public var iconLibraries: Set<String>

    /// Relative image asset URLs referenced in the source nodes
    /// (e.g. `"./images/photo.png"`).
    public var imageAssetURLs: Set<String>

    /// The text font faces the output sets — each family at each weight and style it is
    /// drawn in, every value a family variable takes included: what a package that
    /// bundles its fonts must carry. Empty for an emitter that leaves fonts to its host.
    public var fontFaces: Set<PenFontFace>

    /// The families of ``fontFaces`` (e.g. `"Inter"`).
    public var fontFamilies: Set<String> {
        Set(fontFaces.map(\.family))
    }

    /// A result of `files`, and the icon libraries, images and font faces they need.
    public init(
        files: [GeneratedFile] = [],
        iconLibraries: Set<String> = [],
        imageAssetURLs: Set<String> = [],
        fontFaces: Set<PenFontFace> = []
    ) {
        self.files = files
        self.iconLibraries = iconLibraries
        self.imageAssetURLs = imageAssetURLs
        self.fontFaces = fontFaces
    }
}
