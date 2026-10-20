//
//  FigmaClipboard+Blobs.swift
//  Woodcase
//

public extension FigmaClipboard {
    /// The message's blob table: the vector networks and command streams its nodes name.
    func blobTable() throws(FigmaBlobError) -> FigmaBlobTable {
        try FigmaBlobTable(message: message)
    }
}
