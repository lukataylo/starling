import Foundation

enum HTMLText {
    static func clean(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = decodeEntities(s)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ s: String) -> String {
        var out = s
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
                   "&#8217;": "’", "&#8216;": "‘", "&#8220;": "“", "&#8221;": "”", "&#8211;": "–", "&#8212;": "—", "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”", "&ndash;": "–", "&mdash;": "—", "&hellip;": "…", "&#8230;": "…", "&#x27;": "'", "&#x2019;": "’"]
        for (k, v) in map { out = out.replacingOccurrences(of: k, with: v) }
        // numeric entities
        if let re = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let ns = out as NSString
            var result = ""
            var last = 0
            for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                if let code = Int(ns.substring(with: m.range(at: 1))), let scalar = Unicode.Scalar(code) { result.append(Character(scalar)) }
                last = m.range.location + m.range.length
            }
            result += ns.substring(from: last)
            out = result
        }
        return out
    }

    /// Pull readable paragraphs out of an HTML document: every <p> with enough words,
    /// skipping obvious boilerplate.
    static func paragraphs(fromHTML html: String) -> [String] {
        var doc = html
        for tag in ["script", "style", "nav", "header", "footer", "aside", "form", "noscript", "figure", "svg"] {
            doc = doc.replacingOccurrences(of: "(?is)<\(tag)\\b[^>]*>.*?</\(tag)>", with: " ", options: .regularExpression)
        }
        guard let re = try? NSRegularExpression(pattern: "(?is)<p\\b[^>]*>(.*?)</p>") else { return [] }
        let ns = doc as NSString
        var paras: [String] = []
        for m in re.matches(in: doc, range: NSRange(location: 0, length: ns.length)) {
            let inner = ns.substring(with: m.range(at: 1))
            let t = clean(inner)
            let words = t.split(separator: " ").count
            guard words >= 8 else { continue }
            let lower = t.lowercased()
            if lower.contains("cookie") && lower.contains("consent") { continue }
            if lower.hasPrefix("sign up") || lower.hasPrefix("subscribe") || lower.contains("all rights reserved") { continue }
            paras.append(t)
        }
        // Cap to keep prompts small: ~1800 words.
        var total = 0
        var out: [String] = []
        for p in paras { total += p.split(separator: " ").count; if total > 1800 { break }; out.append(p) }
        return out
    }
}

enum ArticleExtractor {
    static func fetchBody(for article: Article) async -> [String] {
        var req = URLRequest(url: article.link)
        req.timeoutInterval = 12
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return [] }
        return HTMLText.paragraphs(fromHTML: html)
    }
}
