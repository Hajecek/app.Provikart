//
//  PendingCompletionListView.swift
//  Provikart
//
//  Seznam položek čekajících na dokončení (po termínu instalace). Možnost označit jako dokončené.
//

import SwiftUI

struct PendingCompletionListView: View {
    @EnvironmentObject private var authState: AuthState
    @State private var items: [PendingCompletionItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var completingIds: Set<Int> = []
    /// Chyba z akce „Dokončit“ – zobrazí se v alertu i když je seznam neprázdný.
    @State private var completionError: String?

    private let pendingService = OrderItemsPendingCompletionService()
    private let completeService = OrderItemCompleteService()

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView("Načítám položky…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorMessage, items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(err)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Zkusit znovu") {
                        Task { await loadItems() }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView(
                    "Žádné položky",
                    systemImage: "checkmark.circle",
                    description: Text("Všechny položky po termínu instalace jsou dokončené.")
                )
            } else {
                List {
                    ForEach(items) { item in
                        PendingCompletionRow(
                            item: item,
                            isCompleting: completingIds.contains(item.id),
                            onComplete: { Task { await completeItem(item) } }
                        )
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Čekající na dokončení")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.visible)
        .background(Color(uiColor: .systemGroupedBackground))
        .task { await loadItems() }
        .refreshable { await loadItems() }
        .alert("Chyba při dokončení", isPresented: Binding(
            get: { completionError != nil },
            set: { if !$0 { completionError = nil } }
        )) {
            Button("OK") { completionError = nil }
        } message: {
            Text(completionError ?? "Neznámá chyba")
        }
    }

    private func loadItems() async {
        let token = await MainActor.run { authState.authToken }
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            let list = try await pendingService.fetchPendingItems(token: token)
            await MainActor.run {
                items = list
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func completeItem(_ item: PendingCompletionItem) async {
        let token = await MainActor.run { authState.authToken }
        guard let token else { return }
        await MainActor.run { completingIds.insert(item.id) }
        do {
            try await completeService.completeOrderItem(orderItemId: item.id, token: token)
            await MainActor.run {
                completingIds.remove(item.id)
                items.removeAll { $0.id == item.id }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } catch {
            await MainActor.run {
                completingIds.remove(item.id)
                completionError = error.localizedDescription
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Řádek položky s tlačítkem Dokončit

private struct PendingCompletionRow: View {
    let item: PendingCompletionItem
    let isCompleting: Bool
    let onComplete: () -> Void

    private var installationText: String {
        var parts: [String] = []
        if let d = item.installation_day, !d.isEmpty { parts.append(d) }
        if let t = item.installation_time, !t.isEmpty { parts.append(t) }
        return parts.joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.item_name ?? "Položka")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("Obj. \(item.displayOrderNumber)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let name = item.customer_name, !name.isEmpty {
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !installationText.isEmpty {
                        Text(installationText)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onComplete()
                } label: {
                    if isCompleting {
                        ProgressView()
                            .scaleEffect(0.9)
                            .frame(minWidth: 88, minHeight: 32)
                    } else {
                        Text("Dokončit")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isCompleting)
            }
            if item.commission > 0 || item.base_price > 0 {
                HStack(spacing: 12) {
                    if item.commission > 0 {
                        Label(priceString(item.commission), systemImage: "creditcard")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if item.base_price > 0 {
                        Text(priceString(item.base_price))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
    }
}

private func priceString(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "CZK"
    formatter.currencySymbol = "Kč"
    formatter.maximumFractionDigits = 0
    formatter.minimumFractionDigits = 0
    return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value)) Kč"
}

#Preview {
    NavigationStack {
        PendingCompletionListView()
            .environmentObject(AuthState())
    }
}
