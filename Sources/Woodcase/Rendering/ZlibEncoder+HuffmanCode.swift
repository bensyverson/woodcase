//
//  ZlibEncoder+HuffmanCode.swift
//  Woodcase
//

extension ZlibEncoder {
    /// Builds the length-limited, canonical Huffman code a dynamic deflate block declares.
    enum HuffmanCode {
        /// The code length of each symbol, `0` for a symbol that never occurs.
        ///
        /// A plain Huffman tree can grow deeper than deflate allows; when it does, the
        /// weights are halved (a used symbol stays at least 1) and the tree rebuilt, which
        /// flattens it until it fits. That costs a little optimality only on inputs whose
        /// frequencies span several orders of magnitude.
        ///
        /// - Parameters:
        ///   - frequencies: How often each symbol occurs.
        ///   - limit: The longest code allowed, in bits.
        /// - Returns: One length per symbol.
        static func lengths(for frequencies: [Int], limit: Int) -> [Int] {
            var weights = frequencies
            // A code needs two symbols; give a lone symbol a partner that never occurs.
            let used = weights.indices.filter { weights[$0] > 0 }
            if used.count == 1 {
                weights[used[0] == 0 ? 1 : 0] = 1
            }
            while true {
                let lengths = unlimitedLengths(for: weights)
                if (lengths.max() ?? 0) <= limit {
                    return lengths
                }
                weights = weights.map { $0 == 0 ? 0 : ($0 + 1) / 2 }
            }
        }

        /// The canonical codes for a set of lengths (RFC 1951 §3.2.2): shorter codes sort
        /// first, and within one length codes follow symbol order.
        ///
        /// - Parameter lengths: One code length per symbol.
        /// - Returns: One code per symbol, meaningful in its low `lengths[symbol]` bits.
        static func canonicalCodes(for lengths: [Int]) -> [UInt32] {
            let longest = lengths.max() ?? 0
            var lengthCounts = [UInt32](repeating: 0, count: longest + 1)
            for length in lengths where length > 0 {
                lengthCounts[length] += 1
            }
            var nextCode = [UInt32](repeating: 0, count: longest + 1)
            var code: UInt32 = 0
            for length in stride(from: 1, through: longest, by: 1) {
                code = (code + lengthCounts[length - 1]) << 1
                nextCode[length] = code
            }
            return lengths.map { length in
                guard length > 0 else { return 0 }
                defer { nextCode[length] += 1 }
                return nextCode[length]
            }
        }

        /// The depth of each used symbol in a Huffman tree over `weights`.
        ///
        /// Ties break on creation order, so the same weights always give the same tree.
        private static func unlimitedLengths(for weights: [Int]) -> [Int] {
            // Leaves are 0..<weights.count; each merge appends a parent.
            var nodeWeights = weights
            var parent = [Int](repeating: -1, count: weights.count)
            var active = weights.indices.filter { weights[$0] > 0 }
            while active.count > 1 {
                active.sort { (nodeWeights[$0], $0) < (nodeWeights[$1], $1) }
                let first = active.removeFirst()
                let second = active.removeFirst()
                let merged = nodeWeights.count
                nodeWeights.append(nodeWeights[first] + nodeWeights[second])
                parent.append(-1)
                parent[first] = merged
                parent[second] = merged
                active.append(merged)
            }
            return weights.indices.map { symbol in
                guard weights[symbol] > 0 else { return 0 }
                var depth = 0
                var node = symbol
                while parent[node] >= 0 {
                    node = parent[node]
                    depth += 1
                }
                return depth
            }
        }
    }
}
