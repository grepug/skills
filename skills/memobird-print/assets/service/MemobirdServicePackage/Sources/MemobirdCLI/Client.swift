import ArgumentParser
import Foundation
import MemobirdCore

struct ClientOptions: ParsableArguments {
    @Option(name: .customLong("url"), help: "服务 URL，或 MEMOBIRD_URL") var url =
        ProcessInfo.processInfo.environment["MEMOBIRD_URL"] ?? "http://127.0.0.1:8765"
    @Option(name: .customLong("token-file"), help: "令牌文件，或 MEMOBIRD_TOKEN_FILE") var tokenFile =
        ProcessInfo.processInfo.environment["MEMOBIRD_TOKEN_FILE"]
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/memobird/token").path
    @Flag(help: "输出机器可读 JSON") var json = false
    func client() throws -> Client { try Client(options: self) }
}

struct Client {
    let options: ClientOptions
    let token: String
    init(options: ClientOptions) throws {
        self.options = options
        do {
            token = try String(contentsOfFile: options.tokenFile, encoding: .utf8).trimmingCharacters(
                in: .whitespacesAndNewlines)
        } catch { throw ServiceError("missing_token", "无法读取令牌文件；请安装本机服务或指定 --token-file") }
    }
    func request(_ path: String, method: String = "GET", body: Data? = nil, key: String? = nil) async throws -> Data {
        guard let url = URL(string: options.url.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path),
            ["http", "https"].contains(url.scheme)
        else { throw ServiceError("invalid_url", "服务 URL 必须使用 HTTP 或 HTTPS") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 90
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key { request.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) } catch {
            let detail = key.map { "；提交结果可能不确定，重试须复用幂等键 \($0)" } ?? ""
            throw ServiceError("connection_failed", "无法连接服务或响应中断" + detail, status: 503, retryable: true)
        }
        guard let response = response as? HTTPURLResponse else {
            throw ServiceError("invalid_response", "服务未返回 HTTP 响应", status: 502)
        }
        guard (200..<300).contains(response.statusCode) else {
            if let envelope = try? JSON.decode([String: ServiceError].self, from: data), let error = envelope["error"] {
                throw error
            }
            throw ServiceError("http_error", "HTTP \(response.statusCode)", status: response.statusCode)
        }
        return data
    }
    func wait(_ id: String, timeout: TimeInterval = 300) async throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let data = try await request("/v1/jobs/" + id)
            let job = try JSON.decode(Job.self, from: data)
            if job.state.terminal { return data }
            guard Date() < deadline else {
                throw ServiceError("wait_timeout", "等待超时；任务仍保留，请用 jobs get \(id) 查询", status: 408, retryable: true)
            }
            try await Task.sleep(for: .milliseconds(500))
        }
    }
}

func emit(_ data: Data, json: Bool) throws {
    if json {
        try FileHandle.standardOutput.write(contentsOf: data + Data([10]))
    } else {
        let value = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        let pretty = try JSONSerialization.data(
            withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
        try FileHandle.standardOutput.write(contentsOf: pretty + Data([10]))
    }
}

struct DocumentOptions: ParsableArguments {
    @Argument(help: "输入文件，- 表示 stdin") var input = "-"
    @Option(help: "附加 CSS 文件") var css: String?
    @Option(help: "字体家族名") var font = "PingFang SC"
    @Option(name: .customLong("font-size")) var fontSize: Double = 26
    @Option(name: .customLong("assets-dir"), help: "递归打包资源目录；默认输入文件所在目录") var assetsDirectory: String?
    @Option(name: .customLong("idempotency-key"), help: "重试时复用同一键") var idempotencyKey: String?
    @Flag(name: .customLong("printer-bitmap"), help: "保留576点宽打印机原始1位BMP；仅图片，软件高度上限4000行，实机长图上限待验证") var printerBitmap = false
    @Flag(help: "等待任务结束") var wait = false
    @Option(help: "--wait 的秒数上限") var timeout: Double = 300
    @OptionGroup var connection: ClientOptions

    func document(_ kind: DocumentKind) throws -> DocumentInput {
        let data: Data
        let inputURL: URL?
        if input == "-" {
            inputURL = nil
            var buffer = Data()
            let maximum = kind == .image ? 25_000_000 : 2_000_000
            while let chunk = try FileHandle.standardInput.read(upToCount: 65536), !chunk.isEmpty {
                buffer.append(chunk)
                guard buffer.count <= maximum else { throw ServiceError("input_size", "stdin 超过大小限制") }
            }
            data = buffer
        } else {
            inputURL = URL(fileURLWithPath: input).standardizedFileURL
            guard let size = try inputURL?.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                size <= (kind == .image ? 25_000_000 : 2_000_000)
            else { throw ServiceError("input_size", "输入不存在或超出大小限制") }
            data = try Data(contentsOf: inputURL!)
        }
        var assets: [ResourceAsset] = []
        let content: String
        if kind == .image {
            content = ""
            assets = [ResourceAsset(path: inputURL?.lastPathComponent ?? "image.png", data: data)]
        } else {
            guard let text = String(data: data, encoding: .utf8) else { throw ServiceError("encoding", "文档须为 UTF-8") }
            content = text
            let root =
                assetsDirectory.map { URL(fileURLWithPath: $0).standardizedFileURL }
                ?? inputURL?.deletingLastPathComponent()
            if let root {
                // Only document assets are bundled; skip source/build trees and unrelated files.
                let allowed = Set([
                    "png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "heic", "tif", "tiff", "css", "ttf", "otf",
                    "ttc", "woff", "woff2",
                ])
                if let enumerator = FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                    options: [.skipsHiddenFiles])
                {
                    for case let file as URL in enumerator {
                        if ["node_modules", "build", "output", "DerivedData"].contains(file.lastPathComponent) {
                            enumerator.skipDescendants()
                            continue
                        }
                        let values = try file.resourceValues(forKeys: [
                            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
                        ])
                        guard values.isSymbolicLink != true else {
                            enumerator.skipDescendants()
                            continue
                        }
                        guard values.isRegularFile == true, allowed.contains(file.pathExtension.lowercased()) else {
                            continue
                        }
                        guard (values.fileSize ?? 0) <= 25_000_000 else {
                            throw ServiceError("asset_size", "资源超过 25 MB")
                        }
                        let path = String(
                            file.resolvingSymlinksInPath().path.dropFirst(root.resolvingSymlinksInPath().path.count + 1)
                        )
                        assets.append(ResourceAsset(path: path, data: try Data(contentsOf: file)))
                        guard assets.count <= 256, assets.reduce(0, { $0 + $1.data.count }) <= 45_000_000 else {
                            throw ServiceError("assets_size", "资源目录过大，请指定较小的 --assets-dir")
                        }
                    }
                }
            }
        }
        let style = try css.map { try String(contentsOfFile: $0, encoding: .utf8) } ?? ""
        let result = DocumentInput(
            kind: kind, content: content, assets: assets.sorted { $0.path < $1.path }, css: style, font: font,
            fontSize: fontSize, printerBitmap: printerBitmap)
        try result.validate()
        return result
    }
    func submit(kind: DocumentKind, mode: String) async throws {
        let client = try connection.client()
        let input = PrintRequest(document: try document(kind))
        let key = idempotencyKey ?? UUID().uuidString.lowercased()
        let data = try await client.request(
            mode == "render" ? "/v1/renders" : "/v1/jobs", method: "POST", body: JSON.encode(input), key: key)
        let job = try JSON.decode(Job.self, from: data)
        let result = wait ? try await client.wait(job.id, timeout: timeout) : data
        try emit(result, json: connection.json)
        if wait {
            let final = try JSON.decode(Job.self, from: result)
            if [.failed, .uncertain, .cancelled].contains(final.state) {
                throw ServiceError(
                    final.error?.code ?? final.state.rawValue,
                    "任务 \(final.id)：" + (final.error?.message ?? final.state.rawValue),
                    status: final.error?.status ?? 409)
            }
        }
    }
}
