import AppKit
import MemobirdCore
import WebKit

/// A renderer exists only for the duration of one helper process.
@MainActor
final class HTMLRenderer: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let resources: ResourceLoader
    private var continuation: CheckedContinuation<Void, any Error>?
    private var timeout: Task<Void, Never>?
    init(root: URL) {
        resources = ResourceLoader(root: root)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        for scheme in ["memobird-resource", "memobird-http", "memobird-https"] {
            configuration.setURLSchemeHandler(resources, forURLScheme: scheme)
        }
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 576, height: 1), configuration: configuration)
        webView.mediaType = "print"
        super.init()
        webView.navigationDelegate = self
    }
    func pdf(document: DocumentInput) async throws -> Data {
        var body = document.content
        if document.kind == .markdown {
            let markdown = try MarkdownHTML.parse(body)
            body = markdown.body
            for (index, source) in markdown.imageSources.enumerated() {
                let safe = source.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(
                    of: "\"", with: "&quot;")
                body = body.replacingOccurrences(of: "memobird-image:\(index)", with: safe)
            }
        }
        let font = String(data: try JSON.encode(document.font), encoding: .utf8)!
        let defaults = """
            <meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: memobird-resource: memobird-http: memobird-https:; style-src 'unsafe-inline' data: memobird-resource: memobird-http: memobird-https:; font-src data: memobird-resource: memobird-http: memobird-https:; script-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'">
            <style>
            *{box-sizing:border-box}html{margin:0;background:white;color:black}body{width:576px;margin:0;padding:18px 20px 30px;font:\(document.fontSize)px/1.48 \(font),sans-serif;overflow-wrap:anywhere}
            h1,h2,h3{line-height:1.25;margin:.8em 0 .35em}h1{font-size:1.5em;border-bottom:2px solid;padding-bottom:10px}h2{font-size:1.25em}p{margin:.55em 0}
            img{max-width:100%;height:auto}pre{font:19px/1.4 Menlo,monospace;border:1px solid;padding:12px;white-space:pre-wrap;overflow-wrap:anywhere}code{font-family:Menlo,monospace}ul,ol{padding-left:34px}blockquote{margin:16px 0;padding-left:18px;border-left:4px solid}
            table{border-collapse:collapse;width:100%;font-size:.8em;table-layout:fixed}td,th{border:1px solid;padding:7px;overflow-wrap:anywhere}a{color:black}
            </style>
            """
        let custom = "<style>\(document.css.replacingOccurrences(of: "</style", with: "<\\/style"))</style>"
        var html: String
        if let head = body.range(of: "<head\\b[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            html = body
            html.insert(contentsOf: defaults, at: head.upperBound)
            if let close = html.range(of: "</head>", options: .caseInsensitive) {
                html.insert(contentsOf: custom, at: close.lowerBound)
            } else {
                html += custom
            }
        } else if let element = body.range(of: "<html\\b[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            html = body
            html.insert(contentsOf: "<head>\(defaults)\(custom)</head>", at: element.upperBound)
        } else {
            html = "<!doctype html><html><head>\(defaults)\(custom)</head><body>\(body)</body></html>"
        }
        html = ResourceLoader.rewrite(html)
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: URL(string: "memobird-resource://job/index.html"))
            timeout = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                self?.finish(.failure(ServiceError("render_timeout", "页面加载超过 20 秒", status: 422)))
            }
        }
        // Host-owned evaluation is allowed while page JavaScript remains disabled.
        let result = try await webView.callAsyncJavaScript(
            """
            await document.fonts.ready;
            await Promise.all(Array.from(document.images).map(i => i.complete ? Promise.resolve() : new Promise(r => {i.onload=r;i.onerror=r})));
            await new Promise(r => setTimeout(r, 30));
            return {width:Math.max(576,document.documentElement.scrollWidth,document.body.scrollWidth),height:Math.max(document.documentElement.scrollHeight,document.body.scrollHeight),badImages:Array.from(document.images).filter(i=>!i.complete||!i.naturalWidth).length,badFonts:Array.from(document.fonts).filter(f=>f.status==='error').length};
            """, arguments: [:], in: nil, contentWorld: .page)
        guard let values = result as? [String: Any], let width = values["width"] as? Double,
            let height = values["height"] as? Double,
            width > 0, height > 0, width <= 12000, height * 576 / width <= 30_000
        else { throw ServiceError("document_too_long", "页面超过打印尺寸限制", status: 422) }
        guard resources.failures.isEmpty, (values["badImages"] as? Int ?? 0) == 0,
            (values["badFonts"] as? Int ?? 0) == 0
        else {
            throw ServiceError("resource_failed", "图片、样式或字体资源缺失或无法解码", status: 422)
        }
        let configuration = WKPDFConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: width, height: height)
        return try await webView.pdf(configuration: configuration)
    }
    private func finish(_ result: Result<Void, any Error>) {
        timeout?.cancel()
        timeout = nil
        let current = continuation
        continuation = nil
        current?.resume(with: result)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finish(.failure(error))
    }
    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
    ) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async
        -> WKNavigationActionPolicy
    {
        navigationAction.targetFrame?.isMainFrame == true && navigationAction.navigationType == .other
            ? .allow : .cancel
    }
}
