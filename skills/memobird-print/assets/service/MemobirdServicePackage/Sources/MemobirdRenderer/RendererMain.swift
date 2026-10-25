import AppKit
import CoreText
import ImageIO
import MemobirdCore

@main
@MainActor
struct RendererMain {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let parent = getppid()
        let parentWatch = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if getppid() != parent { exit(1) }
        }
        _ = parentWatch
        Task { @MainActor in
            do {
                let input = try JSON.decode(
                    WorkerInput.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
                try input.document.validate()
                let directory = URL(fileURLWithPath: input.directory)
                let assets = directory.appendingPathComponent("assets")
                try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
                for resource in input.document.assets {
                    let file = assets.appendingPathComponent(resource.path)
                    try FileManager.default.createDirectory(
                        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try resource.data.write(to: file)
                }
                try registerFonts([assets, URL(fileURLWithPath: input.fontsDirectory)])
                let bitmaps: [Data]
                var pdfName: String?
                if input.document.kind == .image {
                    let data: Data
                    if let first = input.document.assets.first {
                        data = first.data
                    } else if let comma = input.document.content.firstIndex(of: ","),
                        let decoded = Data(
                            base64Encoded: String(input.document.content[input.document.content.index(after: comma)...])
                        )
                    {
                        data = decoded
                    } else {
                        throw ServiceError("invalid_image", "图片数据无效", status: 422)
                    }
                    if input.document.printerBitmap {
                        bitmaps = try preservedBitmap(data, pdfURL: directory.appendingPathComponent("document.pdf"))
                    } else {
                        bitmaps = try imageBitmaps(data, pdfURL: directory.appendingPathComponent("document.pdf"))
                    }
                    pdfName = "document.pdf"
                } else {
                    let renderer = HTMLRenderer(root: assets)
                    let pdf = try await renderer.pdf(document: input.document)
                    try pdf.write(to: directory.appendingPathComponent("document.pdf"), options: .atomic)
                    pdfName = "document.pdf"
                    bitmaps = try PDFRasterizer.bitmaps(from: pdf)
                }
                var names: [String] = []
                var height = 0
                for (index, bitmap) in bitmaps.enumerated() {
                    let name = String(format: "stripe-%04d.bmp", index)
                    try bitmap.write(to: directory.appendingPathComponent(name), options: .atomic)
                    names.append(name)
                    if bitmap.count >= 26 {
                        height += Int(bitmap[22]) | Int(bitmap[23]) << 8 | Int(bitmap[24]) << 16 | Int(bitmap[25]) << 24
                    }
                }
                try FileHandle.standardOutput.write(
                    contentsOf: JSON.encode(
                        WorkerOutput(artifacts: RenderArtifacts(pdf: pdfName, bitmaps: names, height: height))))
                exit(0)
            } catch {
                let failure =
                    error as? ServiceError
                    ?? ServiceError("render_failed", "渲染失败：\(error.localizedDescription)", status: 422)
                if let data = try? JSON.encode(WorkerOutput(error: failure)) {
                    try? FileHandle.standardOutput.write(contentsOf: data)
                }
                exit(1)
            }
        }
        application.run()
    }

    static func registerFonts(_ roots: [URL]) throws {
        for root in roots {
            if let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
                for case let file as URL in files where ["ttf", "otf", "ttc"].contains(file.pathExtension.lowercased())
                {
                    guard CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil) else {
                        throw ServiceError("invalid_font", "字体无法注册", status: 422)
                    }
                }
            }
        }
    }

    /// Image-only work skips WebKit entirely and preserves portrait orientation.
    static func imageBitmaps(_ data: Data, pdfURL: URL) throws -> [Data] {
        guard data.count <= 25_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let rawWidth = properties[kCGImagePropertyPixelWidth] as? Double,
            let rawHeight = properties[kCGImagePropertyPixelHeight] as? Double,
            rawWidth > 0, rawHeight > 0
        else { throw ServiceError("invalid_image", "图片无法解码", status: 422) }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let displayWidth = (5...8).contains(orientation) ? rawHeight : rawWidth
        let displayHeight = (5...8).contains(orientation) ? rawWidth : rawHeight
        guard displayHeight * 576 / displayWidth <= 30000 else {
            throw ServiceError("image_too_tall", "图片高度超过 30,000 像素", status: 422)
        }
        // Decode near printer resolution instead of expanding a multi-megapixel original.
        let maximumDimension = min(30000, max(1, Int(ceil(max(rawWidth, rawHeight) * min(1, 576 / displayWidth)))))
        guard
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                ] as CFDictionary)
        else { throw ServiceError("invalid_image", "图片无法解码", status: 422) }
        let height = Int(ceil(Double(image.height) * 576 / Double(image.width)))
        guard height > 0, height <= 30000 else { throw ServiceError("image_too_tall", "图片高度超过 30,000 像素", status: 422) }
        var bounds = CGRect(x: 0, y: 0, width: 576, height: height)
        guard let consumer = CGDataConsumer(url: pdfURL as CFURL),
            let pdf = CGContext(consumer: consumer, mediaBox: &bounds, nil)
        else {
            throw ServiceError("pdf_failed", "无法生成图片 PDF 预览", status: 422)
        }
        pdf.beginPDFPage(nil)
        pdf.setFillColor(gray: 1, alpha: 1)
        pdf.fill(bounds)
        pdf.draw(image, in: bounds)
        pdf.endPDFPage()
        pdf.closePDF()
        var bitmaps: [Data] = []
        for top in stride(from: 0, to: height, by: 1600) {
            let stripeHeight = min(1600, height - top)
            var pixels = [UInt8](repeating: 255, count: 576 * stripeHeight)
            try pixels.withUnsafeMutableBytes { buffer in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: 576, height: stripeHeight, bitsPerComponent: 8,
                        bytesPerRow: 576, space: CGColorSpaceCreateDeviceGray(),
                        bitmapInfo: CGImageAlphaInfo.none.rawValue)
                else { throw CocoaError(.fileReadUnknown) }
                context.setFillColor(gray: 1, alpha: 1)
                context.fill(CGRect(x: 0, y: 0, width: 576, height: stripeHeight))
                context.draw(image, in: CGRect(x: 0, y: -height + top + stripeHeight, width: 576, height: height))
            }
            bitmaps.append(MonochromeBitmap.encode(grayscale: pixels, width: 576, height: stripeHeight, dither: true))
        }
        return bitmaps
    }
}
