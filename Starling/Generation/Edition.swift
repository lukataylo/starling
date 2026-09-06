import Foundation

struct Edition: Codable, Hashable, Identifiable {
    var id: String { stateSummary + rationale + String(blocks.count) }
    let stateSummary: String
    let rationale: String
    var posterHeadline: String? = nil
    let density: Density
    let tone: Tone
    let pace: Pace
    let typeScale: TypeScale
    let typeface: Typeface
    let headlineWeight: HeadlineWeight
    let palette: PaletteName
    let accent: AccentName
    let margins: Margins
    let format: EditionFormat
    let estimatedReadSeconds: Int
    let blocks: [Block]

    struct Block: Codable, Hashable {
        let type: Kind
        let text: String?
        let items: [String]?
        let symbol: String?
        let caption: String?
        var imagePrompt: String? = nil
        enum Kind: String, Codable { case headline, dek, keyFacts, paragraph, pullQuote, imageCard, stat, timeline, takeaway, readFullPrompt }
    }

    var headline: String { blocks.first { $0.type == .headline }?.text ?? "" }
}

enum EditionSchema {
    private static func e(_ values: [String]) -> [String: Any] { ["type": "string", "enum": values] }
    static let json: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["stateSummary", "rationale", "posterHeadline", "density", "tone", "pace", "typeScale", "typeface", "headlineWeight", "palette", "accent", "margins", "format", "estimatedReadSeconds", "blocks"],
        "properties": [
            "stateSummary": ["type": "string"],
            "rationale": ["type": "string"],
            "posterHeadline": ["type": "string"],
            "density": e(Density.allCases.map(\.rawValue)),
            "tone": e(Tone.allCases.map(\.rawValue)),
            "pace": e(Pace.allCases.map(\.rawValue)),
            "typeScale": e(TypeScale.allCases.map(\.rawValue)),
            "typeface": e(Typeface.allCases.map(\.rawValue)),
            "headlineWeight": e(HeadlineWeight.allCases.map(\.rawValue)),
            "palette": e(PaletteName.allCases.map(\.rawValue)),
            "accent": e(AccentName.allCases.map(\.rawValue)),
            "margins": e(Margins.allCases.map(\.rawValue)),
            "format": e(EditionFormat.allCases.map(\.rawValue)),
            "estimatedReadSeconds": ["type": "integer"],
            "blocks": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["type", "text", "items", "symbol", "caption", "imagePrompt"],
                    "properties": [
                        "type": e(["headline", "dek", "keyFacts", "paragraph", "pullQuote", "imageCard", "stat", "timeline", "takeaway", "readFullPrompt"]),
                        "text": ["type": ["string", "null"]],
                        "items": ["type": ["array", "null"], "items": ["type": "string"]],
                        "symbol": ["type": ["string", "null"]],
                        "caption": ["type": ["string", "null"]],
                        "imagePrompt": ["type": ["string", "null"]],
                    ],
                ],
            ],
        ],
    ]
}
