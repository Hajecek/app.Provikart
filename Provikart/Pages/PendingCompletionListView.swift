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
    /// Položka, u které uživatel zadal dokončit – zobrazí se potvrzovací dialog.
    @State private var itemToComplete: PendingCompletionItem?

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
                        Section {
                            PendingCompletionRow(
                                item: item,
                                isCompleting: completingIds.contains(item.id),
                                onRequestComplete: { itemToComplete = $0 }
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                    }
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(12)
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
        .alert("Dokončit položku?", isPresented: Binding(
            get: { itemToComplete != nil },
            set: { if !$0 { itemToComplete = nil } }
        )) {
            Button("Zrušit", role: .cancel) {
                itemToComplete = nil
            }
            Button("Dokončit") {
                guard let item = itemToComplete else { return }
                itemToComplete = nil
                Task { await completeItem(item) }
            }
        } message: {
            Text("Opravdu chcete označit tuto položku jako dokončenou?")
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

// MARK: - Řádek položky (iOS styl, v rámci Section = jedna karta)

private struct PendingCompletionRow: View {
    let item: PendingCompletionItem
    let isCompleting: Bool
    /// Uživatel klepl na Dokončit – rodič zobrazí potvrzení a pak volá completeItem.
    let onRequestComplete: (PendingCompletionItem) -> Void

    /// České formátování data z installation_day (YYYY-MM-DD) a installation_time (HH:MM).
    private var installationDateFormatted: String? {
        guard let day = item.installation_day, !day.isEmpty else { return nil }
        guard let date = parseDate(day) else { return day + (item.installation_time.map { " \($0)" } ?? "") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let dateStr = formatter.string(from: date)
        if let time = item.installation_time, !time.isEmpty {
            return dateStr + ", " + time
        }
        return dateStr
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.item_name ?? "Položka")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onRequestComplete(item)
                } label: {
                    if isCompleting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 20, height: 20)
                    } else {
                        Text("Dokončit")
                            .font(.subheadline.weight(.medium))
                    }
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .controlSize(.small)
                .disabled(isCompleting)
            }

            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Objednávka", value: item.displayOrderNumber)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let name = item.customer_name, !name.isEmpty {
                    LabeledContent("Zákazník", value: name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let dateStr = installationDateFormatted {
                    LabeledContent("Termín", value: dateStr)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if item.commission > 0 {
                    LabeledContent("Provize", value: priceString(item.commission))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listRowSeparator(.hidden)
    }
}

private func parseDate(_ yyyyMMdd: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    return formatter.date(from: yyyyMMdd.trimmingCharacters(in: .whitespaces))
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
