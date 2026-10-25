import Foundation
import JavaScriptCore

struct MarkdownHTML {
    let body: String
    let imageSources: [String]

    static func parse(_ markdown: String) throws -> MarkdownHTML {
        guard let url = Bundle.module.url(forResource: "markdown-it.umd.min", withExtension: "js"),
            let context = JSContext()
        else { throw CocoaError(.fileReadUnknown) }
        let decodeBase64: @convention(block) (String) -> String = { source in
            guard let data = Data(base64Encoded: source) else { return "" }
            return String(data: data, encoding: .isoLatin1) ?? ""
        }
        context.setObject(decodeBase64, forKeyedSubscript: "atob" as NSString)
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        if let exception = context.exception {
            throw NSError(
                domain: "Markdown", code: 1, userInfo: [NSLocalizedDescriptionKey: exception.toString() ?? "解析器加载失败"])
        }
        context.evaluateScript(
            """
            function renderDocument(source) {
              const parser = markdownit({html:false, linkify:true, breaks:false});
              const images = [];
              const imageRule = parser.renderer.rules.image;
              parser.renderer.rules.image = function(tokens,index,options,env,self) {
                const token = tokens[index];
                images.push(token.attrGet('src'));
                token.attrSet('src','memobird-image:' + (images.length - 1));
                return imageRule(tokens,index,options,env,self);
              };
              return {body:parser.render(source), images:images};
            }
            """)
        guard
            let result = context.objectForKeyedSubscript("renderDocument")?.call(withArguments: [markdown])?
                .toDictionary(),
            context.exception == nil, let body = result["body"] as? String,
            let images = result["images"] as? [String]
        else { throw CocoaError(.fileReadCorruptFile) }
        return MarkdownHTML(body: body, imageSources: images)
    }
}
