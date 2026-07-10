import Foundation

/// Shared HTML → readable markdown/text (local files and fetched pages).
enum HTMLTextExtractor {
    static func looksLikeHTML(_ data: Data) -> Bool {
        guard let head = String(data: data.prefix(800), encoding: .utf8)?.lowercased() else { return false }
        return head.contains("<html")
            || head.contains("<!doctype html")
            || head.contains("<body")
            || head.contains("<head")
    }

    static func looksLikeHTML(string: String) -> Bool {
        looksLikeHTML(Data(string.utf8))
    }

    static func toMarkdown(_ html: String, sourceLabel: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: #"(?is)<script[^>]*>.*?</script>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?is)<style[^>]*>.*?</style>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?is)<noscript[^>]*>.*?</noscript>"#, with: "", options: .regularExpression)

        var title = sourceLabel
        if let match = s.range(of: #"(?is)<title[^>]*>(.*?)</title>"#, options: .regularExpression) {
            let inner = String(s[match])
                .replacingOccurrences(of: #"(?is)</?title[^>]*>"#, with: "", options: .regularExpression)
            let decoded = decodeEntities(inner).trimmingCharacters(in: .whitespacesAndNewlines)
            if !decoded.isEmpty { title = decoded }
        }

        for level in 1...6 {
            s = s.replacingOccurrences(
                of: #"(?is)<h\#(level)[^>]*>(.*?)</h\#(level)>"#,
                with: "\n\n" + String(repeating: "#", count: level) + " $1\n\n",
                options: .regularExpression
            )
        }
        s = s.replacingOccurrences(of: #"(?is)<p[^>]*>"#, with: "\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?is)</p>"#, with: "\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?is)<br\s*/?>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?is)<li[^>]*>"#, with: "\n- ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
        s = decodeEntities(s)
        s = s.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        return "# \(title)\n\nSource: \(sourceLabel)\n\n\(s)\n"
    }

    private static func decodeEntities(_ s: String) -> String {
        var out = s
        let map = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'"
        ]
        for (k, v) in map { out = out.replacingOccurrences(of: k, with: v) }
        return out
    }
}
