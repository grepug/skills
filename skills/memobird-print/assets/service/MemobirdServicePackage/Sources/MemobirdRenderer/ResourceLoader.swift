import Foundation
import MemobirdCore
import UniformTypeIdentifiers
import WebKit

/// All page resources pass through this loader; file URLs never reach WebKit.
@MainActor
final class ResourceLoader: NSObject, WKURLSchemeHandler {
    let root: URL
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private(set) var failures: [String] = []
    init(root: URL) { self.root = root }
    static func rewrite(_ source: String) -> String {
        source.replacingOccurrences(of: "https://", with: "memobird-https://")
            .replacingOccurrences(of: "http://", with: "memobird-http://")
    }
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        tasks[id] = Task { @MainActor in
            do {
                guard let url = urlSchemeTask.request.url else { throw ServiceError("resource", "资源 URL 无效") }
                var data: Data
                let mime: String
                if url.scheme == "memobird-resource" {
                    let path = String(url.path.dropFirst())
                    try ResourceAsset.validatePath(path)
                    let file = root.appendingPathComponent(path).standardizedFileURL
                    guard file.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/"),
                        let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 25_000_000
                    else {
                        throw ServiceError("resource", "资源不存在或超过大小限制")
                    }
                    data = try Data(contentsOf: file)
                    mime =
                        UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                } else {
                    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                    components.scheme = url.scheme == "memobird-https" ? "https" : "http"
                    guard let remote = components.url, components.user == nil, components.password == nil else {
                        throw ServiceError("resource", "远程资源 URL 无效")
                    }
                    var request = URLRequest(url: remote)
                    request.timeoutInterval = 15
                    // Stream the download so an oversized response cannot fill renderer memory.
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                        response.expectedContentLength <= 25_000_000
                    else {
                        throw ServiceError("resource", "远程资源下载失败或超过 25 MB")
                    }
                    mime = response.mimeType ?? "application/octet-stream"
                    data = Data()
                    for try await byte in bytes {
                        data.append(byte)
                        if data.count > 25_000_000 { throw ServiceError("resource", "远程资源超过 25 MB") }
                    }
                }
                if mime == "text/css", let css = String(data: data, encoding: .utf8) {
                    data = Data(Self.rewrite(css).utf8)
                }
                try Task.checkCancellation()
                guard tasks[id] != nil else { return }
                urlSchemeTask.didReceive(
                    URLResponse(
                        url: url, mimeType: mime, expectedContentLength: data.count,
                        textEncodingName: mime.hasPrefix("text/") ? "utf-8" : nil))
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                guard !Task.isCancelled, tasks[id] != nil else { return }
                failures.append("图片、样式或字体资源无法加载")
                urlSchemeTask.didFailWithError(error)
            }
            tasks.removeValue(forKey: id)
        }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        tasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }
}
