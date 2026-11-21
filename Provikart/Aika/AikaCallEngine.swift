//
//  AikaCallEngine.swift
//  Provikart
//
//  Hlasový hovor s AIKA přes oficiální ElevenLabs Swift SDK (WebRTC / LiveKit):
//   1. server (aika/api/session.php) vydá krátkodobý conversation token + dynamické proměnné,
//   2. SDK spustí hovor s agentem (poslech + hlas řeší ElevenLabs, mozek je GPT na serveru),
//   3. každý client tool agenta se přepošle na aika/api/tool.php a `output` se vrátí agentovi.
//  Stav, hlasitost a přepis publikuje pro SwiftUI.
//

import SwiftUI
import Combine
import AVFoundation
import ElevenLabs
import LiveKit

struct AikaTranscriptLine: Identifiable, Equatable {
    enum Role: String { case user, assistant }
    let id: String
    let role: Role
    var text: String
    var final: Bool
}

@MainActor
final class AikaCallEngine: ObservableObject {
    @Published private(set) var state: AikaOrbState = .idle
    @Published private(set) var level: Double = 0
    @Published private(set) var inCall = false
    @Published private(set) var isMuted = false
    @Published private(set) var transcript: [AikaTranscriptLine] = []
    @Published var notice: String?

    private var conversation: Conversation?
    private var api: AikaAPI?
    private var toolNames: Set<String> = []
    private var subscriptions = Set<AnyCancellable>()
    private var startTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var toolTasks: [String: Task<Void, Never>] = [:]
    private var vad: Double = 0
    private var agentState: ElevenLabs.AgentState = .listening
    private var userEnded = false
    /// Zvyšuje se s každým hovorem – zpětná volání ze starého hovoru se ignorují.
    private var generation = 0

    func start(token appToken: String?) {
        guard !inCall else { return }
        guard let token = AikaConfig.token(from: appToken), !token.isEmpty else {
            notice = "Nejsi přihlášený. Přihlas se znovu."
            return
        }
        generation += 1
        let gen = generation
        notice = nil
        transcript = []
        inCall = true
        isMuted = false
        userEnded = false
        vad = 0
        agentState = .listening
        state = .connecting
        let api = AikaAPI(authToken: token)
        self.api = api

        startTask = Task { [weak self] in
            await self?.connect(api: api, generation: gen)
        }
    }

    func stop() {
        userEnded = true
        startTask?.cancel()
        startTask = nil
        let conv = conversation
        finish()
        if let conv { Task { await conv.endConversation() } }
    }

    func toggleMute() {
        guard inCall, let conversation else { return }
        let target = !isMuted
        isMuted = target
        Task {
            do { try await conversation.setMuted(target) }
            catch { await MainActor.run { self.isMuted = conversation.isMuted } }
        }
    }

    // MARK: - Připojení

    private func connect(api: AikaAPI, generation gen: Int) async {
        // Token hovoru se stahuje už během dotazu na mikrofon – start je o jeden síťový krok rychlejší.
        async let pendingSession = api.startSession()
        let granted = await AVAudioApplication.requestRecordPermission()
        guard gen == generation, inCall else { return }
        guard granted else {
            finish(message: "Bez přístupu k mikrofonu to nepůjde. Povol mikrofon v Nastavení → Provikart.")
            return
        }
        // Mikrofon a hlasové zpracování se nahřejí hned, souběžně se stahováním tokenu –
        // jinak by se zapínaly až po připojení k ElevenLabs a první slova by se ztratila / zasekla.
        Self.prewarmMicrophone()

        let session: AikaSession
        do {
            session = try await pendingSession
        } catch {
            guard gen == generation else { return }
            finish(message: (error as? AikaAPIError)?.message ?? "Nepodařilo se spojit se serverem. Zkontroluj připojení.")
            return
        }
        guard gen == generation, inCall, !Task.isCancelled else { return }

        #if targetEnvironment(simulator)
        // Simulátor neumí hlasové zpracování iOS (VPIO) → audio engine hlásí −3010 a mikrofon se nezapne.
        let audio = AudioPipelineConfiguration(recordingAlwaysPrepared: false, voiceProcessingBypassed: true)
        #else
        let audio = AudioPipelineConfiguration.default
        #endif

        let config = ConversationConfig(
            dynamicVariables: session.dynamicVariables,
            onDisconnect: { [weak self] reason in
                Task { @MainActor in self?.handleDisconnect(reason, generation: gen) }
            },
            audioConfiguration: audio,
            onError: { [weak self] error in
                Task { @MainActor in self?.handleError(error, generation: gen) }
            },
            onVadScore: { [weak self] score in
                Task { @MainActor in
                    guard let self, gen == self.generation else { return }
                    self.vad = score
                }
            },
            onUnhandledClientToolCall: { [weak self] call in
                Task { @MainActor in self?.handleToolCall(call, generation: gen) }
            }
        )

        do {
            let conv = try await ElevenLabs.startConversation(conversationToken: session.token, config: config)
            guard gen == generation, inCall else {
                await conv.endConversation()
                return
            }
            conversation = conv
            bind(conv, generation: gen)
            startLevelLoop(generation: gen)
        } catch {
            guard gen == generation else { return }
            Log.aika.error("Start hovoru selhal: \(String(describing: error), privacy: .public)")
            #if DEBUG
            finish(message: "Hovor se nepodařilo spustit. (\(error.localizedDescription))")
            #else
            finish(message: "Hovor se nepodařilo spustit. Zkus to znovu.")
            #endif
        }
    }

    private func bind(_ conv: Conversation, generation gen: Int) {
        subscriptions.removeAll()

        conv.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] st in
                guard let self, gen == self.generation else { return }
                switch st {
                case .idle, .connecting:
                    self.state = .connecting
                case .active:
                    self.applyAgentState()
                case .ended(let reason):
                    if self.inCall {
                        self.finish(message: reason == .userEnded || self.userEnded ? nil : "Hovor skončil.")
                    }
                case .error(let error):
                    self.handleError(error, generation: gen)
                }
            }
            .store(in: &subscriptions)

        conv.$agentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] st in
                guard let self, gen == self.generation else { return }
                self.agentState = st
                if conv.state.isActive { self.applyAgentState() }
            }
            .store(in: &subscriptions)

        conv.$isMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] muted in
                guard let self, gen == self.generation, conv.state.isActive else { return }
                self.isMuted = muted
            }
            .store(in: &subscriptions)

        conv.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messages in
                guard let self, gen == self.generation else { return }
                self.transcript = messages.map {
                    AikaTranscriptLine(
                        id: $0.id,
                        role: $0.role == .user ? .user : .assistant,
                        text: $0.content,
                        final: true
                    )
                }
            }
            .store(in: &subscriptions)
    }

    private func applyAgentState() {
        guard inCall else { return }
        // Během běžícího nástroje Aika „přemýšlí“, i když SDK hlásí poslech.
        if !toolTasks.isEmpty && agentState != .speaking {
            state = .thinking
            return
        }
        switch agentState {
        case .listening: state = .listening
        case .thinking: state = .thinking
        case .speaking: state = .speaking
        }
    }

    // MARK: - Nástroje

    private func handleToolCall(_ call: ClientToolCallEvent, generation gen: Int) {
        guard gen == generation, let api else { return }
        if !toolNames.isEmpty && !toolNames.contains(call.toolName) {
            Log.aika.info("Neznámý nástroj \(call.toolName, privacy: .public) – přeposílám serveru")
        }
        let id = call.toolCallId
        toolTasks[id] = Task { [weak self] in
            let output = await api.runTool(name: call.toolName, argumentsJSON: call.parametersData)
            await MainActor.run {
                guard let self, gen == self.generation else { return }
                self.toolTasks[id] = nil
                self.applyAgentState()
                guard let conv = self.conversation else { return }
                if call.expectsResponse {
                    Task {
                        do { try await conv.sendToolResult(for: id, result: output) }
                        catch { Log.aika.error("Výsledek nástroje se nepodařilo odeslat: \(String(describing: error), privacy: .public)") }
                    }
                } else {
                    conv.markToolCallCompleted(id)
                }
            }
        }
        applyAgentState()
    }

    // MARK: - Konec / chyby

    private func handleDisconnect(_ reason: DisconnectionReason, generation gen: Int) {
        guard gen == generation, inCall else { return }
        switch reason {
        case .user: finish()
        case .agent: finish(message: userEnded ? nil : "Aika hovor ukončila.")
        case .error: finish(message: "Spojení s Aikou se přerušilo.")
        }
    }

    private func handleError(_ error: ConversationError, generation gen: Int) {
        guard gen == generation, inCall else { return }
        Log.aika.error("Chyba hovoru: \(String(describing: error), privacy: .public)")
        switch error {
        case .microphoneToggleFailed:
            notice = "Mikrofon se nepodařilo přepnout."
        case .authenticationFailed:
            finish(message: "Hovor se nepodařilo ověřit. Zkus to znovu.")
        case .agentTimeout:
            finish(message: "Aika se nepřipojila včas. Zkus to znovu.")
        default:
            if conversation?.state.isActive != true {
                finish(message: "Spojení s Aikou se nepodařilo.")
            }
        }
    }

    private func finish(message: String? = nil) {
        generation += 1
        subscriptions.removeAll()
        toolTasks.values.forEach { $0.cancel() }
        toolTasks.removeAll()
        levelTask?.cancel()
        levelTask = nil
        conversation = nil
        inCall = false
        isMuted = false
        level = 0
        state = .idle
        Self.releaseMicrophone()
        if let message { notice = message }
    }

    // MARK: - Mikrofon předem

    /// Spustí nahrávací cestu (mikrofon + hlasové zpracování) ještě před připojením, ztlumeně.
    /// SDK ElevenLabs by to udělalo až po připojení k místnosti – to je ta prodleva na začátku.
    nonisolated static func prewarmMicrophone() {
        #if !targetEnvironment(simulator)
        Task.detached(priority: .userInitiated) {
            do { try await LiveKit.AudioManager.shared.setRecordingAlwaysPreparedMode(true) }
            catch { Log.aika.notice("Mikrofon se nepodařilo připravit předem: \(String(describing: error), privacy: .public)") }
        }
        #endif
    }

    /// Po hovoru mikrofon uvolnit, ať nesvítí oranžová tečka a nežere baterii.
    nonisolated static func releaseMicrophone() {
        #if !targetEnvironment(simulator)
        Task.detached(priority: .utility) {
            try? await LiveKit.AudioManager.shared.setRecordingAlwaysPreparedMode(false)
        }
        #endif
    }

    // MARK: - Hlasitost pro kouli

    /// Při poslechu jde o VAD skóre uživatele, při mluvení o jemné „dýchání“ hlasu Aiky.
    private func startLevelLoop(generation gen: Int) {
        levelTask?.cancel()
        levelTask = Task { [weak self] in
            var t = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                t += 0.05
                guard let self, gen == self.generation else { return }
                switch self.state {
                case .speaking:
                    self.level = 0.35 + 0.2 * sin(t * 7) + 0.1 * sin(t * 13.3)
                case .listening:
                    self.level = self.isMuted ? 0 : min(1, self.vad)
                default:
                    self.level = 0
                }
            }
        }
    }
}
