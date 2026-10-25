import CoreGraphics
import Foundation
import MemobirdCore

extension RendererMain {
    /// Preserve approved raster bytes; create the PDF from their actual top-first row order.
    static func preservedBitmap(_ data: Data, pdfURL: URL) throws -> [Data] {
        let bitmap = try PrinterBitmap(data)
        let bytes = [UInt8](data)
        var gray = [UInt8](repeating: 255, count: bitmap.width * bitmap.height)
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width where bytes[62 + y * bitmap.rowStride + x / 8] & (0x80 >> (x % 8)) != 0 {
                gray[y * bitmap.width + x] = 0
            }
        }
        guard let provider = CGDataProvider(data: Data(gray) as CFData),
            let image = CGImage(width: bitmap.width, height: bitmap.height, bitsPerComponent: 8,
                bitsPerPixel: 8, bytesPerRow: bitmap.width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)
        else { throw ServiceError("invalid_printer_bitmap", "无法生成位图预览", status: 422) }
        var bounds = CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height)
        guard let consumer = CGDataConsumer(url: pdfURL as CFURL),
            let pdf = CGContext(consumer: consumer, mediaBox: &bounds, nil)
        else { throw ServiceError("pdf_failed", "无法生成位图PDF预览", status: 422) }
        pdf.beginPDFPage(nil)
        pdf.draw(image, in: bounds)
        pdf.endPDFPage()
        pdf.closePDF()
        return [bitmap.data]
    }
}
