//
//  AikaView.swift
//  Provikart
//
//  Hlasová asistentka AIKA – vzhled podle webu (provikart.cz/aika).
//  Po otevření se hovor spustí sám a Aika pozdraví uživatele jménem.
//

import SwiftUI

private enum AikaStyle {
    static let bg = Color(red: 5 / 255, green: 6 / 255, blue: 13 / 255)          // #05060d
    static let bgCenter = Color(red: 13 / 255, green: 16 / 255, blue: 48 / 255)  // #0d1030
    static let text = Color(red: 238 / 255, green: 240 / 255, blue: 1)           // #eef0ff
    static let muted = Color(red: 141 / 255, green: 147 / 255, blue: 181 / 255)  // #8d93b5
    static let line = Color.white.opacity(0.08)
    /// Text na bílé výplni pilulky.
    static let onPill = Color(red: 16 / 255, green: 18 / 255, blue: 42 / 255)

    static func dot(_ state: AikaOrbState) -> Color {
        switch state {
        case .idle, .connecting: Color(red: 108 / 255, green: 124 / 255, blue: 1)        // #6c7cff
        case .listening: Color(red: 47 / 255, green: 224 / 255, blue: 212 / 255)          // #2fe0d4
        case .thinking: Color(red: 176 / 255, green: 108 / 255, blue: 1)                  // #b06cff
        case .speaking: Color(red: 1, green: 122 / 255, blue: 89 / 255)                   // #ff7a59
        }
    }
}

struct AikaView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var engine = AikaCallEngine()
    @State private var showTranscript = false
    @Namespace private var modeAnimation
    /// Když je Aika záložkou ve spodním menu, lišta záložek zůstává vidět.
    var keepsTabBar = false
    /// Je-li nastaveno, v liště vlevo je tlačítko „Domů“ (Aika jako záložka bez spodního menu).
    var onClose: (() -> Void)? = nil

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [AikaStyle.bgCenter, AikaStyle.bg],
                center: UnitPoint(x: 0.5, y: 0.45),
                startRadius: 0,
                endRadius: 520
            )
            .ignoresSafeArea()

            VStack(spacing: 6) {
                modeSwitch
                .padding(.top, 4)
                .padding(.horizontal, 16)

                Spacer(minLength: 0)

                Button {
                    if !engine.inCall { engine.start(token: authState.authToken) }
                } label: {
                    AikaOrbView(state: engine.state, level: engine.level, training: engine.mode == .trenink)
                        .frame(maxWidth: 520)
                }
                .buttonStyle(.plain)
                .disabled(engine.inCall)
                .accessibilityLabel(engine.inCall ? "Aika" : (engine.mode == .trenink ? "Začít trénink se zákazníkem" : "Začít hovor s Aikou"))

                Spacer(minLength: 0)
            }

            if let notice = engine.notice {
                VStack {
                    Spacer()
                    Text(notice)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 1, green: 208 / 255, blue: 216 / 255))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color(red: 26 / 255, green: 29 / 255, blue: 58 / 255), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(red: 1, green: 107 / 255, blue: 129 / 255).opacity(0.4)))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 44)
                        .onTapGesture { engine.notice = nil }
                }
                .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.25), value: engine.transcript.isEmpty)
        .animation(.easeOut(duration: 0.25), value: engine.notice)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        engine.stop()
                        onClose()
                    } label: {
                        Label("Domů", systemImage: "chevron.left")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(AikaStyle.text)
                    }
                    .accessibilityLabel("Zpět domů")
                }
            }
            ToolbarItem(placement: .principal) {
                if let started = engine.callStartedAt {
                    callTimer(started: started, ended: engine.callEndedAt)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Aika").font(.system(size: 18, weight: .bold))
                        Text("VOICE").font(.system(size: 12, weight: .medium)).tracking(1.5).foregroundStyle(AikaStyle.muted)
                    }
                    .foregroundStyle(AikaStyle.text)
                }
            }
            if !engine.transcript.isEmpty {
                // přepis je v horní liště, ať se neplete s přepínačem režimu
                ToolbarItem(placement: .topBarTrailing) {
                    transcriptButton
                }
            }
            if engine.inCall {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { engine.toggleMute() } label: {
                        Image(systemName: engine.isMuted ? "mic.slash" : "mic")
                            .foregroundStyle(engine.isMuted ? Color(red: 1, green: 207 / 255, blue: 158 / 255) : Color(red: 201 / 255, green: 205 / 255, blue: 240 / 255))
                    }
                    .accessibilityLabel(engine.isMuted ? "Zapnout mikrofon" : "Ztlumit mikrofon")
                    Button { engine.stop() } label: {
                        Image(systemName: "phone.down.fill")
                            .foregroundStyle(Color(red: 1, green: 141 / 255, blue: 160 / 255))
                    }
                    .accessibilityLabel("Ukončit hovor")
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(keepsTabBar ? .visible : .hidden, for: .tabBar)
        .sheet(isPresented: $showTranscript) { transcriptSheet }
        .onAppear { engine.start(token: authState.authToken) }
        .onDisappear { engine.stop() }
    }

    // MARK: - Přepis

    // MARK: - Přepínač Asistent | Trénink (styl přepínače období v manažerském Přehledu)

    private var modeSwitch: some View {
        HStack(spacing: 4) {
            ForEach(AikaMode.allCases) { item in
                let selected = engine.mode == item
                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    withAnimation(.snappy(duration: 0.28)) {
                        engine.switchMode(item, token: authState.authToken)
                    }
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? AikaStyle.onPill : Color.white.opacity(0.84))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Color.white)
                                    .matchedGeometryEffect(id: "mode", in: modeAnimation)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .glassPill()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Režim Aiky")
    }

    // MARK: - Časovač hovoru (po konci zůstane délka)

    private func callTimer(started: Date, ended: Date?) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let secs = max(0, Int((ended ?? context.date).timeIntervalSince(started)))
            HStack(spacing: 7) {
                if ended == nil {
                    Circle().fill(Color(red: 1, green: 77 / 255, blue: 106 / 255)).frame(width: 7, height: 7)
                }
                Text(String(format: "%02d:%02d", secs / 60, secs % 60))
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(ended == nil ? AikaStyle.text : AikaStyle.muted)
                if engine.ringing {
                    Text("zvoníš…").font(.system(size: 13)).foregroundStyle(AikaStyle.muted)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Délka hovoru \(secs / 60) minut \(secs % 60) sekund")
        }
    }

    // MARK: - Přepis (tlačítko v horní liště)

    private var transcriptButton: some View {
        Button { showTranscript = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "text.bubble")
                Text("\(engine.transcript.count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(Color(red: 201 / 255, green: 205 / 255, blue: 240 / 255))
        }
        .accessibilityLabel("Přepis, \(engine.transcript.count) zpráv")
    }

    private var transcriptSheet: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(engine.transcript) { line in
                        transcriptBubble(line).id(line.id)
                    }
                }
                .padding(14)
            }
            .onChange(of: engine.transcript) { _, lines in
                if let last = lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .background(Color(red: 14 / 255, green: 16 / 255, blue: 38 / 255))
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(red: 14 / 255, green: 16 / 255, blue: 38 / 255).opacity(0.96))
        .environment(\.colorScheme, .dark)
    }

    private func transcriptBubble(_ line: AikaTranscriptLine) -> some View {
        let isUser = line.role == .user
        let empty = line.text.isEmpty
        return VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
            Text(isUser ? "TY" : engine.mode.agentLabel)
                .font(.system(size: 10))
                .tracking(1.5)
                .foregroundStyle(AikaStyle.muted)
            Text(empty ? (line.final ? "(nerozpoznáno)" : "…") : line.text)
                .font(.system(size: 14))
                .italic(empty)
                .foregroundStyle(empty ? AikaStyle.muted : AikaStyle.text)
                .multilineTextAlignment(isUser ? .trailing : .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            isUser ? Color(red: 47 / 255, green: 224 / 255, blue: 212 / 255).opacity(0.12)
                   : (engine.mode == .trenink ? Color(red: 1, green: 122 / 255, blue: 89 / 255).opacity(0.16)
                                              : Color(red: 124 / 255, green: 92 / 255, blue: 1).opacity(0.16)),
            in: UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: isUser ? 18 : 6,
                bottomTrailingRadius: isUser ? 6 : 18,
                topTrailingRadius: 18
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: isUser ? 18 : 6,
                bottomTrailingRadius: isUser ? 6 : 18,
                topTrailingRadius: 18
            )
            .strokeBorder(Color.white.opacity(0.08))
        )
        .frame(maxWidth: 320, alignment: isUser ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

#Preview {
    NavigationStack {
        AikaView()
            .environmentObject(AuthState())
    }
}

private extension View {
    /// Skleněná kapsle jako přepínač období v manažerském Přehledu (materiál + jemný obrys).
    func glassPill() -> some View {
        self
            .background(.ultraThinMaterial, in: Capsule())
            .background(
                LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16)))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }
}
