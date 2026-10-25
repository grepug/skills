import Foundation
import Hummingbird
import MemobirdCore

/// One authenticated API surface; no page server, cookies, or cross-origin access.
struct HTTPAPI: HTTPResponder {
    typealias Context = BasicRequestContext
    let coordinator: PrintCoordinator
    let token: String

    func respond(to request: Request, context: Context) async throws -> Response {
        do {
            guard request.headers[.authorization] == "Bearer " + token else {
                throw ServiceError("unauthorized", "需要有效 Bearer Token", status: 401)
            }
            guard request.headers[.origin] == nil else {
                throw ServiceError("cross_origin_disabled", "不支持浏览器跨域请求", status: 403)
            }
            let path = request.uri.path.split(separator: "/").map(String.init)
            let method = request.method.rawValue
            let query = request.uri.queryParameters
            func parameter(_ key: String) -> String? { query[Substring(key)].map(String.init) }
            if path == ["v1", "status"], method == "GET" { return try await json(coordinator.status()) }
            if path == ["v1", "paths"], method == "GET" { return try json(ServicePaths(root: coordinator.root)) }
            if path == ["v1", "printers"], method == "GET" { return try await json(coordinator.printerStatus()) }
            if path == ["v1", "printers", "scan"], method == "POST" { return try await json(coordinator.scan()) }
            if path == ["v1", "printer", "connect"], method == "POST" {
                let input: [String: String] = try await decode(request)
                return try await json(coordinator.connect(input["id"]))
            }
            if path == ["v1", "printer", "disconnect"], method == "POST" {
                return try await json(coordinator.disconnect())
            }
            if path == ["v1", "printer", "power"], method == "GET" {
                return try await json(coordinator.power())
            }
            if path == ["v1", "printer", "auto-off"], method == "POST" {
                let input: [String: Int] = try await decode(request)
                guard let minutes = input["minutes"] else {
                    throw ServiceError("invalid_setting", "须提供 minutes，0 表示关闭自动关机")
                }
                return try await json(coordinator.autoOff(minutes: minutes))
            }
            if path == ["v1", "jobs"] || path == ["v1", "renders"] {
                if method == "GET", path.last == "jobs" {
                    let jobs = try coordinator.store.list()
                    let limit = min(1000, max(1, Int(parameter("limit") ?? "200") ?? 200))
                    return try json(Array(jobs.suffix(limit).reversed()))
                }
                if method == "POST" {
                    let input: PrintRequest = try await decode(request)
                    let key = request.headers[.init("Idempotency-Key")!]
                    let job = try await coordinator.submit(
                        input, key: key, mode: path.last == "renders" ? "render" : "print")
                    return try json(job, status: .accepted)
                }
            }
            if path.count >= 3, Array(path.prefix(2)) == ["v1", "jobs"] {
                let store = coordinator.store
                let job = try store.get(path[2])
                if path.count == 3, method == "GET" { return try json(job) }
                if path.count == 4, path[3] == "purge", method == "POST" {
                    try store.purgeArtifacts(job.id)
                    return try json(store.get(job.id))
                }
                if path.count == 4, path[3] == "cancel", method == "POST" {
                    return try await json(coordinator.cancel(job.id))
                }
                if path.count == 5, path[3] == "artifacts", method == "GET" {
                    let name = path[4]
                    guard !job.artifactsExpired, let artifacts = job.artifacts,
                        artifacts.bitmaps.contains(name) || artifacts.pdf == name
                    else { throw ServiceError("artifact_not_found", "文件不存在或已过期", status: 404) }
                    let data = try Data(
                        contentsOf: store.directory(job.id).appendingPathComponent(name), options: .mappedIfSafe)
                    return Response(
                        status: .ok,
                        headers: [
                            .contentType: name.hasSuffix(".pdf") ? "application/pdf" : "image/bmp",
                            .cacheControl: "no-store",
                        ], body: .init(byteBuffer: ByteBuffer(bytes: data)))
                }
            }
            if path == ["v1", "fonts"] {
                if method == "GET" { return try await json(coordinator.fonts()) }
                if method == "POST" {
                    let asset: ResourceAsset = try await decode(request)
                    return try await json(coordinator.addFont(asset), status: .created)
                }
            }
            if path.count == 3, Array(path.prefix(2)) == ["v1", "fonts"], method == "DELETE" {
                try await coordinator.removeFont(path[2])
                return try json(["status": "removed"])
            }
            if path == ["v1", "logs"], method == "GET" {
                let since = parameter("since").flatMap { ISO8601DateFormatter().date(from: $0) }
                return try json(
                    coordinator.log.read(
                        jobId: parameter("job"), level: parameter("level"), since: since,
                        limit: Int(parameter("limit") ?? "2000") ?? 2000))
            }
            if path == ["v1", "maintenance", "prune"], method == "POST" {
                try await coordinator.prune()
                return try json(["status": "pruned"])
            }
            throw ServiceError("not_found", "接口不存在", status: 404)
        } catch {
            let error = error as? ServiceError ?? ServiceError("internal_error", "服务内部错误", status: 500)
            return try json(["error": error], status: .init(code: error.status))
        }
    }
    private func decode<T: Decodable>(_ request: Request) async throws -> T {
        if let length = request.headers[.contentLength].flatMap(Int.init), length > 64_000_000 {
            throw ServiceError("request_too_large", "请求最多 64 MB", status: 413)
        }
        let buffer: ByteBuffer
        do { buffer = try await request.body.collect(upTo: 64_000_000) } catch {
            throw ServiceError("invalid_body", "请求体超出大小限制或连接中断", status: 413)
        }
        do { return try JSON.decode(T.self, from: Data(buffer.readableBytesView)) } catch {
            throw ServiceError("invalid_json", "JSON 请求格式无效")
        }
    }
    private func json<T: Encodable>(_ value: T, status: HTTPResponse.Status = .ok) throws -> Response {
        Response(
            status: status, headers: [.contentType: "application/json; charset=utf-8", .cacheControl: "no-store"],
            body: .init(byteBuffer: ByteBuffer(bytes: try JSON.encode(value))))
    }
}
