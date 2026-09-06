import Foundation
import Observation
import Combine
import ElevenLabs

/// The voice layer. Stage 1: author a spoken narrative from the article (ours, OpenAI). Stage 2: call the ElevenLabs
/// newsreader agent with that narrative injected as dynamic variables. Strict grounding; confirm-before-change via client tools.
@Observable @MainActor
final class Newsreader {
    enum CallState: Equatable { case idle, authoring, connecting, live, ended, failed(String) }

    private(set) var narratives: [String: String] = [:]
    private var authoring: Set<String> = []
    private(set) var callState: CallState = .idle
    private(set) var transcript: [(role: String, text: String)] = []
    private(set) var agentSpeaking = false
    private(set) var isMuted = false
    private(set) var proposal: (kind: String, reason: String)? = nil
    var onApplyVersion: ((String) -> Void)?
    private var conversation: Conversation?
    private var cancellables: Set<AnyCancellable> = []

    static var agentID: String {
        UserDefaults.standard.string(forKey: "elevenAgentID").flatMap { $0.isEmpty ? nil : $0 } ?? (Bundle.main.infoDictionary?["ELEVENLABS_AGENT_ID"] as? String ?? "")
    }
    static var apiKey: String? {
        let k = (Bundle.main.infoDictionary?["ELEVENLABS_API_KEY"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        return k.isEmpty ? nil : k
    }

    // MARK: Stage 1 — story authoring (prefetched the moment an article opens)
    func author(article: Article, sources: [FeedSource]) {
        guard narratives[article.id] == nil, !authoring.contains(article.id), let key = LLMClient.apiKey else { return }
        authoring.insert(article.id)
        Task {
            defer { authoring.remove(article.id) }
            let styles = sources.map { "\($0.name): \($0.style)" }.joined(separator: "; ")
            let system = "You write spoken news narratives for a single newsreader voice. Rewrite the article as continuous prose meant to be heard: broadcast-anchor cadence, scene-setting, connective phrasing, 220–320 words, no headings, no bullet points, no numbers spelled as digits unless they are the point. Blend the house styles of the reader's sources (\(styles)), weighting the article's own source most. Use only facts that are in the article; never add context, speculation or names that are not in it. End with one plain sentence on what to watch next, only if the article says so."
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            req.httpMethod = "POST"; req.timeoutInterval = 60
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let body: [String: Any] = ["model": LLMClient.model, "reasoning_effort": "none",
                "messages": [["role": "system", "content": system], ["role": "user", "content": "TITLE: \(article.title)\nSOURCE: \(FeedCatalog.source(article.sourceID)?.name ?? "")\n\n" + (article.body ?? [article.summary]).joined(separator: "\n\n")]]]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = ((json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String else { return }
            narratives[article.id] = text
        }
    }

    // MARK: Stage 2 — the call
    func startCall(article: Article, state: UserState, currentVersion: String, sources: [FeedSource]) async {
        guard callState != .live, callState != .connecting else { return }
        transcript = []; proposal = nil
        let agent = Self.agentID
        guard !agent.isEmpty else { callState = .failed("No newsreader agent configured. Add the agent ID in Settings."); return }
        // Make sure the narrative exists; author now if the prefetch hasn't landed.
        if narratives[article.id] == nil {
            callState = .authoring
            author(article: article, sources: sources)
            for _ in 0..<60 { if narratives[article.id] != nil { break }; try? await Task.sleep(for: .milliseconds(500)) }
        }
        guard let narrative = narratives[article.id] else { callState = .failed("Couldn't author the story for voice."); return }
        callState = .connecting
        let name = (UserDefaults.standard.string(forKey: "readerName") ?? "").trimmingCharacters(in: .whitespaces)
        let vars: [String: String] = [
            "listener_name": name.isEmpty ? "there" : name,
            "headline": article.title,
            "source": FeedCatalog.source(article.sourceID)?.name ?? "",
            "state_summary": "\(state.label.rawValue), \(state.timeOfDay.label), \(state.motion.rawValue)",
            "current_version": currentVersion,
            "narrative": narrative,
        ]
        var config = ConversationConfig()
        config.dynamicVariables = vars
        config.agentOverrides = AgentOverrides(firstMessage: "")
        do {
            let conv: Conversation
            if let key = Self.apiKey, let token = try? await Self.conversationToken(agentID: agent, apiKey: key) {
                conv = try await ElevenLabs.startConversation(conversationToken: token, config: config)
            } else {
                conv = try await ElevenLabs.startConversation(agentId: agent, config: config)
            }
            conversation = conv
            observe(conv)
            callState = .live
            try? await conv.setMuted(false)
        } catch {
            callState = .failed(error.localizedDescription)
        }
    }

    func endCall() async {
        await conversation?.endConversation()
        conversation = nil
        cancellables.removeAll()
        callState = .ended
    }

    func toggleMute() async { try? await conversation?.toggleMute() }
    func interrupt() async { try? await conversation?.interruptAgent() }

    /// Mid-call: the reader moved to another story; inject it as the new current article (dynamic override, not the knowledge base).
    func moveTo(article: Article, currentVersion: String) async {
        guard let n = narratives[article.id] else { return }
        try? await conversation?.updateContext("The reader has moved to a new story. Headline: \(article.title). Version on screen: \(currentVersion). NARRATIVE (your only knowledge now): \(n)")
    }

    private func observe(_ conv: Conversation) {
        cancellables.removeAll()
        conv.$messages.receive(on: DispatchQueue.main).sink { [weak self] msgs in
            self?.transcript = msgs.map { (role: $0.role == .agent ? "newsreader" : "you", text: $0.content) }
        }.store(in: &cancellables)
        conv.$agentState.receive(on: DispatchQueue.main).sink { [weak self] s in self?.agentSpeaking = (s == .speaking) }.store(in: &cancellables)
        conv.$isMuted.receive(on: DispatchQueue.main).sink { [weak self] m in self?.isMuted = m }.store(in: &cancellables)
        conv.$state.receive(on: DispatchQueue.main).sink { [weak self] s in
            switch s {
            case .ended: self?.callState = .ended
            case .error(let e): self?.callState = .failed(e.localizedDescription)
            default: break
            }
        }.store(in: &cancellables)
        conv.$pendingToolCalls.receive(on: DispatchQueue.main).sink { [weak self] calls in
            guard let self else { return }
            for call in calls {
                let params = (try? call.getParameters()) ?? [:]
                let kind = (params["kind"] as? String ?? "short").lowercased()
                switch call.toolName {
                case "propose_version":
                    proposal = (kind, params["reason"] as? String ?? "")
                    Task { try? await conv.sendToolResult(for: call.toolCallId, result: "Proposed \(kind) to the reader on screen. Wait for their spoken yes before applying.") ; conv.markToolCallCompleted(call.toolCallId) }
                case "apply_version":
                    proposal = nil
                    onApplyVersion?(kind)
                    Task { try? await conv.sendToolResult(for: call.toolCallId, result: "Switched the screen to \(kind)."); conv.markToolCallCompleted(call.toolCallId) }
                default:
                    Task { try? await conv.sendToolResult(for: call.toolCallId, result: "Unknown tool", isError: true); conv.markToolCallCompleted(call.toolCallId) }
                }
            }
        }.store(in: &cancellables)
    }

    private static func conversationToken(agentID: String, apiKey: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/convai/conversation/token?agent_id=\(agentID)")!)
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let token = json["token"] as? String else {
            throw NSError(domain: "eleven", code: 1, userInfo: [NSLocalizedDescriptionKey: "token"])
        }
        return token
    }
}
