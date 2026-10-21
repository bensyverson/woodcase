//
//  FigmaImportOptions.swift
//  Woodcase
//

/// The choices ``FigmaImporter`` leaves to its caller.
///
/// Each default is the reading Penumbra's Paste starts from; the open questions behind them
/// are listed in <doc:FigmaImport>.
public struct FigmaImportOptions: Friendly {
    /// What becomes of an instance whose component the clipboard does not carry.
    public enum MissingComponents: String, Friendly, CaseIterable {
        /// A frame of the instance's size and paints, with no children, and a
        /// ``FigmaImportLoss/Feature/missingComponent`` loss.
        case placeholder
        /// Refuse the selection with ``FigmaImportError/missingComponent(_:)``.
        case refuse
    }

    /// The URL to write for each image, by its hash as lowercase hex. The clipboard carries
    /// hashes only; a caller that fetched the bytes (the figmeta `imageHashes` names a URL
    /// for each) names where it put them. An image paint whose hash is not here is dropped
    /// and reported (``FigmaImportLoss/Feature/imageNotEmbedded``), its hash in the loss.
    public var imageURLs: [String: String]
    /// What becomes of an instance whose component the clipboard does not carry.
    public var missingComponents: MissingComponents

    /// Options with the given choices.
    public init(imageURLs: [String: String] = [:], missingComponents: MissingComponents = .placeholder) {
        self.imageURLs = imageURLs
        self.missingComponents = missingComponents
    }
}
