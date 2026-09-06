import SwiftUI

/// Starling identity: warm white, ink, acid green; cobalt and deep red story tiles. Grotesk for interface, serif for editorial.
enum Identity {
    static let warmWhite = Color(red: 0.965, green: 0.957, blue: 0.933)
    static let ink = Color(red: 0.055, green: 0.055, blue: 0.055)
    static let acid = Color(red: 0.78, green: 1.0, blue: 0.0)
    static let cobalt = Color(red: 0.16, green: 0.16, blue: 1.0)
    static let red = Color(red: 0.86, green: 0.16, blue: 0.16)
    static let grey = Color(red: 0.45, green: 0.45, blue: 0.43)
    static let rule = Color.black
    static let night = Color(red: 0.04, green: 0.04, blue: 0.04)

    static func grotesk(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .default) }
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .serif) }
}

/// The whole app's look. The identity is fixed; the reader's state and the edition decide light/dark, scale and which layout family.
struct Theme {
    let paletteName: PaletteName
    let accentName: AccentName
    let scale: TypeScale
    let typeface: Typeface

    var isDark: Bool { paletteName == .night || paletteName == .dusk }
    var palette: Palette {
        isDark
        ? Palette(background: Identity.night, card: Color(white: 0.12), text: Identity.warmWhite, secondary: Color(white: 0.62), scheme: .dark)
        : Palette(background: Identity.warmWhite, card: Color.white, text: Identity.ink, secondary: Identity.grey, scheme: .light)
    }
    var accent: Color { Identity.acid }
    var design: Font.Design { typeface == .serif ? .serif : .default }
    var metrics: (body: CGFloat, headline: CGFloat, lineSpacing: CGFloat) { DesignGenome.metrics(scale) }
    var surface: Color { isDark ? Color(white: 0.12) : Color.white }
    var ink: Color { palette.text }
    var secondary: Color { palette.secondary }
    /// Story tile colours, cycling: cobalt, deep red, ink, acid.
    var tiles: [Color] { [Identity.cobalt, Identity.red, Identity.ink, Identity.acid] }
    func tileInk(_ i: Int) -> Color { i % 4 == 3 ? Identity.ink : Identity.warmWhite }

    func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: design) }
    var heavy: Font.Weight { .heavy }

    /// Compressed, poster-like reading (quick edition) vs calm literary article.
    var isQuick: Bool { scale == .large || scale == .xl }

    static func forState(_ s: UserState) -> Theme {
        let moving = s.motion == .walking || s.motion == .running || s.motion == .automotive
        let tense = s.label == .tense || s.stress > 0.6
        let lying = s.posture == .lyingDown || s.posture == .reclined
        var palette: PaletteName
        switch s.timeOfDay {
        case .earlyMorning, .morning: palette = .dawn
        case .midday, .afternoon: palette = .day
        case .evening: palette = .dusk
        case .night: palette = .night
        }
        var scale: TypeScale = .regular
        var face: Typeface = .sans
        if moving || tense || s.label == .distracted { scale = .large; face = .sans }
        else if s.label == .tired { scale = .large; face = .serif; palette = s.timeOfDay == .evening ? .dusk : .night }
        else if s.label == .calm && lying { face = .serif }
        return Theme(paletteName: palette, accentName: .sage, scale: scale, typeface: face)
    }

    static func forEdition(_ e: Edition) -> Theme {
        let quick = e.resolvedLayout == .quick
        return Theme(paletteName: e.palette, accentName: e.accent, scale: quick ? .large : e.typeScale, typeface: quick ? .sans : .serif)
    }
}

extension SignalHub {
    var theme: Theme { Theme.forState(state) }
}

/// Round icon button.
struct RoundIconButton: View {
    let symbol: String
    let theme: Theme
    var filled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(filled ? theme.palette.background : theme.ink)
                .frame(width: 40, height: 40)
                .background(filled ? theme.ink : Color.clear, in: Circle())
                .overlay(Circle().strokeBorder(theme.ink.opacity(filled ? 0 : 0.9), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
    }
}

/// The acid-green state pill: "Focused · 84% · Standing".
struct StatePill: View {
    @Environment(SignalHub.self) private var hub
    let theme: Theme
    var badge = false
    var suffix: String? = nil
    let action: () -> Void

    var body: some View {
        let s = hub.state
        Button(action: action) {
            HStack(spacing: 6) {
                Text(text(s)).font(Identity.grotesk(12, .semibold)).tracking(-0.2).lineLimit(1)
                if badge { Circle().fill(Identity.ink).frame(width: 6, height: 6) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Identity.acid, in: Capsule())
            .foregroundStyle(Identity.ink)
        }
        .buttonStyle(.plain)
    }

    func text(_ s: UserState) -> String {
        var parts = [s.label.rawValue.capitalized]
        if s.sensingEnabled && s.faceDetected { parts.append("\(Int(s.attention * 100))%") }
        if let bpm = s.bpm, s.bpmConfidence >= 0.3 { parts.append("\(Int(bpm)) bpm") }
        switch s.motion {
        case .walking: parts.append("Walking")
        case .running: parts.append("Running")
        case .automotive: parts.append("In transit")
        default:
            switch s.posture {
            case .lyingDown: parts.append("Lying down")
            case .reclined: parts.append("Reclined")
            case .flat: parts.append("On table")
            default: parts.append("Still")
            }
        }
        if let suffix { parts.append(suffix) }
        return parts.joined(separator: " · ")
    }
}

/// Small circular arrow used on tiles.
struct ArrowDot: View {
    var light = true
    var body: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(light ? Identity.ink : Identity.warmWhite)
            .frame(width: 32, height: 32)
            .background(light ? Identity.warmWhite : Identity.ink, in: Circle())
    }
}
