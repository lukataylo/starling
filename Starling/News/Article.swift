import Foundation

struct FeedSource: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let url: URL
    /// House style, fed to the model so the reader's selection shapes the voice.
    let style: String
    let symbol: String
}

struct Article: Identifiable, Hashable, Codable {
    var id: String { link.absoluteString }
    let title: String
    let link: URL
    let sourceID: String
    let summary: String
    let published: Date?
    let imageURL: URL?
    /// Full extracted body (paragraphs). Nil until loaded; RSS content:encoded may prefill it.
    var body: [String]?

    var wordCount: Int { (body ?? [summary]).joined(separator: " ").split(separator: " ").count }
}
