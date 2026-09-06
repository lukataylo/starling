import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SignalHub.self) private var hub
    @Environment(Generator.self) private var generator
    @Environment(OvernightPregen.self) private var overnight
    @Environment(FeedStore.self) private var feeds
    @Environment(ImageGenerator.self) private var imageGen
    @AppStorage("apiKeyOverride") private var keyOverride = ""
    @AppStorage("modelOverride") private var modelOverride = ""
    @AppStorage("elevenAgentID") private var elevenAgentID = ""
    @AppStorage("readerName") private var readerName = ""
    @AppStorage("devMode") private var devMode = true
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue
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
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { a in Text(a.label).tag(a.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: appearance) { _, raw in hub.appearance = Appearance(rawValue: raw) ?? .system }
                    Text("Dark turns every skin into its night version; Light keeps the page pale even in the evening.").font(.caption).foregroundStyle(.secondary)
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
                    TextField("Your name (the newsreader greets you)", text: $readerName)
                    TextField("Agent ID (blank = bundled)", text: $elevenAgentID).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Text(Newsreader.apiKey == nil ? "No ElevenLabs key bundled." : "ElevenLabs key bundled. Bundled agent: \((Bundle.main.infoDictionary?["ELEVENLABS_AGENT_ID"] as? String ?? "none").prefix(12))…").font(.caption).foregroundStyle(.secondary)
                } header: { Text("Newsreader (ElevenLabs)") } footer: { Text("Tap the phone in a story to call the newsreader. It only knows the story it was handed and asks before changing what's on screen.") }
                Section {
                    Toggle("Pre-generate overnight", isOn: Binding(get: { overnight.isEnabled }, set: { overnight.isEnabled = $0 }))
                    Button(overnight.isRunning ? "Running…" : "Run now") {
                        Task { await overnight.run(feeds: feeds, generator: generator, images: imageGen, hub: hub, perSource: 2, postersFor: 2) }
                    }.disabled(overnight.isRunning)
                    if overnight.isRunning { Text(overnight.progress).font(.caption).foregroundStyle(.secondary) }
                    if let d = overnight.lastRun {
                        Text("Last run \(d.formatted(date: .abbreviated, time: .shortened)). \(overnight.lastSummary)").font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("Overnight pre-generation") } footer: {
                    Text("While charging on wifi, Starling pre-renders the top stories from each of your sources for the states you're most often in (\(overnight.commonStates(hub: hub).map(\.name).joined(separator: ", "))), plus their posters, so the morning feed opens instantly.")
                }
                Section {
                    NavigationLink("State readout") { SignalSheet(theme: hub.theme) }
                    NavigationLink("Live signals") { SensorDebugView() }
                    Toggle("Developer mode", isOn: $devMode)
                } header: { Text("Sensing") } footer: { Text("With developer mode on, tapping the state pill opens the raw telemetry readout from anywhere.") }
                Section("The interface is never finished") {
                    NavigationLink("Layout rules per state") { LayoutRulesView() }
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
