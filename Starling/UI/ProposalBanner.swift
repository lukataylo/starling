import SwiftUI

/// Adaptation is a proposal, not a trap. Lives in a collapsible tray at the bottom of the reader.
struct ProposalBanner: View {
    let edition: Edition
    @Binding var expanded: Bool
    @Binding var format: EditionFormat
    let onReadFull: () -> Void
    let onKeep: () -> Void
    let onNotMe: () -> Void
    let onWhy: () -> Void

    var body: some View {
        let palette = DesignGenome.palette(edition.palette)
        let accent = DesignGenome.accent(edition.accent, palette: edition.palette)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(accent)
                    Text(edition.stateSummary.prefix(1).uppercased() + edition.stateSummary.dropFirst())
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("~\(max(5, edition.estimatedReadSeconds))s").font(.caption2).foregroundStyle(palette.secondary)
                    Image(systemName: expanded ? "chevron.down" : "chevron.up").font(.caption2).foregroundStyle(palette.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                Text(edition.rationale).font(.caption).foregroundStyle(palette.secondary)
                HStack(spacing: 8) {
                    Picker("Format", selection: $format) {
                        Label("Cards", systemImage: "rectangle.on.rectangle").tag(EditionFormat.cards)
                        Label("Text", systemImage: "text.alignleft").tag(EditionFormat.text)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    Spacer()
                    Button("Keep", action: onKeep)
                    Button("Not me", action: onNotMe)
                    Button(action: onWhy) { Image(systemName: "info.circle") }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.mini)
                .tint(accent)
            }
        }
        .padding(12)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(palette.text)
        .environment(\.colorScheme, palette.scheme)
    }
}
