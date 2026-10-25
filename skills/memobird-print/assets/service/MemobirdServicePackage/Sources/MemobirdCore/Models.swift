import CryptoKit
import Foundation

/// Stable error envelope shared by the CLI, HTTP API, and renderer.
public struct ServiceError: Error, Codable, Sendable, LocalizedError {
    public let code: String
    public let message: String
    public let retryable: Bool
    public let status: Int
    public var errorDescription: String? { message }
    public init(_ code: String, _ message: String, status: Int = 400, retryable: Bool = false) {
        self.code = code
        self.message = message
        self.status = status
        self.retryable = retryable
    }
}

public enum JSON {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
    public static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct ResourceAsset: Codable, Sendable {
    public var path: String
    public var data: Data
    public var mimeType: String?
    public init(path: String, data: Data, mimeType: String? = nil) {
        self.path = path
        self.data = data
        self.mimeType = mimeType
    }
    public static func validatePath(_ path: String) throws {
        let decoded = path.removingPercentEncoding ?? path
        guard !decoded.isEmpty, decoded.utf8.count < 1024, !decoded.hasPrefix("/"),
            !decoded.contains("\\"), !decoded.contains(":"), !decoded.contains("\0"),
            decoded.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
                !$0.isEmpty && $0 != "." && $0 != ".."
            })
        else {
            throw ServiceError("invalid_asset_path", "资源必须使用安全的相对路径")
        }
    }
}

public enum DocumentKind: String, Codable, Sendable { case markdown, html, image }

public struct DocumentInput: Codable, Sendable {
    public var kind: DocumentKind
    public var content: String
    public var assets: [ResourceAsset]
    public var css: String
    public var font: String
    public var fontSize: Double
    public var printerBitmap: Bool
    public init(
        kind: DocumentKind, content: String, assets: [ResourceAsset] = [], css: String = "",
        font: String = "PingFang SC", fontSize: Double = 26, printerBitmap: Bool = false
    ) {
        self.kind = kind
        self.content = content
        self.assets = assets
        self.css = css
        self.font = font
        self.fontSize = fontSize
        self.printerBitmap = printerBitmap
    }
    private enum CodingKeys: String, CodingKey { case kind, content, assets, css, font, fontSize, printerBitmap }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try c.decode(DocumentKind.self, forKey: .kind),
            content: try c.decodeIfPresent(String.self, forKey: .content) ?? "",
            assets: try c.decodeIfPresent([ResourceAsset].self, forKey: .assets) ?? [],
            css: try c.decodeIfPresent(String.self, forKey: .css) ?? "",
            font: try c.decodeIfPresent(String.self, forKey: .font) ?? "PingFang SC",
            fontSize: try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 26,
            printerBitmap: try c.decodeIfPresent(Bool.self, forKey: .printerBitmap) ?? false)
    }
    public func validate() throws {
        guard content.utf8.count + css.utf8.count <= 2_000_000, fontSize.isFinite, (6...120).contains(fontSize),
            font.count < 256
        else {
            throw ServiceError("invalid_document", "文档/CSS 最多 2 MB，字号须在 6–120 之间")
        }
        var paths = Set<String>()
        for asset in assets {
            try ResourceAsset.validatePath(asset.path)
            guard paths.insert(asset.path).inserted, asset.data.count <= 25_000_000 else {
                throw ServiceError("invalid_asset", "资源路径重复或单个资源超过 25 MB")
            }
        }
        guard assets.count <= 256, assets.reduce(0, { $0 + $1.data.count }) <= 45_000_000 else {
            throw ServiceError("request_too_large", "每个任务资源总计最多 45 MB", status: 413)
        }
        if printerBitmap {
            guard kind == .image, assets.count == 1, content.isEmpty else {
                throw ServiceError("invalid_printer_bitmap", "原始打印位图模式仅支持单个图片资源", status: 422)
            }
            _ = try PrinterBitmap(assets[0].data)
        }
        if kind == .image, assets.isEmpty, !content.hasPrefix("data:image/") {
            throw ServiceError("missing_image", "图片任务需要一个图片资源或 data URL")
        }
    }
}

public struct PrintRequest: Codable, Sendable {
    public var document: DocumentInput?
    public var renderId: String?
    public init(document: DocumentInput? = nil, renderId: String? = nil) {
        self.document = document
        self.renderId = renderId
    }
}

public enum JobState: String, Codable, Sendable {
    case queued, rendering, rendered
    case waitingForPrinter = "waiting_for_printer"
    case sending, transmitted, failed, cancelled, uncertain
    public var terminal: Bool { [.rendered, .transmitted, .failed, .cancelled, .uncertain].contains(self) }
}

public struct RenderArtifacts: Codable, Sendable {
    public var pdf: String?
    public var bitmaps: [String]
    public var height: Int
    public init(pdf: String? = nil, bitmaps: [String], height: Int) {
        self.pdf = pdf
        self.bitmaps = bitmaps
        self.height = height
    }
}

public struct Job: Codable, Sendable {
    public var id: String
    public var mode: String
    public var state: JobState
    public var createdAt: Date
    public var updatedAt: Date
    public var artifacts: RenderArtifacts?
    public var error: ServiceError?
    public var deviceAcknowledgement: String?
    public var artifactsExpired: Bool
    public init(id: String, mode: String, state: JobState = .queued) {
        self.id = id
        self.mode = mode
        self.state = state
        createdAt = Date()
        updatedAt = createdAt
        artifactsExpired = false
    }
}

public struct WorkerInput: Codable, Sendable {
    public let directory: String
    public let fontsDirectory: String
    public let document: DocumentInput
    public init(directory: String, fontsDirectory: String, document: DocumentInput) {
        self.directory = directory
        self.fontsDirectory = fontsDirectory
        self.document = document
    }
}

public struct WorkerOutput: Codable, Sendable {
    public var artifacts: RenderArtifacts?
    public var error: ServiceError?
    public init(artifacts: RenderArtifacts? = nil, error: ServiceError? = nil) {
        self.artifacts = artifacts
        self.error = error
    }
}

public struct ServicePaths: Codable, Sendable {
    public var root: String
    public var tokenFile: String
    public var logs: String
    public var jobs: String
    public var fonts: String
    public init(root: URL) {
        self.root = root.path
        tokenFile = root.appendingPathComponent("token").path
        logs = root.appendingPathComponent("logs").path
        jobs = root.appendingPathComponent("jobs").path
        fonts = root.appendingPathComponent("fonts").path
    }
    public static var localRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/local.memobird.mac/Data/Library/Application Support/MemobirdService")
    }
}
