import Foundation

enum FeedCatalog {
    static let all: [FeedSource] = [
        FeedSource(id: "economist", name: "The Economist", url: URL(string: "https://www.economist.com/latest/rss.xml")!,
                   style: "authoritative, witty, economically literate, argues a position in plain prose", symbol: "building.2"),
        FeedSource(id: "bbc", name: "BBC News", url: URL(string: "https://feeds.bbci.co.uk/news/rss.xml")!,
                   style: "neutral, short declarative sentences, facts before interpretation", symbol: "globe.europe.africa"),
        FeedSource(id: "guardian", name: "The Guardian", url: URL(string: "https://www.theguardian.com/uk/rss")!,
                   style: "contextual, human angle, progressive framing, longer sentences", symbol: "newspaper"),
        FeedSource(id: "ft", name: "Financial Times", url: URL(string: "https://www.ft.com/rss/home")!,
                   style: "analytical, numbers-led, markets and consequences, dry wit", symbol: "chart.line.uptrend.xyaxis"),
        FeedSource(id: "verge", name: "The Verge", url: URL(string: "https://www.theverge.com/rss/index.xml")!,
                   style: "conversational, product-minded, opinionated, first person allowed", symbol: "iphone"),
        FeedSource(id: "nyt", name: "New York Times", url: URL(string: "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml")!,
                   style: "measured, narrative lede, explanatory, US perspective", symbol: "building.columns"),
        FeedSource(id: "ars", name: "Ars Technica", url: URL(string: "https://feeds.arstechnica.com/arstechnica/index")!,
                   style: "technical, precise, skeptical of hype, explains mechanisms", symbol: "cpu"),
        FeedSource(id: "hn", name: "Hacker News", url: URL(string: "https://news.ycombinator.com/rss")!,
                   style: "terse, engineering-minded, skeptical, links over prose", symbol: "terminal"),
        FeedSource(id: "wired", name: "Wired", url: URL(string: "https://www.wired.com/feed/rss")!,
                   style: "vivid, future-facing, culture and tech, a little breathless", symbol: "bolt"),
    ]

    static func source(_ id: String) -> FeedSource? { all.first { $0.id == id } }
    static let defaultEnabled: Set<String> = ["economist", "verge", "ars"]
}
