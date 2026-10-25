import Foundation

enum PrinterProtocol {
    static func imagePackets(_ bitmaps: [Data]) -> [Data] {
        let chunks = bitmaps.flatMap { bitmap in
            stride(from: 0, to: bitmap.count, by: 1900).map { offset in
                Array(bitmap[offset..<min(offset + 1900, bitmap.count)])
            }
        }
        guard !chunks.isEmpty, chunks.count <= 32767 else { return [] }
        return chunks.enumerated().map { index, chunk in
            frame(
                command: 4,
                body: parameter(11, littleEndian(chunks.count))
                    + parameter(12, littleEndian(index + 1)) + parameter(8, chunk))
        }
    }
    static func imagePackets(_ bitmap: Data) -> [Data] {
        let bytes = Array(bitmap)
        guard !bytes.isEmpty, bytes.count <= 1900 * 32767 else { return [] }
        let count = (bytes.count + 1899) / 1900
        return stride(from: 0, to: bytes.count, by: 1900).enumerated().map { index, offset in
            var body = parameter(11, littleEndian(count))
            body += parameter(12, littleEndian(index + 1))
            body += parameter(8, Array(bytes[offset..<min(offset + 1900, bytes.count)]))
            return frame(command: 4, body: body)
        }
    }
    /// Matches SDK 2.5.5 BLEPacketHelper: UTF-16LE, 1900-byte payloads, command 4.
    static func textPackets(_ text: String) -> [Data] {
        let bytes = Array(text.utf16).flatMap { littleEndian(Int($0)) }
        guard !bytes.isEmpty, bytes.count <= 1900 * 32767 else { return [] }
        let count = (bytes.count + 1899) / 1900
        return stride(from: 0, to: bytes.count, by: 1900).enumerated().map { index, offset in
            var body = parameter(11, littleEndian(count))
            body += parameter(12, littleEndian(index + 1))
            body += parameter(13, [1])  // SDK text encoding flag.
            body += parameter(16, [0])  // Underline.
            body += parameter(17, [0])  // Bold.
            body += parameter(18, [0])  // Left alignment.
            body += parameter(7, Array(bytes[offset..<min(offset + 1900, bytes.count)]))
            return frame(command: 4, body: body)
        }
    }

    static func frame(command: UInt8, body: [UInt8] = []) -> Data {
        var bytes: [UInt8] = [0xAA] + littleEndian(body.count + 1) + [command] + body
        bytes.append(0 &- bytes.reduce(0, &+))
        return Data(bytes)
    }

    private static func parameter(_ type: UInt8, _ bytes: [UInt8]) -> [UInt8] {
        [type] + littleEndian(bytes.count) + bytes
    }

    private static func littleEndian(_ value: Int) -> [UInt8] {
        [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]
    }
}
