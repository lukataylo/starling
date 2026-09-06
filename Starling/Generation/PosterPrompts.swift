import Foundation
import CryptoKit

/// Pure-Foundation prompt builders shared by the app and the offline pre-generation harness.
/// The app looks images up by `key(prompt, mood)`, so both sides must build identical strings.
enum PosterPrompts {
    enum Kind { case headline, stat }

    static func key(_ prompt: String, mood: String) -> String {
        let h = SHA256.hash(data: Data((mood + "|" + prompt).utf8))
        return h.prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    static func coverPrompt(headline: String, summary: String) -> String {
        "Cover image for a news story: \(headline). \(summary.prefix(200))"
    }

    /// A complete poster card with the type baked in: bold gradient, minimal clean sans, infographic layout.
    static func poster(kind: Kind, big: String, line: String, subject: String, mood: String) -> String {
        let colours: String
        switch mood {
        case "calm": colours = "a smooth confident gradient from soft sage green at the top to warm sand at the bottom, gentle diffuse daylight, deep ink-green text"
        case "focused": colours = "a deep near-black to charcoal gradient with a warm signal-orange glow rising from the bottom-right, off-white text with the smaller line in orange"
        default: colours = "a bold saturated gradient from vivid orange-coral at the top to deeper burnt orange at the bottom, near-black text"
        }
        let bigLine = kind == .stat
            ? "the figure \"\(big)\" set enormous (about a third of the card width) on its own line"
            : "the headline \"\(big)\" set very large across up to three lines"
        return "Vertical 9:16 story card, confident graphic-design poster, infographic style. Background: \(colours). Typography: minimal clean geometric sans-serif, excellent layout, generous margins; top-left, \(bigLine), then directly below in a smaller regular weight the line \"\(line)\". Bottom-left: a small solid circle followed by the word \"starling\" in the same sans-serif. One duotone photographic or simplified graphic subject placed low-right and blending into the gradient, related to: \(subject). No other text, no logos, no interface elements. Spell every word exactly as given."
    }

    /// Poster prompts for the first two cards of an edition.
    static func prompts(edition: Edition, title: String, summary: String, sourceName: String, mood: String) -> [String?] {
        let subject = String(summary.prefix(160))
        let headline = edition.posterHeadline ?? edition.headline.split(separator: " ").prefix(6).joined(separator: " ")
        // Broadcaster names trip the image safety filter as trademarks; use the state summary as the line for those.
        let line = sourceName.localizedCaseInsensitiveContains("BBC") ? edition.stateSummary : sourceName
        let p0 = poster(kind: .headline, big: headline, line: line, subject: subject, mood: mood)
        var p1: String? = nil
        let rest = edition.blocks.filter { $0.type != .headline && $0.type != .dek }
        if let b = rest.first {
            if b.type == .stat, let big = b.text {
                p1 = poster(kind: .stat, big: big, line: b.caption ?? "", subject: subject, mood: mood)
            } else if let first = b.items?.first ?? b.text, !first.isEmpty {
                let words = first.split(separator: " ")
                let big = words.prefix(4).joined(separator: " ")
                let line = words.dropFirst(4).prefix(12).joined(separator: " ")
                p1 = poster(kind: .headline, big: big, line: line, subject: subject, mood: mood)
            }
        }
        return [p0, p1]
    }

    /// Illustration/diagram prompt for an image card.
    static func imageCard(_ prompt: String, mood: String) -> String { prompt }

    static func mood(for palette: PaletteName) -> String {
        [.calm, .dusk, .night, .dawn].contains(palette) ? "calm" : "focused"
    }
}
