import SwiftUI

/// The fixed rules. The model chooses from these vocabularies and nothing else.
enum Density: String, Codable, CaseIterable { case glance, brief, standard, longform }
enum Tone: String, Codable, CaseIterable { case brisk, plain, warm, reflective, reassuring }
enum Pace: String, Codable, CaseIterable { case single, scroll }
enum TypeScale: String, Codable, CaseIterable { case compact, regular, large, xl }
enum Typeface: String, Codable, CaseIterable { case serif, sans, rounded, mono }
enum HeadlineWeight: String, Codable, CaseIterable { case regular, semibold, black }
enum PaletteName: String, Codable, CaseIterable { case dawn, day, focus, dusk, night, calm }
enum AccentName: String, Codable, CaseIterable { case amber, coral, sage, sky, slate, plum }
enum Margins: String, Codable, CaseIterable { case tight, normal, wide }
enum EditionFormat: String, Codable, CaseIterable { case text, cards }

struct Palette {
    let background: Color
    let card: Color
    let text: Color
    let secondary: Color
    let scheme: ColorScheme
}

enum DesignGenome {
    static func palette(_ name: PaletteName) -> Palette {
        switch name {
        case .dawn: return Palette(background: Color(red: 0.99, green: 0.96, blue: 0.90), card: Color(red: 0.97, green: 0.91, blue: 0.80), text: Color(red: 0.22, green: 0.16, blue: 0.10), secondary: Color(red: 0.50, green: 0.42, blue: 0.32), scheme: .light)
        case .day: return Palette(background: .white, card: Color(white: 0.95), text: Color(white: 0.10), secondary: Color(white: 0.42), scheme: .light)
        case .focus: return Palette(background: Color(white: 0.98), card: Color(white: 0.92), text: .black, secondary: Color(white: 0.30), scheme: .light)
        case .dusk: return Palette(background: Color(red: 0.16, green: 0.14, blue: 0.15), card: Color(red: 0.23, green: 0.20, blue: 0.21), text: Color(red: 0.95, green: 0.91, blue: 0.88), secondary: Color(red: 0.72, green: 0.66, blue: 0.64), scheme: .dark)
        case .night: return Palette(background: Color(red: 0.05, green: 0.05, blue: 0.06), card: Color(red: 0.12, green: 0.11, blue: 0.12), text: Color(red: 0.82, green: 0.78, blue: 0.72), secondary: Color(red: 0.55, green: 0.52, blue: 0.48), scheme: .dark)
        case .calm: return Palette(background: Color(red: 0.93, green: 0.94, blue: 0.89), card: Color(red: 0.86, green: 0.89, blue: 0.82), text: Color(red: 0.20, green: 0.25, blue: 0.20), secondary: Color(red: 0.42, green: 0.48, blue: 0.42), scheme: .light)
        }
    }

    static func accent(_ name: AccentName, palette: PaletteName) -> Color {
        let dark = palette == .dusk || palette == .night
        switch name {
        case .amber: return dark ? Color(red: 0.95, green: 0.72, blue: 0.35) : Color(red: 0.80, green: 0.52, blue: 0.10)
        case .coral: return dark ? Color(red: 0.98, green: 0.55, blue: 0.48) : Color(red: 0.85, green: 0.35, blue: 0.30)
        case .sage: return dark ? Color(red: 0.60, green: 0.75, blue: 0.58) : Color(red: 0.35, green: 0.52, blue: 0.36)
        case .sky: return dark ? Color(red: 0.55, green: 0.75, blue: 0.95) : Color(red: 0.16, green: 0.45, blue: 0.75)
        case .slate: return dark ? Color(red: 0.70, green: 0.74, blue: 0.80) : Color(red: 0.30, green: 0.36, blue: 0.45)
        case .plum: return dark ? Color(red: 0.80, green: 0.60, blue: 0.85) : Color(red: 0.48, green: 0.25, blue: 0.55)
        }
    }

    static func design(_ t: Typeface) -> Font.Design {
        switch t {
        case .serif: return .serif
        case .sans: return .default
        case .rounded: return .rounded
        case .mono: return .monospaced
        }
    }

    /// Body / headline point sizes and line spacing per scale.
    static func metrics(_ s: TypeScale) -> (body: CGFloat, headline: CGFloat, lineSpacing: CGFloat) {
        switch s {
        case .compact: return (15, 24, 3)
        case .regular: return (17, 30, 5)
        case .large: return (21, 36, 7)
        case .xl: return (26, 44, 9)
        }
    }

    static func weight(_ w: HeadlineWeight) -> Font.Weight {
        switch w {
        case .regular: return .regular
        case .semibold: return .semibold
        case .black: return .black
        }
    }

    static func padding(_ m: Margins) -> CGFloat {
        switch m {
        case .tight: return 14
        case .normal: return 22
        case .wide: return 34
        }
    }

    /// Human-readable rules, sent as the system prompt.
    static let rules = """
    You are the generative layout engine of Starling, a news reader whose interface is never finished. For each request you rewrite ONE news article and choose its page design so that it fits this reader, right now. You return only JSON matching the schema.

    THE GENOME (you may only choose from these):
    - density: glance (≈20s read, one screen), brief (≈60s), standard (≈3 min), longform (full story, may exceed original length only by adding context the source implies)
    - tone: brisk, plain, warm, reflective, reassuring
    - pace: single (fits one phone screen, no scrolling) or scroll
    - typeScale: compact, regular, large, xl
    - typeface: serif, sans, rounded, mono
    - headlineWeight: regular, semibold, black
    - palette: dawn (warm cream + amber), day (white + ink), focus (high contrast), dusk (deep warm greys), night (near-black, dim warm text), calm (sage and sand, low contrast)
    - accent: amber, coral, sage, sky, slate, plum
    - margins: tight, normal, wide
    - format: text (one flowing page) or cards (one idea per swipeable card, each block becomes a card; suggest cards when the reader is walking, standing, or on transport, and text when they are sitting or lying down — the reader can flip this)
    - blocks: headline, dek, keyFacts (items, max 3), paragraph, pullQuote, imageCard (symbol = an SF Symbol name, caption), timeline (items, each "time — event"), takeaway, readFullPrompt

    RULES OF JUDGEMENT:
    1. The default is standard / plain / scroll / regular / sans / semibold / day / slate / normal. Every deviation must earn its place: it must make the page clearer, faster or more legible for THIS reader in THIS moment, and you must say why in `rationale` in one plain sentence the reader would accept. Never mutate for decoration.
    2. Time of day shapes both text and design. Early morning and morning: brisk tone, briefing structure (keyFacts first), dawn or day palette, sans. Midday and afternoon: plain tone, day or focus. Evening: warm or reflective tone, longer sentences allowed, dusk palette, serif is welcome. Night: reassuring tone, no alarming framing, no cliffhangers, night palette, larger type, dim accent, never coral.
    3. The reader's chosen sources shape the voice. Blend the house styles of their enabled sources, weighting the article's own source most. Do not invent facts; you may only restructure, compress, clarify and add neutral context that the article itself implies.
    4. State overrides. Walking, automotive, or stress above 0.6: glance or brief, pace single, typeScale large or xl, calm palette, keyFacts first, no pullQuote, format cards with 3–5 short blocks. Attention below 0.4: shorter blocks, a pullQuote hook, takeaway at the end. Lying down or reclined and calm: longform is allowed, serif, wide margins, reflective tone. Tired (late, low attention, slow blinks): reassuring, brief, large, night or dusk.
    5. Low-confidence signals must be ignored, not guessed at. If the state says a signal is unavailable, do not mention it.
    6. Respect the reader's stored feedback above every heuristic.
    7. The headline must stay faithful to the story. Never editorialise beyond the source's own framing. Never add a call to action other than readFullPrompt.
    8. `stateSummary` is 3–8 words describing what you noticed, e.g. "walking, evening, a little tense". `rationale` is one sentence, second person, no jargon.
    """
}
