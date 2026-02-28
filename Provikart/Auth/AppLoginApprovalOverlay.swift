//
//  AppLoginApprovalOverlay.swift
//  Provikart
//
//  Schvalování přihlášení na web z aplikace – systémový sheet (modální okno).
//

import SwiftUI

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

    /// Načte čekající požadavky (volá se z pollingu – nekanceluje task).
    func fetchPending(username: String, token: String?) {
        guard !username.isEmpty else { return }
        Task { @MainActor in
            do {
                let list = try await service.fetchPendingRequests(username: username, token: token)
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

    /// Otevře sheet z accessory (tap na bottom accessory).
    func openSheetFromAccessory() {
        if let first = pendingRequests.first {
            // Uživatel si explicitně přeje otevřít → povolíme další auto-sheety.
            userDismissedSheetUntilInteraction = false
            presentation = .sheet(first)
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
