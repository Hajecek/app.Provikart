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
    /// Asistent (data týmu) nebo Trénink (zákazník u dveří).
    /// Poslední zvolený režim platí i po novém spuštění aplikace.
    @Published private(set) var mode: AikaMode = AikaMode(rawValue: UserDefaults.standard.string(forKey: AikaCallEngine.modeKey) ?? "") ?? .asistent {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: AikaCallEngine.modeKey) }
    }
    private static let modeKey = "AikaMode"
    /// Fáze tréninku – pamatuje se stejně jako režim.
    @Published private(set) var phase: AikaTrainingPhase = AikaTrainingPhase(rawValue: UserDefaults.standard.string(forKey: AikaCallEngine.phaseKey) ?? "") ?? .nominace {
        didSet { UserDefaults.standard.set(phase.rawValue, forKey: AikaCallEngine.phaseKey) }
    }
    private static let phaseKey = "AikaTrainingPhase"
    /// Časovač: kdy hovor začal (u tréninku zazvoněním) a kdy skončil – po konci zůstane vidět délka.
    @Published private(set) var callStartedAt: Date?
    @Published private(set) var callEndedAt: Date?
    /// Trénink: obchodník právě zvoní / čeká, až se otevřou dveře.
    @Published private(set) var ringing = false
    private var doorPlayer: AVAudioPlayer?
    /// Token z posledního startu – pro přepnutí do tréninku, o které požádá sama Aika.
    private var lastAppToken: String?

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

    func start(token appToken: String?, mode newMode: AikaMode? = nil) {
        guard !inCall else { return }
        if let newMode { mode = newMode }
        lastAppToken = appToken
        callStartedAt = Date()
        callEndedAt = nil
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
        let callMode = mode
        let callPhase = phase

        startTask = Task { [weak self] in
            await self?.connect(api: api, mode: callMode, phase: callPhase, generation: gen)
        }
    }

    /// Přepnutí režimu: běžící hovor skončí dřív, než začne nový (nikdy dva hovory naráz).
    func switchMode(_ newMode: AikaMode, token appToken: String?) {
        guard newMode != mode else { return }
        if inCall { stop() }
        mode = newMode
        transcript = []
        callStartedAt = nil
        callEndedAt = nil
        notice = nil
        // Asistent se hned ozve, Trénink se spojí a čeká na obchodníka.
        start(token: appToken, mode: newMode)
    }

    /// Přepnutí fáze tréninku: běžící trénink skončí a začne znovu v nové fázi.
    func switchPhase(_ newPhase: AikaTrainingPhase, token appToken: String?) {
        guard newPhase != phase else { return }
        guard mode == .trenink else { phase = newPhase; return }
        if inCall { stop() }
        phase = newPhase
        transcript = []
        start(token: appToken)
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

    private func connect(api: AikaAPI, mode callMode: AikaMode, phase callPhase: AikaTrainingPhase, generation gen: Int) async {
        // Token hovoru se stahuje už během dotazu na mikrofon – start je o jeden síťový krok rychlejší.
        async let pendingSession = api.startSession(mode: callMode, phase: callPhase)
        let granted = await AVAudioApplication.requestRecordPermission()
        guard gen == generation, inCall else { return }
        guard granted else {
            finish(message: "Bez přístupu k mikrofonu to nepůjde. Povol mikrofon v Nastavení → Provikart.")
            return
        }
        let session: AikaSession
        do {
            session = try await pendingSession
        } catch {
            guard gen == generation else { return }
            finish(message: (error as? AikaAPIError)?.message ?? "Nepodařilo se spojit se serverem. Zkontroluj připojení.")
            return
        }
        guard gen == generation, inCall, !Task.isCancelled else { return }

        // Trénink: obchodník zazvoní, chvíli čeká a pak se otevřou dveře – teprve potom se zákazník ozve.
        if callMode == .trenink, let bell = session.zvonek {
            ringing = true
            await Self.playToEnd("zvonek-" + bell)
            try? await Task.sleep(nanoseconds: UInt64.random(in: 600_000_000...1_500_000_000))
            ringing = false
            guard gen == generation, inCall, !Task.isCancelled else { return }
            doorPlayer = Self.player("dvere")
            doorPlayer?.play()
        }

        // Mikrofon a hlasové zpracování se nahřejí před připojením k ElevenLabs,
        // jinak by se zapínaly až po připojení a první slova by se ztratila / zasekla.
        Self.prewarmMicrophone()

        #if targetEnvironment(simulator)
        // Simulátor neumí hlasové zpracování iOS (VPIO) → audio engine hlásí −3010 a mikrofon se nezapne.
        let audio = AudioPipelineConfiguration(recordingAlwaysPrepared: false, voiceProcessingBypassed: true)
        #else
        let audio = AudioPipelineConfiguration.default
        #endif

        // Trénink: hlas zákazníka vylosoval server; zákazník nemá žádné nástroje.
        let tts: TTSOverrides? = callMode == .trenink ? session.voiceId.map { TTSOverrides(voiceId: $0) } : nil

        let config = ConversationConfig(
            ttsOverrides: tts,
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
                        // výrazové značky pro hlas ([sighs], [laughs] …) do přepisu nepatří
                        text: $0.content.replacingOccurrences(of: #"\[[A-Za-z ]{2,24}\]\s*"#, with: "", options: .regularExpression),
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
        if call.toolName == "prepnout_do_treninku" {
            handleSwitchToTraining(call, generation: gen)
            return
        }
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

    /// Aika potvrdila přepnutí do tréninku: odpoví nástroji, dořekne větu a pak se hovor přepne.
    private func handleSwitchToTraining(_ call: ClientToolCallEvent, generation gen: Int) {
        let params = (try? call.getParameters()) ?? [:]
        let phase = AikaTrainingPhase(rawValue: params["faze"] as? String ?? "") ?? .nominace
        if let conv = conversation {
            let result = #"{"ok":true,"faze":"\#(phase.rawValue)","zprava":"Přepínám do tréninku."}"#
            Task { try? await conv.sendToolResult(for: call.toolCallId, result: result) }
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            var waited = 0
            while waited < 30, let self, gen == self.generation, self.agentState == .speaking {
                try? await Task.sleep(nanoseconds: 200_000_000)
                waited += 1
            }
            guard let self, gen == self.generation, self.inCall else { return }
            self.switchPhase(phase, token: self.lastAppToken)
            self.switchMode(.trenink, token: self.lastAppToken)
        }
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
        ringing = false
        doorPlayer = nil
        if callStartedAt != nil, callEndedAt == nil { callEndedAt = Date() }
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
    // MARK: - Zvuky u dveří (trénink)

    private static func player(_ name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3")
                ?? Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "Sounds") else { return nil }
        // zvonek se má ozvat i při tichém režimu, LiveKit si pak session přenastaví pro hovor
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let p = try? AVAudioPlayer(contentsOf: url)
        p?.prepareToPlay()
        return p
    }

    /// Přehraje zvuk a počká na jeho konec.
    private static func playToEnd(_ name: String) async {
        guard let p = player(name) else { return }
        p.play()
        try? await Task.sleep(nanoseconds: UInt64(max(0.3, p.duration) * 1_000_000_000))
    }

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
