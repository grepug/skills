import CoreGraphics
import Foundation
import MemobirdCore

enum PDFRasterizer {
    /// Rasterizes every PDF page in top-to-bottom stripes, including offscreen content.
    static func bitmaps(from data: Data) throws -> [Data] {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var bitmaps: [Data] = []
        var accumulatedHeight = 0
        for index in 1...max(1, document.numberOfPages) {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.getBoxRect(.mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { throw CocoaError(.fileReadCorruptFile) }
            let scale = 576 / bounds.width
            let height = Int(ceil(bounds.height * scale))
            accumulatedHeight += height
            guard accumulatedHeight <= 30_000 else {
                throw NSError(
                    domain: "PrintDocument", code: 1, userInfo: [NSLocalizedDescriptionKey: "内容过长，请拆成较短的文档打印"])
            }
            for top in stride(from: 0, to: height, by: 1600) {
                let stripeHeight = min(1600, height - top)
                var grayscale = [UInt8](repeating: 255, count: 576 * stripeHeight)
                try grayscale.withUnsafeMutableBytes { buffer in
                    guard
                        let context = CGContext(
                            data: buffer.baseAddress, width: 576, height: stripeHeight,
                            bitsPerComponent: 8, bytesPerRow: 576, space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)
                    else { throw CocoaError(.fileReadUnknown) }
                    context.setFillColor(gray: 1, alpha: 1)
                    context.fill(CGRect(x: 0, y: 0, width: 576, height: stripeHeight))
                    context.translateBy(x: 0, y: -CGFloat(height - top - stripeHeight))
                    context.scaleBy(x: scale, y: scale)
                    context.translateBy(x: -bounds.minX, y: -bounds.minY)
                    context.drawPDFPage(page)
                }
                bitmaps.append(
                    MonochromeBitmap.encode(grayscale: grayscale, width: 576, height: stripeHeight, dither: true))
            }
        }
        return bitmaps
    }
}
