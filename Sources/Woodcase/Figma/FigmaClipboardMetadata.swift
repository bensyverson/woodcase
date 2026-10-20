//
//  FigmaClipboardMetadata.swift
//  Woodcase
//

/// The `(figmeta)` JSON a Figma clipboard payload carries beside its binary.
///
/// Every field is optional: the format is undocumented, and a missing field is no reason
/// to refuse a payload whose binary decodes. A field of the wrong JSON type is.
public struct FigmaClipboardMetadata: Friendly {
    /// The key of the Figma file the selection was copied from.
    public var fileKey: String?
    /// A number Figma assigns to each copy.
    public var pasteID: Int?
    /// What the payload holds; `scene` for a copied selection.
    public var dataType: String?
    /// The editor copied from: `design`, `figjam` or `slides`.
    public var editorType: String?
    /// The host Figma ran on. The desktop app wraps the web app, so it reads
    /// `www.figma.com` from either.
    public var environment: String?
    /// The selected nodes, as Figma encodes them (`1:309|4|0|0`, comma-separated).
    public var selectedNodeData: String?
    /// Each image fill's hash, mapped to a signed URL its bytes can be fetched from; the
    /// clipboard carries no image bytes.
    public var imageHashes: [String: String]?

    /// Creates metadata from its fields.
    public init(
        fileKey: String? = nil,
        pasteID: Int? = nil,
        dataType: String? = nil,
        editorType: String? = nil,
        environment: String? = nil,
        selectedNodeData: String? = nil,
        imageHashes: [String: String]? = nil
    ) {
        self.fileKey = fileKey
        self.pasteID = pasteID
        self.dataType = dataType
        self.editorType = editorType
        self.environment = environment
        self.selectedNodeData = selectedNodeData
        self.imageHashes = imageHashes
    }
}
