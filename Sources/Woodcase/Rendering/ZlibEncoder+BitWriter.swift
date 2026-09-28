//
//  ZlibEncoder+BitWriter.swift
//  Woodcase
//

extension ZlibEncoder {
    /// Packs values into bytes least-significant bit first, the order deflate reads.
    struct BitWriter {
        private var bytes: [UInt8] = []
        private var buffer: UInt64 = 0
        private var bufferedBits = 0

        /// Appends the low `count` bits of `value`, least-significant first.
        mutating func write(_ value: UInt32, count: Int) {
            buffer |= (UInt64(value) & ((UInt64(1) << count) - 1)) << bufferedBits
            bufferedBits += count
            while bufferedBits >= 8 {
                bytes.append(UInt8(truncatingIfNeeded: buffer))
                buffer >>= 8
                bufferedBits -= 8
            }
        }

        /// Appends a Huffman code, which deflate packs most-significant bit first.
        mutating func writeHuffman(_ code: UInt32, length: Int) {
            var reversed: UInt32 = 0
            for bit in 0 ..< length {
                reversed |= ((code >> bit) & 1) << (length - 1 - bit)
            }
            write(reversed, count: length)
        }

        /// The written bytes, with the last partial byte padded with zeros.
        mutating func finish() -> [UInt8] {
            if bufferedBits > 0 {
                write(0, count: 8 - bufferedBits)
            }
            return bytes
        }
    }
}
