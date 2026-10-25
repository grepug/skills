import Foundation

/// Printer-native BMP: positive height but top-first rows, white index 0 and black index 1.
/// This is an explicit per-document import format, not a general-purpose BMP decoder.
public struct PrinterBitmap: Sendable {
    public static let maximumHeight = 4000 // Software guard only; hardware limit remains unverified.
    public let data: Data
    public let width: Int
    public let height: Int
    public let rowStride: Int

    public init(_ data: Data) throws {
        func invalid() -> ServiceError {
            ServiceError("invalid_printer_bitmap", "须为576点宽、1–4000行、62字节头、白0黑1、顶行优先的未压缩1位打印BMP；4000行仅为软件保护上限", status: 422)
        }
        guard data.count >= 62 else { throw invalid() }
        let b = [UInt8](data.prefix(62))
        func little(_ offset: Int, _ count: Int = 4) -> Int {
            (0..<count).reduce(0) { $0 | Int(b[offset + $1]) << ($1 * 8) }
        }
        let width = little(18), height = little(22)
        guard b[0] == 0x42, b[1] == 0x4D,
            little(2) == data.count, little(10) == 62, little(14) == 40,
            width == 576, (1...Self.maximumHeight).contains(height),
            little(26, 2) == 1, little(28, 2) == 1, little(30) == 0,
            [0, 2].contains(little(46)),
            Array(b[54..<62]) == [255, 255, 255, 0, 0, 0, 0, 0]
        else { throw invalid() }
        let stride = ((width + 31) / 32) * 4
        guard little(34) == stride * height, data.count == 62 + stride * height else { throw invalid() }
        self.data = data
        self.width = width
        self.height = height
        self.rowStride = stride
    }
}
