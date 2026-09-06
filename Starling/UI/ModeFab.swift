import SwiftUI

/// The persistent bottom-left mode button. One tap flips the level's mode and the icon changes with it.
/// Home: tiles ↔ cards. Article: short ↔ cards.
struct ModeFab: View {
    let symbol: String
    let label: String
    let theme: Theme
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 16, weight: .bold)).contentTransition(.symbolEffect(.replace))
                Text(label).font(Identity.grotesk(12, .bold)).tracking(-0.2)
            }
            .padding(.leading, 14).padding(.trailing, 16).frame(height: 48)
            .background(theme.ink, in: Capsule())
            .foregroundStyle(theme.palette.background)
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: symbol)
    }
}
