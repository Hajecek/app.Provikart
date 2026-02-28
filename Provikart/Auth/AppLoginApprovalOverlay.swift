//
//  AppLoginApprovalOverlay.swift
//  Provikart
//
//  Schvalování přihlášení na web z aplikace – systémový sheet (modální okno).
//

import SwiftUI

/// Stav čekajících požadavků na přihlášení – sdílený v aplikaci pro zobrazení sheetu.
final class AppLoginApprovalState: ObservableObject {
    @Published private(set) var pendingRequests: [AppLoginRequest] = []
    /// Požadavek, pro který se má zobrazit sheet (nil = sheet skryt).
    @Published var presentedRequest: AppLoginRequest?
    @Published var isProcessing = false
    @Published var errorMessage: String?

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
                if let first = list.first {
                    presentedRequest = first
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
        presentedRequest = pendingRequests.first
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
