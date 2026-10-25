import Foundation

public enum MonochromeBitmap {
    /// SDK oneFiveBmpImgData uses white palette index 0, black index 1, top-first rows.
    public static func encode(grayscale: [UInt8], width: Int, height: Int, dither: Bool = false) -> Data {
        guard width > 0, width <= 576, height > 0, height <= 4000,
            grayscale.count == width * height
        else { return Data() }
        let stride = ((width + 31) / 32) * 4
        var bytes = [UInt8](repeating: 0, count: 62 + stride * height)
        func write(_ value: Int, at offset: Int, length: Int = 4) {
            for index in 0..<length { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8)) }
        }
        bytes[0] = 0x42
        bytes[1] = 0x4D
        write(bytes.count, at: 2)
        write(62, at: 10)
        write(40, at: 14)
        write(width, at: 18)
        write(height, at: 22)
        write(1, at: 26, length: 2)
        write(1, at: 28, length: 2)
        write(stride * height, at: 34)
        bytes[54] = 255
        bytes[55] = 255
        bytes[56] = 255
        var currentError = [Double](repeating: 0, count: width + 2)
        var nextError = currentError
        for y in 0..<height {
            for x in 0..<width {
                let value = min(255, max(0, Double(grayscale[y * width + x]) + currentError[x + 1]))
                let isBlack = value < 128
                if isBlack { bytes[62 + y * stride + x / 8] |= 0x80 >> (x % 8) }
                if dither {
                    let error = value - (isBlack ? 0 : 255)
                    currentError[x + 2] += error * 7 / 16
                    nextError[x] += error * 3 / 16
                    nextError[x + 1] += error * 5 / 16
                    nextError[x + 2] += error / 16
                }
            }
            currentError = nextError
            nextError = [Double](repeating: 0, count: width + 2)
        }
        return Data(bytes)
    }
}
