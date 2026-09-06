import SwiftUI

/// The whole app's look, derived from the reader's state (no model call) or from the edition on screen.
struct Theme {
    let paletteName: PaletteName
    let accentName: AccentName
    let scale: TypeScale
    let typeface: Typeface

    var palette: Palette { DesignGenome.palette(paletteName) }
    var accent: Color { DesignGenome.accent(accentName, palette: paletteName) }
    var design: Font.Design { DesignGenome.design(typeface) }
    var isDark: Bool { palette.scheme == .dark }
    var metrics: (body: CGFloat, headline: CGFloat, lineSpacing: CGFloat) { DesignGenome.metrics(scale) }
    /// Surface for pills, dock buttons, tiles' neutral state.
    var surface: Color { isDark ? Color.white.opacity(0.08) : Color.white }
    var ink: Color { palette.text }
    var secondary: Color { palette.secondary }

    /// Pastel tile colours, tinted for dark palettes.
    var tiles: [Color] {
        if isDark {
            return [Color(red: 0.24, green: 0.21, blue: 0.16), Color(red: 0.16, green: 0.20, blue: 0.26), Color(red: 0.23, green: 0.18, blue: 0.26), Color(red: 0.27, green: 0.18, blue: 0.17), Color(red: 0.17, green: 0.23, blue: 0.18)]
        }
        return [Color(red: 0.96, green: 0.90, blue: 0.80), Color(red: 0.84, green: 0.89, blue: 0.93), Color(red: 0.89, green: 0.84, blue: 0.92), Color(red: 0.95, green: 0.83, blue: 0.80), Color(red: 0.81, green: 0.85, blue: 0.77)]
    }

    func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: design) }
    var heavy: Font.Weight { typeface == .rounded ? .heavy : .bold }

    static func forState(_ s: UserState) -> Theme {
        let moving = s.motion == .walking || s.motion == .running || s.motion == .automotive
        let tense = s.label == .tense || s.stress > 0.6
        let lying = s.posture == .lyingDown || s.posture == .reclined
        var palette: PaletteName
        var accent: AccentName
        switch s.timeOfDay {
        case .earlyMorning, .morning: palette = .dawn; accent = .amber
        case .midday, .afternoon: palette = .day; accent = .sky
        case .evening: palette = .dusk; accent = .coral
        case .night: palette = .night; accent = .slate
        }
        var scale: TypeScale = .regular
        var face: Typeface = .rounded
        if moving || tense { palette = .calm; accent = .sage; scale = .large; face = .rounded }
        else if s.label == .focused { palette = s.timeOfDay == .night ? .night : .focus; accent = .slate; face = .sans }
        else if s.label == .tired { palette = s.timeOfDay == .evening ? .dusk : .night; accent = .amber; scale = .large; face = .serif }
        else if s.label == .calm && lying { face = .serif }
        else if s.label == .distracted { scale = .large; accent = .coral }
        return Theme(paletteName: palette, accentName: accent, scale: scale, typeface: face)
    }

    static func forEdition(_ e: Edition) -> Theme {
        Theme(paletteName: e.palette, accentName: e.accent, scale: e.typeScale, typeface: e.typeface)
    }
}

extension SignalHub {
    var theme: Theme { Theme.forState(state) }
}

/// Round icon button, D style.
struct RoundIconButton: View {
    let symbol: String
    let theme: Theme
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.ink)
                .frame(width: 44, height: 44)
                .background(theme.surface, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// The state pill: icon in a tinted circle, label, sub-line. Tapping opens the signal readout.
struct StatePill: View {
    @Environment(SignalHub.self) private var hub
    let theme: Theme
    let action: () -> Void

    var body: some View {
        let s = hub.state
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: s.label.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .frame(width: 28, height: 28)
                    .background(theme.accent.opacity(theme.isDark ? 0.45 : 0.35), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.label.rawValue.capitalized).font(theme.font(13, weight: .heavy))
                    Text(subline(s)).font(theme.font(10, weight: .semibold)).foregroundStyle(theme.secondary)
                }
            }
            .padding(.leading, 8).padding(.trailing, 12).padding(.vertical, 8)
            .background(theme.surface, in: Capsule())
            .foregroundStyle(theme.ink)
        }
        .buttonStyle(.plain)
    }

    func subline(_ s: UserState) -> String {
        var parts = [s.timeOfDay.label]
        switch s.motion {
        case .walking: parts.append("walking")
        case .running: parts.append("running")
        case .automotive: parts.append("in transit")
        default:
            switch s.posture {
            case .lyingDown: parts.append("lying down")
            case .reclined: parts.append("reclined")
            default: parts.append("still")
            }
        }
        if let bpm = s.bpm, s.bpmConfidence >= 0.4 { parts.append("\(Int(bpm)) bpm") }
        return parts.joined(separator: " · ")
    }
}
