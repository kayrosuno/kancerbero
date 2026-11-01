import Foundation

/// Aggregated socket counts per process, produced by libproc in the collection
/// actor. It deliberately carries counts only: no addresses, ports or paths.
public enum SocketSummaryCollector {
    public static func summaries(for processes: [KBProcessInfo]) -> KBSocketInventory {
        guard !processes.isEmpty else {
            return KBSocketInventory()
        }

        let started = DispatchTime.now().uptimeNanoseconds
        let pids = processes.map(\.pid)
        var pointer: UnsafeMutablePointer<kb_socket_summary>?
        var count = 0
        let result = pids.withUnsafeBufferPointer { buffer in
            kb_socket_summary_all(buffer.baseAddress, buffer.count, &pointer, &count)
        }
        let duration = Double(DispatchTime.now().uptimeNanoseconds - started)
            / 1_000_000

        guard result == 0, let base = pointer else {
            return KBSocketInventory(
                durationMilliseconds: duration,
                scannedProcesses: processes.count,
                error: "socket summary scan failed"
            )
        }
        defer { kb_socket_summary_free(base) }

        var byPID: [Int32: KBProcessInfo] = [:]
        byPID.reserveCapacity(processes.count)
        for process in processes {
            byPID[process.pid] = process
        }

        var summaries: [KBProcessSocketSummary] = []
        summaries.reserveCapacity(Int(count))
        var restrictedProcesses = 0
        var truncated = false

        for index in 0..<Int(count) {
            let raw = base[index]
            guard let process = byPID[raw.pid] else { continue }
            if raw.restricted != 0 { restrictedProcesses += 1 }
            if raw.truncated != 0 { truncated = true }
            let sigs = signatures(from: raw)
            summaries.append(KBProcessSocketSummary(
                key: process.id,
                buckets: KBSocketBucketCounts(
                    tcp4: Int(raw.tcp4),
                    tcp6: Int(raw.tcp6),
                    udp4: Int(raw.udp4),
                    udp6: Int(raw.udp6),
                    unix: Int(raw.unix_count),
                    raw4: Int(raw.raw4),
                    raw6: Int(raw.raw6),
                    other: Int(raw.other)
                ),
                types: KBSocketTypeCounts(
                    stream: Int(raw.stream),
                    dgram: Int(raw.dgram),
                    raw: Int(raw.raw_type),
                    seqpacket: Int(raw.seqpacket),
                    otherType: Int(raw.other_type)
                ),
                socketFDs: Int(raw.fds),
                uniqueSockets: Int(raw.total),
                restricted: raw.restricted != 0,
                truncated: raw.truncated != 0,
                otherFamilies: otherFamilies(from: raw.other_families),
                otherProtocols: otherProtocols(from: raw.inet_protocols),
                signatures: sigs,
                signaturesTruncated: sigs == nil ? nil : (raw.signatures_truncated != 0)
            ))
        }

        return KBSocketInventory(
            summaries: summaries,
            durationMilliseconds: duration,
            scannedProcesses: processes.count,
            restrictedProcesses: restrictedProcesses,
            truncated: truncated
        )
    }

    /// Reads the fixed C array of distinct (family, type, protocol) triples.
    /// nil means there is no usable scan (older daemon or fully restricted);
    /// an empty array means the process was scanned and had no sockets.
    private static func signatures(from raw: kb_socket_summary) -> [KBSocketSignature]? {
        guard raw.restricted == 0 || raw.total > 0 else { return nil }
        let count = Int(raw.signature_count)
        guard count > 0 else { return [] }
        return withUnsafeBytes(of: raw.signatures) { bytes in
            let entries = bytes.bindMemory(to: kb_socket_signature.self)
            return entries.prefix(min(count, entries.count)).map { entry in
                KBSocketSignature(family: entry.family,
                                  type: entry.type,
                                  protocolNumber: entry.protocol_number)
            }.sorted { lhs, rhs in
                if lhs.family != rhs.family { return lhs.family < rhs.family }
                if lhs.type != rhs.type { return lhs.type < rhs.type }
                return lhs.protocolNumber < rhs.protocolNumber
            }
        }
    }

    /// Expands the AF-number bitmask into the families that fell into `other`.
    private static func otherFamilies(from mask: UInt64) -> [UInt32]? {
        guard mask != 0 else { return nil }
        return (0..<64).compactMap { bit in
            mask & (UInt64(1) << UInt64(bit)) != 0 ? UInt32(bit) : nil
        }
    }

    /// Expands the 256-bit IPPROTO mask (`uint64_t[4]`, imported as a tuple)
    /// into the protocols counted in the RAW buckets.
    private static func otherProtocols<T>(from words: T) -> [UInt8]? {
        var result: [UInt8] = []
        withUnsafeBytes(of: words) { buffer in
            let bits = buffer.bindMemory(to: UInt64.self)
            for wordIndex in 0..<bits.count {
                let word = bits[wordIndex]
                guard word != 0 else { continue }
                for bit in 0..<64 where word & (UInt64(1) << UInt64(bit)) != 0 {
                    result.append(UInt8(wordIndex * 64 + bit))
                }
            }
        }
        return result.isEmpty ? nil : result
    }
}
