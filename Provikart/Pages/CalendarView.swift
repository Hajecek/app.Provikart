//
//  CalendarView.swift
//  Provikart
//

import SwiftUI

/// Parsuje řetězec data z API (DD.MM.YYYY nebo YYYY-MM-DD) na Date pro řazení a skupiny.
private func parseInstallationDate(_ raw: String) -> Date? {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    let ddMMyyyy: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        f.locale = Locale(identifier: "cs_CZ")
        return f
    }()
    let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    return ddMMyyyy.date(from: trimmed) ?? yyyyMMdd.date(from: trimmed)
}

struct CalendarView: View {
    @EnvironmentObject private var authState: AuthState

    @State private var items: [OrderItemByInstallationDate] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let service = OrderItemsByInstallationDateService()

    /// Položky seskupené podle data instalace (datum -> položky), seřazené podle data.
    private var itemsByDate: [(date: Date, displayDate: String, items: [OrderItemByInstallationDate])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { item -> Date? in
            parseInstallationDate(item.installation_date)
        }
        .compactMapValues { $0 }
        return grouped
            .compactMap { key, value -> (Date, String, [OrderItemByInstallationDate])? in
                guard let d = key else { return nil }
                let startOfDay = calendar.startOfDay(for: d)
                let formatted = formatSectionDate(startOfDay)
                return (startOfDay, formatted, value.sorted { a, b in
                    (parseInstallationDate(a.installation_date) ?? .distantPast) < (parseInstallationDate(b.installation_date) ?? .distantPast)
                })
            }
            .sorted { $0.date < $1.date }
    }

    private func formatSectionDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        f.locale = Locale(identifier: "cs_CZ")
        return f.string(from: date)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                content
            }
            .navigationTitle("Kalendář")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileBarButton()
                }
            }
        }
        .task {
            await loadItems()
        }
        .refreshable {
            await loadItems()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && items.isEmpty {
            ProgressView("Načítám položky…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let msg = errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(msg)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Button("Zkusit znovu") {
                    Task { await loadItems() }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if itemsByDate.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Žádné položky s datem instalace")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(itemsByDate, id: \.date) { group in
                    Section {
                        ForEach(group.items) { item in
                            OrderItemRow(item: item)
                        }
                    } header: {
                        Text(group.displayDate)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.visible)
        }
    }

    private func loadItems() async {
        guard authState.authToken != nil else {
            await MainActor.run {
                errorMessage = "Pro zobrazení kalendáře se přihlaste."
            }
            return
        }
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            let fetched = try await service.fetchOrderItems(token: authState.authToken, installationDate: nil)
            await MainActor.run {
                items = fetched
                isLoading = false
            }
        } catch {
            await MainActor.run {
                items = []
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Jedna řádka položky v kalendáři (název, objednávka, cena, status).
private struct OrderItemRow: View {
    let item: OrderItemByInstallationDate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.item_name)
                .font(.headline)
            HStack {
                Text("Objednávka #\(item.order_id)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if item.base_price > 0 {
                    Text(Formatting.price(item.base_price))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if !item.status.isEmpty {
                Text(item.status)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Formátování ceny (použij existující helper, pokud máš)
private enum Formatting {
    static func price(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CZK"
        formatter.currencySymbol = "Kč"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value)) Kč"
    }
}

#Preview {
    CalendarView()
        .environmentObject(AuthState())
}
