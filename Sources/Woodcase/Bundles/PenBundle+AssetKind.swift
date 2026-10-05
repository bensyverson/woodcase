//
//  PenBundle+AssetKind.swift
//  Woodcase
//

import Foundation

public extension PenBundle {
    /// Which kind of file a document points at, and so which bundle folder it is kept in.
    enum AssetKind: String, Friendly, CaseIterable {
        /// An image paint's `url`, kept in `images/`.
        case image
        /// A declared font's `url`, kept in `fonts/`.
        case font

        /// The bundle folder files of this kind are kept in: ``PenLocation/imagesDirectoryName``
        /// or ``PenLocation/fontsDirectoryName``.
        public var directoryName: String {
            switch self {
            case .image: PenLocation.imagesDirectoryName
            case .font: PenLocation.fontsDirectoryName
            }
        }
    }
}
