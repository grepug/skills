import Foundation

/// SDK 2.5.5: command 3 sets one-byte parameter 19; info requests use command 2.
public enum PrinterPowerProtocol {
    public static var query: Data { PrinterProtocol.frame(command: 2) }

    public static func setAutoOff(minutes: Int) throws -> Data {
        guard (0...255).contains(minutes) else {
            throw ServiceError("invalid_setting", "自动关机时间须为 0–255 分钟，0 表示关闭自动关机")
        }
        return PrinterProtocol.frame(command: 3, body: [19, 1, 0, UInt8(minutes)])
    }

    public static func autoOffMinutes(in reply: PrinterReply) throws -> Int {
        guard [2, 10].contains(reply.command), let value = reply.parameters[19], value.count == 1 else {
            throw ServiceError("setting_readback_failed", "设备未返回自动关机时间，不能确认设置", status: 502)
        }
        return Int(value[0])
    }
}

public struct PrinterReply {
    public let command: UInt8
    public let parameters: [UInt8: [UInt8]]
}

/// Reassembles bounded FF01 responses and discards invalid checksums or TLV lengths.
public struct PrinterReplyDecoder {
    private var buffer = Data()
    public init() {}

    public mutating func receive(_ data: Data) throws -> [PrinterReply] {
        guard buffer.count + data.count <= 8192 else {
            throw ServiceError("invalid_device_reply", "设备响应超过限制", status: 502)
        }
        buffer.append(data)
        var replies: [PrinterReply] = []
        while buffer.count >= 4 {
            let header = Array(buffer.prefix(4))
            guard header[0] == 0xAA else {
                buffer.removeFirst()
                continue
            }
            let length = Int(header[1]) + Int(header[2]) * 256
            guard (1...1024).contains(length) else {
                buffer.removeFirst()
                continue
            }
            guard buffer.count >= length + 4 else { break }
            let frame = Array(buffer.prefix(length + 4))
            guard frame.reduce(UInt8(0), &+) == 0 else {
                buffer.removeFirst()
                continue
            }
            buffer.removeFirst(length + 4)
            if let parameters = parameters(frame) {
                replies.append(PrinterReply(command: frame[3], parameters: parameters))
            }
        }
        return replies
    }

    private func parameters(_ frame: [UInt8]) -> [UInt8: [UInt8]]? {
        var values: [UInt8: [UInt8]] = [:]
        var offset = 4
        while offset < frame.count - 1 {
            guard offset + 3 <= frame.count - 1 else { return nil }
            let length = Int(frame[offset + 1]) + Int(frame[offset + 2]) * 256
            guard offset + 3 + length <= frame.count - 1, values[frame[offset]] == nil else { return nil }
            values[frame[offset]] = Array(frame[(offset + 3)..<(offset + 3 + length)])
            offset += 3 + length
        }
        return values
    }
}
