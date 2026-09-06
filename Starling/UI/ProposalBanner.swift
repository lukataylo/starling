import SwiftUI

/// One quiet button at the bottom. Everything about the adaptation lives behind it.
struct ProposalButton: View {
    let edition: Edition
    let updateReady: Bool
    let action: () -> Void

    var body: some View {
        let palette = DesignGenome.palette(edition.palette)
        let accent = DesignGenome.accent(edition.accent, palette: edition.palette)
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(accent)
                Text(edition.stateSummary.prefix(1).uppercased() + edition.stateSummary.dropFirst())
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if updateReady {
                    Circle().fill(accent).frame(width: 7, height: 7)
                    Text("new version").font(.caption2).foregroundStyle(palette.secondary)
                }
                Image(systemName: "chevron.up").font(.caption2).foregroundStyle(palette.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(palette.card.opacity(0.92), in: Capsule())
            .overlay(Capsule().strokeBorder(palette.secondary.opacity(0.15)))
            .foregroundStyle(palette.text)
            .environment(\.colorScheme, palette.scheme)
        }
        .buttonStyle(.plain)
    }
}

/// The sheet behind the button: why this version, format, keep / not me, pending state change.
struct ProposalSheet: View {
    let edition: Edition
    @Binding var format: EditionFormat
    let pending: UserState?
    let pendingReady: Bool
    let onSwitch: () -> Void
    let onDismissPending: () -> Void
    let onReadFull: () -> Void
    let onKeep: () -> Void
    let onNotMe: () -> Void
    let onWhy: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let palette = DesignGenome.palette(edition.palette)
        let accent = DesignGenome.accent(edition.accent, palette: edition.palette)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(accent)
                Text(edition.stateSummary.prefix(1).uppercased() + edition.stateSummary.dropFirst()).font(.headline)
                Spacer()
                Text("~\(max(5, edition.estimatedReadSeconds))s read").font(.caption).foregroundStyle(palette.secondary)
            }
            Text(edition.rationale).font(.subheadline).foregroundStyle(palette.secondary)
            Text("\(edition.density.rawValue) · \(edition.tone.rawValue) · \(edition.typeface.rawValue) \(edition.typeScale.rawValue) · \(edition.palette.rawValue)")
                .font(.caption2).foregroundStyle(palette.secondary)

            if let p = pending {
                HStack(spacing: 10) {
                    Image(systemName: p.label.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You seem \(p.label.rawValue) now\(p.motion == .walking ? ", walking" : "")").font(.subheadline.weight(.semibold))
                        Text(pendingReady ? "A version for this moment is ready." : "Preparing a version for this moment…").font(.caption).foregroundStyle(palette.secondary)
                    }
                    Spacer()
                    Button("Switch") { onSwitch(); dismiss() }.disabled(!pendingReady).buttonStyle(.borderedProminent).tint(accent)
                    Button { onDismissPending() } label: { Image(systemName: "xmark") }.buttonStyle(.bordered)
                }
                .padding(12)
                .background(palette.background, in: RoundedRectangle(cornerRadius: 12))
            }

            Picker("Format", selection: $format) {
                Label("Cards", systemImage: "rectangle.on.rectangle").tag(EditionFormat.cards)
                Label("Text", systemImage: "text.alignleft").tag(EditionFormat.text)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Button { onKeep(); dismiss() } label: { Label("Keep this", systemImage: "checkmark") }
                Button { dismiss(); onNotMe() } label: { Label("Not how I feel", systemImage: "hand.raised") }
            }
            .buttonStyle(.bordered).tint(accent)
            HStack(spacing: 10) {
                Button { dismiss(); onReadFull() } label: { Label("Read the full story", systemImage: "text.book.closed") }
                Button { dismiss(); onWhy() } label: { Label("What it sensed", systemImage: "waveform.path.ecg") }
            }
            .buttonStyle(.bordered).tint(palette.secondary)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card)
        .foregroundStyle(palette.text)
        .environment(\.colorScheme, palette.scheme)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
