import Foundation

/// Keeps at most one bitmap stripe and one packet in memory, with document-wide numbering.
public final class BitmapPacketStream {
    public let packetCount: Int
    public let byteCount: Int
    private let files: [URL]
    private let sizes: [Int]
    private var index = 0
    private var bitmap = Data()
    private var offset = 0
    private var sequence = 0
    public init(files: [URL]) throws {
        self.files = files
        sizes = try files.map { try $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 }
        packetCount = sizes.reduce(0) { $0 + ($1 + 1899) / 1900 }
        byteCount = sizes.reduce(0, +) + packetCount * 18
        guard packetCount > 0, packetCount <= 32767 else { throw ServiceError("invalid_bitmap", "位图为空或打印数据过大") }
    }

    /// SDK recovery drops exactly the acknowledged prefix, preserving document-wide numbering.
    public func seek(after acknowledgedSequence: Int) throws {
        guard (0...packetCount).contains(acknowledgedSequence) else {
            throw ServiceError("invalid_acknowledgement", "设备返回了无效的补传位置", status: 409)
        }
        var remaining = acknowledgedSequence
        bitmap = Data()
        offset = 0
        sequence = acknowledgedSequence
        index = files.count
        for (fileIndex, size) in sizes.enumerated() {
            let count = (size + 1899) / 1900
            if remaining >= count {
                remaining -= count
                continue
            }
            bitmap = try Data(contentsOf: files[fileIndex], options: .mappedIfSafe)
            index = fileIndex + 1
            offset = remaining * 1900
            return
        }
    }
    public func next() throws -> Data? {
        while offset >= bitmap.count {
            guard index < files.count else { return nil }
            bitmap = try Data(contentsOf: files[index], options: .mappedIfSafe)
            index += 1
            offset = 0
        }
        let end = min(offset + 1900, bitmap.count)
        let chunk = Array(bitmap[offset..<end])
        offset = end
        sequence += 1
        func little(_ number: Int) -> [UInt8] {
            [UInt8(truncatingIfNeeded: number), UInt8(truncatingIfNeeded: number >> 8)]
        }
        return PrinterProtocol.frame(
            command: 4,
            body: [11, 2, 0] + little(packetCount) + [12, 2, 0] + little(sequence) + [8] + little(chunk.count) + chunk)
    }
}
