//
//  OrdersView.swift
//  Provikart
//
//  Seznam objednávek (položky s datem instalace).
//

import SwiftUI

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

private func sortDate(for item: OrderItemByInstallationDate) -> Date {
    guard let day = parseInstallationDate(item.installation_date) else { return .distantPast }
    guard let timeStr = item.installation_time, !timeStr.isEmpty else { return day }
    let parts = timeStr.split(separator: ":")
    guard parts.count >= 2,
          let h = Int(parts[0]), let m = Int(parts[1]),
          (0..<24).contains(h), (0..<60).contains(m) else { return day }
    return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
}

private func formatSectionDate(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateStyle = .long
    f.timeStyle = .none
    f.locale = Locale(identifier: "cs_CZ")
    return f.string(from: date)
}

private func relativeSectionHeader(for date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) {
        return "Dnes"
    }
    if cal.isDateInTomorrow(date) {
        return "Zítra"
    }
    let dayMonth = DateFormatter()
    dayMonth.locale = Locale(identifier: "cs_CZ")
    dayMonth.dateFormat = "d. M."
    let weekday = DateFormatter()
    weekday.locale = Locale(identifier: "cs_CZ")
    weekday.dateFormat = "EEEE"
    let weekdayLower = weekday.string(from: date).lowercased()
    return "\(weekdayLower) \(dayMonth.string(from: date))"
}

struct OrdersView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.openAddSheet) private var openAddSheet

    @State private var items: [OrderItemByInstallationDate] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedItem: OrderItemByInstallationDate?
    private let service = OrderItemsByInstallationDateService()
    private let calendar = Calendar.current

    private var sortedDates: [Date] {
        let dates = Set(items.compactMap { parseInstallationDate($0.installation_date) }.map { calendar.startOfDay(for: $0) })
        return dates.sorted()
    }

    private func items(for date: Date) -> [OrderItemByInstallationDate] {
        let start = calendar.startOfDay(for: date)
        return items.filter {
            guard let d = parseInstallationDate($0.installation_date) else { return false }
            return calendar.isDate(d, inSameDayAs: start)
        }
        .sorted { sortDate(for: $0) < sortDate(for: $1) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView("Načítám…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let msg = errorMessage {
                    errorView(msg)
                } else if items.isEmpty {
                    emptyView
                } else {
                    mainList
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Objednávky")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 16) {
                        NavigationLink {
                            StatisticsView()
                                .environmentObject(authState)
                                .environment(\.openAddSheet, openAddSheet)
                        } label: {
                            Image(systemName: "chart.bar")
                        }
                        NavigationLink {
                            ProblemsView()
                                .environmentObject(authState)
                                .environment(\.openAddSheet, openAddSheet)
                        } label: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if openAddSheet != nil {
                        Button {
                            openAddSheet?()
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                    ProfileBarButton()
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .sheet(item: $selectedItem) { item in
            OrderItemDetailSheet(item: item, selectedItem: $selectedItem)
        }
        .task { await loadItems() }
        .refreshable { await loadItems() }
    }

    private func errorView(_ msg: String) -> some View {
        ContentUnavailableView {
            Label("Chyba", systemImage: "exclamationmark.triangle")
        } description: {
            Text(msg)
        } actions: {
            Button("Zkusit znovu") { Task { await loadItems() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("Žádné objednávky", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("Jakmile budete mít položky s datem instalace, objeví se zde.")
        } actions: {
            if openAddSheet != nil {
                Button("Přidat položku") { openAddSheet?() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mainList: some View {
        List {
            ForEach(sortedDates, id: \.self) { date in
                Section {
                    ForEach(items(for: date)) { item in
                        Button {
                            selectedItem = item
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                OrdersListRow(item: item)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(relativeSectionHeader(for: date))
                        .textCase(nil)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(calendar.isDateInToday(date) ? Color.accentColor : Color.primary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.visible)
    }

    private func loadItems() async {
        guard authState.authToken != nil else {
            await MainActor.run { errorMessage = "Pro zobrazení objednávek se přihlaste." }
            return
        }
        await MainActor.run { isLoading = true; errorMessage = nil }
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

// MARK: - Řádek objednávky

private struct OrdersListRow: View {
    let item: OrderItemByInstallationDate

    private var timeAndOrder: String {
        var parts: [String] = ["Obj. \(item.displayOrderNumber)"]
        if let t = item.installation_time, !t.isEmpty { parts.append(t) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.item_name)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            Text(timeAndOrder)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if item.base_price > 0 || !item.status.isEmpty {
                HStack(spacing: 8) {
                    if item.base_price > 0 {
                        Text(OrdersViewFormatting.price(item.base_price))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if !item.status.isEmpty {
                        Text(item.status)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail položky (sheet)

private struct OrderItemDetailSheet: View {
    let item: OrderItemByInstallationDate
    @Binding var selectedItem: OrderItemByInstallationDate?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Položka", value: item.item_name)
                    LabeledContent("Objednávka", value: item.displayOrderNumber)
                    if let type = item.item_type, !type.isEmpty {
                        LabeledContent("Typ", value: type)
                    }
                }
                Section("Instalace") {
                    LabeledContent("Datum", value: formatInstallationDate(item.installation_date))
                    if let time = item.installation_time, !time.isEmpty {
                        LabeledContent("Čas", value: time)
                    }
                }
                Section("Ceny") {
                    LabeledContent("Základní cena", value: OrdersViewFormatting.price(item.base_price))
                    if item.discount != 0 {
                        LabeledContent("Sleva", value: OrdersViewFormatting.price(item.discount))
                    }
                    LabeledContent("Provize", value: OrdersViewFormatting.price(item.commission))
                }
                if !item.status.isEmpty {
                    Section {
                        LabeledContent("Stav", value: item.status)
                    }
                }
            }
            .navigationTitle(item.item_name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") {
                        selectedItem = nil
                        dismiss()
                    }
                }
            }
            .onDisappear {
                selectedItem = nil
            }
        }
    }

    private func formatInstallationDate(_ raw: String) -> String {
        guard let date = parseInstallationDate(raw) else { return raw }
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        f.locale = Locale(identifier: "cs_CZ")
        return f.string(from: date)
    }
}

private enum OrdersViewFormatting {
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
    OrdersView()
        .environmentObject(AuthState())
}
