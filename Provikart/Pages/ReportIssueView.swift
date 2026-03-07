//
//  ReportIssueView.swift
//  Provikart
//
//  Obrazovka pro nahlášení problému k objednávce. Napojení na API připraveno v ReportIssueService.
//

import SwiftUI

struct ReportIssueView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var orderNumber = ""
    @State private var description = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    private let service = ReportIssueService()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                Form {
                    Section {
                        TextField("Číslo objednávky", text: $orderNumber)
                            .textContentType(.none)
                            .keyboardType(.numberPad)

                        TextField("Popis problému", text: $description, axis: .vertical)
                            .lineLimit(3...8)
                    } header: {
                        Text("Údaje")
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Nahlásit problém")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        isPresented = false
                        dismiss()
                    } label: {
                        Image(systemName: "house")
                    }
                    .accessibilityLabel("Zpět na Domů")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ProfileBarButton()
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        isPresented = false
                        dismiss()
                    } label: {
                        Label("Zrušit", systemImage: "xmark.circle")
                    }
                    Spacer()
                    Button {
                        submitReport()
                    } label: {
                        Label("Odeslat", systemImage: "paperplane.fill")
                    }
                    .disabled(orderNumber.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .alert("Problém nahlášen", isPresented: $showSuccess) {
                Button("OK") {
                    showSuccess = false
                    isPresented = false
                    dismiss()
                }
            } message: {
                Text("Vaše nahlášení bylo odesláno.")
            }
        }
    }

    private func submitReport() {
        let order = orderNumber.trimmingCharacters(in: .whitespaces)
        let note = description.trimmingCharacters(in: .whitespaces)
        guard !order.isEmpty else { return }

        errorMessage = nil
        isSubmitting = true

        Task { @MainActor in
            do {
                try await service.submitReport(
                    orderNumber: order,
                    note: note.isEmpty ? nil : note,
                    token: authState.authToken
                )
                showSuccess = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

#Preview {
    ReportIssueView(isPresented: .constant(true))
        .environmentObject(AuthState())
}
