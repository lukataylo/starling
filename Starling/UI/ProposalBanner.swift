import SwiftUI

/// Adaptation is a proposal, not a trap.
struct ProposalBanner: View {
    let edition: Edition
    let onReadFull: () -> Void
    let onKeep: () -> Void
    let onNotMe: () -> Void
    let onWhy: () -> Void

    var body: some View {
        let palette = DesignGenome.palette(edition.palette)
        let accent = DesignGenome.accent(edition.accent, palette: edition.palette)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(accent)
                Text(edition.stateSummary.prefix(1).uppercased() + edition.stateSummary.dropFirst())
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("~\(max(5, edition.estimatedReadSeconds))s").font(.caption2).foregroundStyle(palette.secondary)
            }
            Text(edition.rationale).font(.caption).foregroundStyle(palette.secondary)
            HStack(spacing: 8) {
                Button("Read full", action: onReadFull)
                Button("Keep this", action: onKeep)
                Button("Not how I feel", action: onNotMe)
                Spacer()
                Button(action: onWhy) { Image(systemName: "info.circle") }
            }
            .font(.caption.weight(.medium))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.mini)
            .tint(accent)
        }
        .padding(12)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(palette.text)
        .environment(\.colorScheme, palette.scheme)
    }
}
