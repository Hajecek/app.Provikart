//
//  AddView.swift
//  Provikart
//

import SwiftUI

struct AddView: View {
    @Binding var selectedTab: Tabs
    @Binding var isAIMode: Bool
    @EnvironmentObject private var authState: AuthState
    @State private var searchText = ""
    @State private var isRecording = false
    @StateObject private var audioMeter = AudioLevelMeter()
    private let authService = AuthService()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                if isAIMode {
                    aiOrderContent
                } else {
                    defaultContent
                }
            }
            .task(id: isAIMode, priority: .background) {
                guard isAIMode else { return }
                while !Task.isCancelled {
                    let token = await MainActor.run { authState.authToken ?? "" }
                    if token.isEmpty {
                        print("[Profil] Kontrola (každých 5 s): žádný token, přihlaste se")
                    } else {
                        do {
                            if let user = try await authService.fetchCurrentUser(token: token) {
                                await MainActor.run {
                                    authState.refreshCurrentUser(user)
                                    printUserInfo(user)
                                }
                            } else {
                                print("[Profil] Kontrola (každých 5 s): server nevrátil uživatele (401 nebo prázdná odpověď)")
                            }
                        } catch {
                            print("[Profil] Kontrola (každých 5 s): chyba – \(error.localizedDescription)")
                        }
                    }
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
            .refreshable {
                await refreshUserAndLog()
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert("Mikrofon nepovolen", isPresented: $audioMeter.permissionDenied) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Pro hlasové vyhledávání povolte přístup k mikrofonu v Nastavení.")
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        selectedTab = .home
                    } label: {
                        Image(systemName: "house")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileBarButton()
                }
            }
        }
    }

    // MARK: - AI objednávka
    @ViewBuilder
    private var aiOrderContent: some View {
        let plan = authState.currentUser?.plan ?? "free"
        if plan != "paid" {
            aiOrderPaidOnlyView
        } else {
            let greeting: String = userName.isEmpty
                ? "\(timeGreeting), vlož text objednávky a rozpoznám ho."
                : "\(timeGreeting), \(userName), vlož text objednávky a rozpoznám ho."
            AIOrderFlowView(
                isAIMode: $isAIMode,
                authToken: authState.authToken,
                greetingText: greeting
            )
        }
    }

    /// Zobrazení pro uživatele s free plánem – bez inputu, jen hláška.
    private var aiOrderPaidOnlyView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Tato stránka se dá využít pouze pro uživatele s placeným plánem.")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Načte aktuálního uživatele ze serveru, aktualizuje stav a vypíše do konzole (např. při pull-to-refresh).
    private func refreshUserAndLog() async {
        guard let token = authState.authToken, !token.isEmpty else { return }
        guard let user = try? await authService.fetchCurrentUser(token: token) else { return }
        authState.refreshCurrentUser(user)
        printUserInfo(user)
    }

    /// Výpis všech informací o uživateli do konzole (tag [Profil]), včetně URL profilového obrázku.
    private func printUserInfo(_ u: UserInfo) {
        print("[Profil] Uživatel:")
        print("  id: \(u.id ?? 0)")
        print("  email: \(u.email ?? "—")")
        print("  name: \(u.name ?? "—")")
        print("  username: \(u.username ?? "—")")
        print("  personal_number: \(u.personal_number ?? "—")")
        print("  firstname: \(u.firstname ?? "—")")
        print("  lastname: \(u.lastname ?? "—")")
        print("  profile_image: \(u.profile_image ?? "—")")
        if let url = u.profileImageURL {
            print("  profile_image_url: \(url.absoluteString)")
        } else {
            print("  profile_image_url: —")
        }
        print("  role: \(u.role ?? "—")")
        print("  plan: \(u.plan ?? "—")")
    }

    // MARK: - Výchozí (vyhledávání / hlas)
    private var defaultContent: some View {
        VStack(spacing: 16) {
            Text(greetingText)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            if isRecording {
                VoiceRecordingBarView(
                    levels: audioMeter.levels,
                    onStop: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            audioMeter.stop()
                            isRecording = false
                        }
                    },
                    onSend: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            audioMeter.stop()
                            isRecording = false
                        }
                        // TODO: odeslat nahrávku / převést na text
                    }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96)),
                    removal: .opacity.combined(with: .scale(scale: 0.96))
                ))
            } else {
                HStack(spacing: 10) {
                    HStack(spacing: 12) {
                        TextField("Zeptej se na cokoli", text: $searchText)
                            .textFieldStyle(.plain)
                            .foregroundStyle(Color(uiColor: .label))
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                audioMeter.start()
                                isRecording = true
                            }
                        } label: {
                            Image(systemName: "mic.fill")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(height: 52)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    Button {
                        submitSearch()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(uiColor: .systemBackground))
                            .frame(width: 52, height: 52)
                            .background(Color(uiColor: .label))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 52)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96)),
                    removal: .opacity.combined(with: .scale(scale: 0.96))
                ))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isRecording)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    /// Pozdrav podle denní doby: Dobré ráno, Dobré dopoledne, Dobré odpoledne, Dobrý večer.
    private var timeGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<9: return "Dobré ráno"
        case 9..<12: return "Dobré dopoledne"
        case 12..<18: return "Dobré odpoledne"
        default: return "Dobrý večer"
        }
    }

    private var userName: String {
        if let first = authState.currentUser?.firstname, !first.isEmpty { return first }
        if let name = authState.currentUser?.name, !name.isEmpty { return name }
        let first = authState.currentUser?.firstname ?? ""
        let last = authState.currentUser?.lastname ?? ""
        let composed = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        if !composed.isEmpty { return composed }
        if let username = authState.currentUser?.username, !username.isEmpty { return username }
        return ""
    }

    private var greetingText: String {
        if userName.isEmpty {
            return "\(timeGreeting), co dnes vymyslíme?"
        }
        return "\(timeGreeting), \(userName), co dnes vymyslíme?"
    }

    private func submitSearch() {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Zatím jen příprava – napojíš odeslání / API
    }
}

// MARK: - AI objednávka: text → parsování → výsledek → přidat do DB

private struct AIOrderFlowView: View {
    @Binding var isAIMode: Bool
    let authToken: String?
    let greetingText: String

    @State private var orderText = ""
    @State private var isLoading = false
    @State private var isRecording = false
    @State private var errorMessage: String?
    @State private var parsedResponse: AIParseOrderResponse?
    @State private var showCreateConfirm = false
    @State private var isCreating = false
    @State private var createSuccessOrderId: Int?
    @State private var createSuccessOrderNumber: String?

    @StateObject private var audioMeter = AudioLevelMeter()
    private let service = AIOrderService()

    var body: some View {
        Group {
            if parsedResponse == nil {
                VStack(spacing: 20) {
                    Spacer()

                    Text(greetingText)
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if isRecording {
                        VoiceRecordingBarView(
                            levels: audioMeter.levels,
                            onStop: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    audioMeter.stop()
                                    isRecording = false
                                }
                            },
                            onSend: {
                                audioMeter.stopWithRecognitionResult { text in
                                    DispatchQueue.main.async {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            if let t = text, !t.isEmpty {
                                                orderText = t
                                            }
                                            isRecording = false
                                        }
                                    }
                                }
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96)),
                            removal: .opacity.combined(with: .scale(scale: 0.96))
                        ))
                    } else {
                        HStack(spacing: 10) {
                            HStack(spacing: 12) {
                                TextField("Vlož text objednávky", text: $orderText)
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(Color(uiColor: .label))
                                Button {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        audioMeter.start()
                                        isRecording = true
                                    }
                                } label: {
                                    Image(systemName: "mic.fill")
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(height: 52)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                            Button {
                                parseOrder()
                            } label: {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color(uiColor: .systemBackground))
                                    .frame(width: 52, height: 52)
                                    .background(Color(uiColor: .label))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(orderText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                        }
                        .frame(height: 52)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96)),
                            removal: .opacity.combined(with: .scale(scale: 0.96))
                        ))
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("AI zpracovává text…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.25), value: isRecording)
                .padding(24)
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        aiResultScrollContent
                            .padding(24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    aiResultBottomBar
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Mikrofon nepovolen", isPresented: $audioMeter.permissionDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Pro hlasové zadání povolte přístup k mikrofonu v Nastavení.")
        }
        .confirmationDialog("Vytvořit objednávku?", isPresented: $showCreateConfirm) {
            Button("Vytvořit") {
                createOrder()
            }
            Button("Zrušit", role: .cancel) { }
        } message: {
            Text("Objednávka bude vytvořena s prázdnými údaji o zákazníkovi. Můžete je doplnit později.")
        }
        .alert("Objednávka vytvořena", isPresented: .init(
            get: { createSuccessOrderId != nil },
            set: { if !$0 { createSuccessOrderId = nil; createSuccessOrderNumber = nil } }
        )) {
            Button("OK") {
                createSuccessOrderId = nil
                createSuccessOrderNumber = nil
                isAIMode = false
            }
        } message: {
            if let num = createSuccessOrderNumber {
                Text("Číslo objednávky: \(num)")
            }
        }
    }

    @ViewBuilder
    private var aiResultScrollContent: some View {
        if let resp = parsedResponse,
           let orderNumber = resp.order_number,
           let items = resp.items,
           !items.isEmpty {

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button {
                        parsedResponse = nil
                        errorMessage = nil
                    } label: {
                        Image(systemName: "arrow.left")
                    }
                    Spacer()
                    Text("Objednávka: \(orderNumber)")
                        .font(.headline)
                }

                let totalCommission = items.reduce(0.0) { $0 + $1.commission }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.item_name)
                                    .font(.subheadline.weight(.medium))
                                Text(itemTypeLabel(item.item_type))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(formatNumber(item.commission)) Kč")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                HStack {
                    Text("Celková provize:")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(formatNumber(totalCommission)) Kč")
                        .font(.headline)
                }
                .padding(.vertical, 8)
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var aiResultBottomBar: some View {
        if parsedResponse != nil {
            VStack(spacing: 12) {
                if isCreating {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.9)
                        Text("Vytvářím objednávku…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    showCreateConfirm = true
                } label: {
                    Text("Přidat do objednávek")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isCreating)

                Button(role: .destructive) {
                    parsedResponse = nil
                    errorMessage = nil
                } label: {
                    Text("Zrušit")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.regular)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
    }

    /// Zobrazí srozumitelnou zprávu při chybách OpenAI a při free plánu.
    private func friendlyAIErrorMessage(_ raw: String) -> String {
        if raw.contains("OpenAI") && raw.contains("401") {
            return "Na serveru je neplatný nebo chybějící OpenAI API klíč. Správce musí v konfiguraci (app_config.php nebo env) nastavit platný OPENAI_API_KEY."
        }
        if raw.contains("OpenAI") && raw.contains("429") {
            return "Překročen limit OpenAI API. Zkuste to za minutu znovu."
        }
        if raw.contains("403") || raw.lowercased().contains("free") || raw.contains("placený plán") || raw.contains("placeného plánu") {
            return "Máte free plán. Pro použití této funkce je potřeba mít placený plán."
        }
        return raw
    }

    private func itemTypeLabel(_ type: String) -> String {
        switch type {
        case "internet": return "Internet"
        case "televize": return "Televize"
        case "postpaid": return "Mobilní tarif"
        case "pevna_linka": return "Pevná linka"
        default: return "Jiné"
        }
    }

    private func formatNumber(_ n: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "cs_CZ")
        return formatter.string(from: NSNumber(value: n)) ?? "\(Int(n))"
    }

    private func parseOrder() {
        let text = orderText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        errorMessage = nil
        isLoading = true
        Task {
            do {
                let response = try await service.parseOrder(text: text, token: authToken)
                await MainActor.run {
                    isLoading = false
                    // success is Bool? in AIParseOrderResponse – coalesce to false
                    if (response.success ?? false),
                       response.order_number != nil,
                       let items = response.items, !items.isEmpty {
                        parsedResponse = response
                    } else {
                        let msg = response.error ?? "AI nevrátilo platná data."
                        errorMessage = friendlyAIErrorMessage(msg)
                        print("[ProviKart AI] Chyba parse_order: \(msg)")
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    let raw = error.localizedDescription
                    errorMessage = friendlyAIErrorMessage(raw)
                    print("[ProviKart AI] Chyba parse_order: \(raw)")
                    print("[ProviKart AI] Detail: \(error)")
                }
            }
        }
    }

    private func createOrder() {
        guard let resp = parsedResponse, let orderNumber = resp.order_number, let items = resp.items, !items.isEmpty else { return }
        showCreateConfirm = false
        isCreating = true
        Task {
            do {
                let response = try await service.createOrderDirect(orderNumber: orderNumber, items: items, token: authToken)
                await MainActor.run {
                    isCreating = false
                    if response.success != false {
                        createSuccessOrderId = response.order_id
                        createSuccessOrderNumber = response.order_number
                    } else {
                        let msg = response.error ?? "Nepodařilo se vytvořit objednávku."
                        errorMessage = friendlyAIErrorMessage(msg)
                        print("[ProviKart AI] Chyba create_order: \(msg)")
                    }
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = friendlyAIErrorMessage(error.localizedDescription)
                    print("[ProviKart AI] Chyba create_order: \(error.localizedDescription)")
                    print("[ProviKart AI] Detail: \(error)")
                }
            }
        }
    }
}

// MARK: - Nahrávací lišta (jen vlny) + tlačítka Stop a Odeslat v jedné linii vedle sebe

private struct VoiceRecordingBarView: View {
    let levels: [CGFloat]
    let onStop: () -> Void
    let onSend: () -> Void

    private let barCount = AudioLevelMeter.barCount
    private let barWidth: CGFloat = 2.5
    private let barSpacing: CGFloat = 2
    private let maxBarHeight: CGFloat = 18
    private let rowHeight: CGFloat = 52
    private let buttonSize: CGFloat = 52

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .frame(width: buttonSize, height: buttonSize)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(Color(uiColor: .tertiaryLabel))
                        .frame(width: barWidth, height: max(3, maxBarHeight * levels[i]))
                        .animation(.easeOut(duration: 0.06), value: levels[i])
                }
            }
            .frame(height: maxBarHeight)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(height: rowHeight)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .frame(width: buttonSize, height: buttonSize)
                    .background(Color(uiColor: .label))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: rowHeight)
    }
}

// MARK: - Sheet s výběrem typu přidání (používá TabMenuView)

struct AddTypeSheetView: View {
    @Binding var isPresented: Bool
    var onSelectAIMode: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    // TODO: Normální přidání
                    isPresented = false
                    dismiss()
                } label: {
                    Label("Normální přidání", systemImage: "plus.circle.fill")
                }

                Button {
                    onSelectAIMode?()
                    dismiss()
                } label: {
                    Label("AI objednávka", systemImage: "sparkles")
                }
            }
            .navigationTitle("Přidat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    AddView(selectedTab: .constant(.add), isAIMode: .constant(false))
        .environmentObject(AuthState())
}
