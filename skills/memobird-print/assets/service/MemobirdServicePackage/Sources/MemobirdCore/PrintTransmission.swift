import Foundation

/// Owns a single document's packet stream and device acknowledgement lifecycle.
public final class PrintTransmission {
    private let stream: BitmapPacketStream
    private var responses = Data()
    private var highestSequence = 0
    private var checkpoint: Int?
    private var recoveryCount = 0
    public var packetCount: Int { stream.packetCount }
    public var byteCount: Int { stream.byteCount }
    public private(set) var isComplete = false

    public init(files: [URL]) throws { stream = try BitmapPacketStream(files: files) }

    public func nextPacket() throws -> Data? {
        guard !isComplete, checkpoint == nil else { return nil }
        let packet = try stream.next()
        if let packet { highestSequence = max(highestSequence, Int(packet[12]) + Int(packet[13]) * 256) }
        return packet
    }

    /// FF01 may split or combine frames. Only a checksummed final ACK completes a job.
    public func receive(_ data: Data) throws -> [Int] {
        guard !isComplete else { return [] }
        guard responses.count + data.count <= 8192 else {
            throw ServiceError("invalid_acknowledgement", "设备响应超过限制", status: 409)
        }
        responses.append(data)
        var resumes: [Int] = []
        while responses.count >= 4 {
            let header = Array(responses.prefix(4))
            guard header[0] == 0xAA else {
                responses.removeFirst()
                continue
            }
            let length = Int(header[1]) + Int(header[2]) * 256
            guard (1...1024).contains(length) else {
                responses.removeFirst()
                continue
            }
            guard responses.count >= length + 4 else { break }
            let frame = Array(responses.prefix(length + 4))
            guard frame.reduce(UInt8(0), &+) == 0 else {
                responses.removeFirst()
                continue
            }
            responses.removeFirst(length + 4)
            guard frame[3] == 4, let values = parameters(frame),
                let countBytes = values[11], countBytes.count == 2,
                let sequenceBytes = values[12], sequenceBytes.count == 2,
                let result = values[14], result.count == 1,
                let status = values[6], status.count == 1
            else { continue }
            let count = Int(countBytes[0]) + Int(countBytes[1]) * 256
            let sequence = Int(sequenceBytes[0]) + Int(sequenceBytes[1]) * 256
            // A delayed response for another document must never complete this one.
            guard count == 0 || count == packetCount else { continue }
            guard status[0] == 0 else {
                throw ServiceError("printer_status_error", "打印机报告缺纸或温度异常（状态 \(status[0])），可能部分出纸", status: 409)
            }
            if result[0] == 1 {
                if count == packetCount, sequence == packetCount, highestSequence == packetCount {
                    isComplete = true
                    return resumes
                }
            } else if result[0] == 0 {
                guard sequence < packetCount, sequence <= highestSequence else {
                    throw ServiceError("invalid_acknowledgement", "设备请求了尚未发送的补传位置", status: 409)
                }
                // Several buffered frames may trigger the same recovery request; pause once.
                guard checkpoint == nil else { continue }
                recoveryCount += 1
                guard recoveryCount <= 3 else {
                    throw ServiceError("packet_recovery_exhausted", "设备多次要求补传，停止发送并等待检查纸张", status: 409)
                }
                checkpoint = sequence
                resumes.append(sequence)
            } else {
                throw ServiceError("printer_rejected", "打印机拒收数据（结果 \(result[0])）", status: 409)
            }
        }
        return resumes
    }

    /// Called after the SDK's 1.5-second drain interval; never starts a new print job.
    public func resume() throws {
        guard let checkpoint, !isComplete else { return }
        try stream.seek(after: checkpoint)
        self.checkpoint = nil
    }

    private func parameters(_ frame: [UInt8]) -> [UInt8: [UInt8]]? {
        var result: [UInt8: [UInt8]] = [:]
        var offset = 4
        while offset < frame.count - 1 {
            guard offset + 3 <= frame.count - 1 else { return nil }
            let length = Int(frame[offset + 1]) + Int(frame[offset + 2]) * 256
            guard offset + 3 + length <= frame.count - 1, result[frame[offset]] == nil else { return nil }
            result[frame[offset]] = Array(frame[(offset + 3)..<(offset + 3 + length)])
            offset += 3 + length
        }
        return result
    }
}
