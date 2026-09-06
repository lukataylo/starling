import Foundation

/// Minimal RSS 2.0 + Atom parser. Good enough for the big feeds.
final class RSSParser: NSObject, XMLParserDelegate {
    private let sourceID: String
    private var articles: [Article] = []
    private var inItem = false
    private var current: [String: String] = [:]
    private var currentElement = ""
    private var text = ""
    private var atomLink: String?
    private var imageURL: String?

    init(sourceID: String) { self.sourceID = sourceID }

    static func parse(data: Data, sourceID: String) -> [Article] {
        let p = RSSParser(sourceID: sourceID)
        let parser = XMLParser(data: data)
        parser.delegate = p
        parser.shouldProcessNamespaces = false
        parser.parse()
        return p.articles
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "item" || elementName == "entry" {
            inItem = true; current = [:]; atomLink = nil; imageURL = nil
        }
        guard inItem else { return }
        text = ""
        if elementName == "link", let href = attributes["href"] {
            if attributes["rel"] == nil || attributes["rel"] == "alternate" { atomLink = href }
        }
        if (elementName == "media:content" || elementName == "media:thumbnail" || elementName == "enclosure"),
           let url = attributes["url"], imageURL == nil,
           (attributes["type"] ?? "image").hasPrefix("image") || elementName != "enclosure" {
            imageURL = url
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { if inItem { text += string } }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { if inItem, let s = String(data: CDATABlock, encoding: .utf8) { text += s } }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard inItem else { return }
        if elementName == "item" || elementName == "entry" {
            inItem = false
            let linkString = (current["link"]?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? atomLink
            guard let linkString, let link = URL(string: linkString) else { return }
            let title = HTMLText.clean(current["title"] ?? "")
            let rawSummary = current["description"] ?? current["summary"] ?? ""
            let summary = HTMLText.clean(rawSummary)
            let encoded = current["content:encoded"] ?? current["content"]
            var body: [String]? = nil
            if let encoded, encoded.count > 600 {
                let paras = HTMLText.paragraphs(fromHTML: encoded)
                if paras.count >= 3 { body = paras }
            }
            let dateString = current["pubDate"] ?? current["published"] ?? current["updated"] ?? current["dc:date"]
            let published = dateString.flatMap(DateParsing.parse)
            if title.isEmpty { return }
            articles.append(Article(title: title, link: link, sourceID: sourceID, summary: summary,
                                    published: published, imageURL: imageURL.flatMap(URL.init(string:)), body: body))
            return
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { current[elementName] = (current[elementName] ?? "") + value }
    }
}

enum DateParsing {
    private static let formats: [DateFormatter] = {
        ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ"].map {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = $0; return f
        }
    }()
    private static let iso = ISO8601DateFormatter()
    static func parse(_ s: String) -> Date? {
        if let d = iso.date(from: s) { return d }
        for f in formats { if let d = f.date(from: s) { return d } }
        return nil
    }
}
