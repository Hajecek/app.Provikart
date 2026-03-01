//
//  AppLoginApprovalOverlay.swift
//  Provikart
//
//  Schvalování přihlášení na web z aplikace – systémový sheet (modální okno).
//

import SwiftUI

// MARK: - Časová platnost požadavku

/// Platnost požadavku na přihlášení – backend: created_at > DATE_SUB(NOW(), INTERVAL 1 MINUTE)
private let loginRequestTimeoutSeconds: TimeInterval = 60 // 1 minuta

private let requestReceivedAtDefaultsKey = "AppLoginApproval.requestReceivedAt"

extension AppLoginRequest {
    /// Kdy požadavek vyprší (created_at + timeout), nebo nil pokud created_at nelze přečíst.
    var expiresAt: Date? {
        guard let created = createdAt else { return nil }
        return Date(timeInterval: loginRequestTimeoutSeconds, since: created)
    }

    private var createdAt: Date? {
        guard let raw = created_at, !raw.isEmpty else { return nil }
        // ISO8601 (např. 2025-02-28T12:34:56Z)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        // Unix timestamp jako string
        if let sec = Double(raw) { return Date(timeIntervalSince1970: sec) }
        return nil
    }
}

/// Zobrazí přesný sekundový odpočet do vypršení (vždy z platného expiresAt).
private struct LoginRequestCountdownView: View {
    let expiresAt: Date?

    var body: some View {
        if let expires = expiresAt {
            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                let remaining = max(0, expires.timeIntervalSince(context.date))
                let text = formatCountdown(remaining)
                Text(text)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(remaining == 0 ? Color.red : (remaining <= 60 ? Color.red : Color.secondary))
            }
        }
    }

    private func formatCountdown(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        if seconds <= 0 {
            return "Vypršelo"
        }
        if m > 0 {
            return "Zbývá \(m) min \(s) s"
        } else {
            return "Zbývá \(s) s"
        }
    }
}

/// Jak zobrazit čekající přihlášení: sheet, jen accessory (po přetažení), nebo nic.
enum LoginApprovalPresentation {
    case sheet(AppLoginRequest)
    case accessory
    case none
}

/// Stav čekajících požadavků na přihlášení – sdílený v aplikaci pro zobrazení sheetu.
final class AppLoginApprovalState: ObservableObject {
    @Published private(set) var pendingRequests: [AppLoginRequest] = []
    /// Jedna hodnota: sheet / accessory / none – při zavření sheetu jen přepneme na .accessory, žádný race.
    @Published var presentation: LoginApprovalPresentation = .none
    @Published var isProcessing = false
    @Published var errorMessage: String?

    /// Pokud uživatel sheet zavřel „bokem“, neotvírat ho automaticky z pollingu,
    /// dokud si ho sám z accessory znovu neotevře, nebo dokud fronta úplně nezmizí.
    private var userDismissedSheetUntilInteraction = false

    var presentedRequest: AppLoginRequest? {
        if case .sheet(let r) = presentation { return r }
        return nil
    }

    var showAsBottomAccessory: Bool {
        if case .accessory = presentation { return true }
        return false
    }

    private let service = AppLoginRequestService()
    private var pollTask: Task<Void, Never>?
    /// Čas prvního přijetí požadavku (persistovaný do UserDefaults, aby po restartu appky byl odpočet správný).
    private var requestReceivedAt: [String: Date] = [:]

    private func loadRequestReceivedAt() {
        guard let raw = UserDefaults.standard.dictionary(forKey: requestReceivedAtDefaultsKey) as? [String: Double] else { return }
        requestReceivedAt = raw.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private func saveRequestReceivedAt() {
        let raw = requestReceivedAt.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(raw, forKey: requestReceivedAtDefaultsKey)
    }

    /// Vrací přesný čas vypršení: z API (created_at) nebo od prvního přijetí (včetně po restartu appky).
    func effectiveExpiresAt(for request: AppLoginRequest) -> Date? {
        if let apiExpires = request.expiresAt { return apiExpires }
        if requestReceivedAt.isEmpty { loadRequestReceivedAt() }
        guard let received = requestReceivedAt[request.request_id] else { return nil }
        return Date(timeInterval: loginRequestTimeoutSeconds, since: received)
    }

    /// Načte čekající požadavky (volá se z pollingu – nekanceluje task).
    func fetchPending(username: String, token: String?) {
        guard !username.isEmpty else { return }
        Task { @MainActor in
            do {
                let list = try await service.fetchPendingRequests(username: username, token: token)
                loadRequestReceivedAt()
                let now = Date()
                for r in list {
                    if requestReceivedAt[r.request_id] == nil {
                        requestReceivedAt[r.request_id] = now
                    }
                }
                requestReceivedAt = requestReceivedAt.filter { id, _ in list.contains(where: { $0.request_id == id }) }
                saveRequestReceivedAt()
                pendingRequests = list
                errorMessage = nil

                if list.isEmpty {
                    // Reset – nic nečeká, můžeme zapomenout, že uživatel zavřel sheet.
                    userDismissedSheetUntilInteraction = false
                    presentation = .none
                } else {
                    switch presentation {
                    case .accessory:
                        // Zůstaň v accessory, dokud si to uživatel sám neotevře.
                        break
                    case .sheet:
                        // Už se něco zobrazuje, jen držíme aktuální list
                        break
                    case .none:
                        if userDismissedSheetUntilInteraction {
                            // Po uživatelském zavření nikdy neotevírej automaticky.
                            presentation = .accessory
                        } else if let first = list.first {
                            presentation = .sheet(first)
                        }
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
                print("[AppLogin] Pending error: \(error)")
            }
        }
    }

    /// Schválí nebo odmítne požadavek a skryje sheet (případně zobrazí další).
    func respond(action: ApproveAction, requestId: String, token: String?) {
        guard let token = token, !token.isEmpty else {
            errorMessage = "Chybí přihlášení"
            dismissCurrent()
            return
        }
        isProcessing = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await service.approveOrReject(requestId: requestId, action: action, token: token)
                dismissCurrent()
            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }

    /// Odstraní aktuální požadavek z fronty a skryje nebo zobrazí další.
    func dismissCurrent() {
        if let first = pendingRequests.first {
            pendingRequests.removeAll { $0.request_id == first.request_id }
        }
        if let first = pendingRequests.first {
            presentation = .sheet(first)
        } else {
            // Fronta prázdná → reset chování, aby se příští nové požadavky mohly opět automaticky otevřít.
            userDismissedSheetUntilInteraction = false
            presentation = .none
        }
    }

    /// Uživatel zavřel sheet (swipe/tap bokem) → okamžitě zobraz jen accessory a neotevírej znovu.
    func dismissedSheetByUser() {
        // Nastav flag hned, aby případný souběžný fetchPending už neotevřel sheet.
        userDismissedSheetUntilInteraction = true

        if pendingRequests.isEmpty {
            // Nic nečeká → accessory nedává smysl, zároveň reset flagu.
            userDismissedSheetUntilInteraction = false
            presentation = .none
        } else {
            // Okamžitě přepni do accessory (bez mezistavu .none), aby binding sheetu byl hned nil.
            presentation = .accessory
        }
    }

    /// Otevře sheet z accessory (tap na bottom accessory) – systémová animace sheetu zdola.
    func openSheetFromAccessory() {
        guard let first = pendingRequests.first else { return }
        userDismissedSheetUntilInteraction = false
        // Odložení na další run loop zajistí, že SwiftUI spustí nativní animaci prezentace sheetu
        DispatchQueue.main.async {
            self.presentation = .sheet(first)
        }
    }

    func startPolling(username: String, token: String?, interval: TimeInterval = 8) {
        guard !username.isEmpty else { return }
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                fetchPending(username: username, token: token)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}

// MARK: - Sheet (systémový modál)

struct AppLoginApprovalSheetView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var approvalState: AppLoginApprovalState
    let request: AppLoginRequest

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "globe.badge.chevron.backward")
                    .font(.system(size: 50))
                    .foregroundStyle(.tint)

                Text("Na webu byl zadán požadavek na přihlášení k vašemu účtu. Chcete přihlášení povolit?")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                LoginRequestCountdownView(expiresAt: approvalState.effectiveExpiresAt(for: request))

                if let err = approvalState.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 16) {
                    Button("Odmítnout") {
                        approvalState.respond(action: .reject, requestId: request.request_id, token: authState.authToken)
                    }
                    .buttonStyle(.bordered)
                    .disabled(approvalState.isProcessing)

                    Button("Povolit") {
                        approvalState.respond(action: .approve, requestId: request.request_id, token: authState.authToken)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(approvalState.isProcessing)
                }
                .padding(.top, 8)
            }
            .padding(32)
            .navigationTitle("Přihlášení na webu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") {
                        approvalState.dismissCurrent()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Bottom accessory (po přetažení sheetu)

struct AppLoginApprovalAccessoryView: View {
    @ObservedObject var approvalState: AppLoginApprovalState

    var body: some View {
        Button {
            approvalState.openSheetFromAccessory()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe.badge.chevron.backward")
                    .font(.body)
                Text("Přihlášení na webu čeká")
                    .font(.subheadline)
                if let first = approvalState.pendingRequests.first, let expires = approvalState.effectiveExpiresAt(for: first) {
                    Spacer()
                    LoginRequestCountdownView(expiresAt: expires)
                        .font(.caption)
                }
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

/// Modifier pro zobrazení čekajícího přihlášení jako tabViewBottomAccessory (iOS 26+).
struct LoginApprovalBottomAccessoryModifier: ViewModifier {
    @ObservedObject var approvalState: AppLoginApprovalState

    private var showAccessory: Bool {
        approvalState.showAsBottomAccessory && !approvalState.pendingRequests.isEmpty
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if showAccessory {
                content
                    .tabViewBottomAccessory {
                        AppLoginApprovalAccessoryView(approvalState: approvalState)
                    }
            } else {
                content
            }
        } else {
            content
        }
    }
}
