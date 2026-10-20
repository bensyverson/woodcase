//
//  DeflateDecodeError.swift
//  Woodcase
//

/// Why ``DeflateDecoder`` refused its input.
///
/// Every refusal is one of these: the decoder never hands back partial bytes.
public enum DeflateDecodeError: Error, Friendly {
    /// The stream is empty, ends before its final block does, or is malformed.
    ///
    /// Apple's Compression framework meets a bad block type, a bad Huffman code or a
    /// back-reference before the output's start by stopping without reaching the stream's
    /// end, exactly as it meets a stream cut short, so the two cannot be told apart.
    case malformed
    /// The stream inflates to more than `limit` bytes.
    case exceedsLimit(limit: Int)
}
