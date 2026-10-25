import Foundation
import Testing
@testable import MemobirdCore

struct PrinterBitmapTests {
    @Test func preserves1830RowNativeBitmapWithoutReencoding() throws {
        let data = MonochromeBitmap.encode(grayscale: [UInt8](repeating: 255, count: 576 * 1830), width: 576, height: 1830)
        let bitmap = try PrinterBitmap(data)
        #expect(bitmap.data == data)
        #expect(bitmap.width == 576 && bitmap.height == 1830 && bitmap.rowStride == 72)
        try DocumentInput(kind: .image, content: "", assets: [.init(path: "native.bmp", data: data)], printerBitmap: true).validate()
    }
    @Test func rejectsCorruptOrUnsupportedNativeBitmap() throws {
        let data = MonochromeBitmap.encode(grayscale: [UInt8](repeating: 255, count: 576 * 2), width: 576, height: 2)
        for offset in [0, 2, 10, 14, 18, 22, 26, 28, 30, 34, 54] {
            var damaged = data; damaged[offset] ^= 1
            #expect(throws: ServiceError.self) { _ = try PrinterBitmap(damaged) }
        }
        #expect(throws: ServiceError.self) { _ = try PrinterBitmap(data.dropLast()) }
        var tall = data; tall[22] = 0xA1; tall[23] = 0x0F
        #expect(throws: ServiceError.self) { _ = try PrinterBitmap(tall) }
        #expect(throws: ServiceError.self) { try DocumentInput(kind: .html, content: "x", printerBitmap: true).validate() }
    }
    @Test func oldRequestsRetainDefaultRendering() throws {
        let input = try JSON.decode(DocumentInput.self, from: Data("{\"kind\":\"html\",\"content\":\"hello\"}".utf8))
        #expect(!input.printerBitmap)
        try input.validate()
    }
}
