import Foundation

struct PrinterFlowControl {
    private(set) var credits = 0
    private(set) var printerMTU = 0

    /// FF03 sends credit increments (01 nn) and little-endian MTU (02 lo hi).
    mutating func receive(_ data: Data) {
        let bytes = Array(data)
        guard let type = bytes.first else { return }
        if type == 1, bytes.count >= 2 {
            credits = min(65535, credits + Int(bytes[1]))
        } else if type == 2, bytes.count >= 3 {
            printerMTU = Int(bytes[1]) + Int(bytes[2]) * 256
        }
    }

    mutating func nextChunk(from data: Data, maximumLength: Int) -> Data? {
        let length = min(data.count, printerMTU, maximumLength)
        guard credits > 0, length > 0 else { return nil }
        credits -= 1
        return Data(data.prefix(length))
    }
}
