import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SignalHub.self) private var hub
    @Environment(Generator.self) private var generator
    @AppStorage("apiKeyOverride") private var keyOverride = ""
    @AppStorage("modelOverride") private var modelOverride = ""
    @State private var useClockOverride = false
    @State private var clock = Date()

    var body: some View {
        @Bindable var hub = hub
        NavigationStack {
            Form {
                Section("Sensing") {
                    Toggle("Use camera, motion and heart rate", isOn: $hub.isSensingEnabled)
                    Text("Adaptation is a proposal. Turn this off and Starling only uses the time of day and how you're holding the phone.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Demo: pretend it's another time") {
                    Toggle("Override clock", isOn: $useClockOverride)
                        .onChange(of: useClockOverride) { _, on in hub.clockOverride = on ? clock : nil }
                    if useClockOverride {
                        DatePicker("Time", selection: $clock, displayedComponents: .hourAndMinute)
                            .onChange(of: clock) { _, d in hub.clockOverride = d }
                    }
                }
                Section("OpenAI API key") {
                    SecureField("sk-…", text: $keyOverride)
                    Text(bundledKeyStatus).font(.caption).foregroundStyle(.secondary)
                    TextField("Model (blank = \(LLMClient.defaultModel))", text: $modelOverride)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                }
                Section {
                    NavigationLink("Live signals") { SensorDebugView() }
                }
                Section {
                    Button("Clear generated editions") { generator.clearCache() }
                    Button("Forget reader feedback", role: .destructive) { generator.feedback = [] }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if let c = hub.clockOverride { useClockOverride = true; clock = c } }
        }
    }

    private var bundledKeyStatus: String {
        let bundled = (Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String) ?? ""
        return bundled.isEmpty ? "No key bundled from Secrets.xcconfig; enter one above." : "A key is bundled from Secrets.xcconfig; leave blank to use it."
    }
}
