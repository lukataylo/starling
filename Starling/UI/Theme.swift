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

/// The reader's appearance choice, persisted under UserDefaults key "appearance".
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let key = "appearance"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    /// The persisted choice (defaults to `.system`).
    static var stored: Appearance { Appearance(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system }
    static var systemIsDark: Bool { UITraitCollection.current.userInterfaceStyle == .dark }
}

/// The whole app's look. The identity is fixed; the reader's state and the edition decide light/dark, scale and which layout family.
struct Theme {
    let paletteName: PaletteName
    let accentName: AccentName
    let scale: TypeScale
    let typeface: Typeface
    /// Appearance override; defaults to whatever is persisted so ad-hoc `Theme(...)` values follow the setting too.
    var appearance: Appearance = .stored
    /// Whether the system trait collection is dark (only consulted when `appearance == .system`).
    var systemDark: Bool = Appearance.systemIsDark

    var isDark: Bool { palette.scheme == .dark }

    /// The palette name after the appearance choice is applied: dark forces light skins to their dark counterparts,
    /// light forces dark skins to day, system follows the trait collection (dark traits behave like `.dark`).
    private var forcesDark: Bool { appearance == .dark || (appearance == .system && systemDark) }
    private var forcesLight: Bool { appearance == .light }

    var resolvedPaletteName: PaletteName {
        if forcesDark {
            switch paletteName {
            case .day, .focus: return .night
            case .dawn: return .dusk
            case .calm, .dusk, .night: return paletteName
            }
        }
        if forcesLight {
            switch paletteName {
            case .dusk, .night: return .day
            default: return paletteName
            }
        }
        return paletteName
    }

    private var darkSage: Palette {
        Palette(background: Color(red: 0.09, green: 0.12, blue: 0.09), card: Color(red: 0.15, green: 0.19, blue: 0.15), text: Color(red: 0.90, green: 0.93, blue: 0.87), secondary: Color(red: 0.62, green: 0.68, blue: 0.60), scheme: .dark)
    }

    /// Six skins, one per genome palette, deliberately far apart so a regeneration for another mood is visible at a glance.
    var palette: Palette {
        switch resolvedPaletteName {
        case .day:   return Palette(background: Identity.warmWhite, card: .white, text: Identity.ink, secondary: Identity.grey, scheme: .light)
        case .focus: return Palette(background: .white, card: Color(white: 0.94), text: .black, secondary: Color(white: 0.35), scheme: .light)
        case .dawn:  return Palette(background: Color(red: 0.96, green: 0.91, blue: 0.80), card: Color(red: 0.99, green: 0.96, blue: 0.90), text: Color(red: 0.20, green: 0.13, blue: 0.06), secondary: Color(red: 0.50, green: 0.40, blue: 0.28), scheme: .light)
        case .calm:
            if forcesDark { return darkSage }
            return Palette(background: Color(red: 0.84, green: 0.88, blue: 0.80), card: Color(red: 0.92, green: 0.94, blue: 0.89), text: Color(red: 0.10, green: 0.18, blue: 0.12), secondary: Color(red: 0.33, green: 0.42, blue: 0.34), scheme: .light)
        case .dusk:  return Palette(background: Color(red: 0.11, green: 0.09, blue: 0.09), card: Color(red: 0.18, green: 0.15, blue: 0.15), text: Color(red: 0.96, green: 0.92, blue: 0.86), secondary: Color(red: 0.70, green: 0.63, blue: 0.58), scheme: .dark)
        case .night: return Palette(background: Identity.night, card: Color(white: 0.12), text: Identity.warmWhite, secondary: Color(white: 0.62), scheme: .dark)
        }
    }
    var accent: Color {
        switch resolvedPaletteName {
        case .dawn: return Color(red: 0.85, green: 0.55, blue: 0.10)
        case .calm: return isDark ? Color(red: 0.55, green: 0.75, blue: 0.58) : Color(red: 0.25, green: 0.45, blue: 0.30)
        case .dusk: return Color(red: 0.98, green: 0.55, blue: 0.48)
        default: return Identity.acid
        }
    }
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
        let quick = [.quick, .poster, .split, .zine].contains(e.resolvedLayout)
        return Theme(paletteName: e.palette, accentName: e.accent, scale: quick ? .large : e.typeScale, typeface: e.typeface == .serif ? .serif : .sans)
    }
}

extension SignalHub {
    var theme: Theme {
        var t = Theme.forState(state)
        t.appearance = appearance
        t.systemDark = systemIsDark
        return t
    }
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
                .contentShape(Circle())
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

    @AppStorage("devMode") private var devMode = false

    var body: some View {
        let s = hub.state
        Button(action: { if devMode { action() } }) {
            HStack(spacing: 6) {
                Text(text(s)).font(Identity.grotesk(12, .semibold)).tracking(-0.2).lineLimit(1)
                if badge { Circle().fill(Identity.ink).frame(width: 6, height: 6) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Identity.acid, in: Capsule())
            .foregroundStyle(Identity.ink)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(devMode)
    }

    func text(_ s: UserState) -> String {
        var parts: [String] = []
        if s.sensingEnabled && hub.cameraSupported {
            if !s.faceDetected { parts.append("Away") }
            else { parts.append(s.attention >= 0.5 ? "Looking" : "Not looking") }
        }
        switch s.label {
        case .calm: parts.append("Calm")
        case .tense: parts.append("Tense")
        case .tired: parts.append("Tired")
        case .focused, .distracted: if parts.isEmpty { parts.append(s.label == .focused ? "Focused" : "Distracted") }
        }
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
