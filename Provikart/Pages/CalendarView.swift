//
//  CalendarView.swift
//  Provikart
//
//  Kalendář instalací – nativní iOS vzhled.
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

/// Vrací datum + čas pro řazení (pokud je installation_time, přidá ho k datu).
private func sortDate(for item: OrderItemByInstallationDate) -> Date {
    guard let day = parseInstallationDate(item.installation_date) else { return .distantPast }
    guard let timeStr = item.installation_time, !timeStr.isEmpty else { return day }
    let parts = timeStr.split(separator: ":")
    guard parts.count >= 2,
          let h = Int(parts[0]), let m = Int(parts[1]),
          (0..<24).contains(h), (0..<60).contains(m) else { return day }
    return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
}

struct CalendarView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.openAddSheet) private var openAddSheet

    @State private var items: [OrderItemByInstallationDate] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedDate: Date?
    @State private var selectedItem: OrderItemByInstallationDate?

    private let service = OrderItemsByInstallationDateService()
    private let calendar = Calendar.current

    private var daysWithItems: Set<Date> {
        Set(items.compactMap { parseInstallationDate($0.installation_date) }.map { calendar.startOfDay(for: $0) })
    }

    private func items(for date: Date) -> [OrderItemByInstallationDate] {
        let start = calendar.startOfDay(for: date)
        return items.filter {
            guard let d = parseInstallationDate($0.installation_date) else { return false }
            return calendar.isDate(d, inSameDayAs: start)
        }
        .sorted { sortDate(for: $0) < sortDate(for: $1) }
    }

    private func formatSectionDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        f.locale = Locale(identifier: "cs_CZ")
        return f.string(from: date)
    }

    /// Nadpis sekce ve stylu iOS Kalendáře: "Dnes", "Zítra" nebo "v sobotu 7. 3."
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

    private func dateHeaderColor(for date: Date) -> Color {
        if calendar.isDateInToday(date) { return Color.accentColor }
        return Color.primary
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
            .navigationTitle("Kalendář")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        StatisticsView()
                            .environmentObject(authState)
                            .environment(\.openAddSheet, openAddSheet)
                    } label: {
                        Image(systemName: "chart.bar")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let openAddSheet {
                        Button {
                            openAddSheet()
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
            InstallationDetailSheet(item: item, selectedItem: $selectedItem)
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
            Label("Žádné instalace", systemImage: "calendar.badge.clock")
        } description: {
            Text("Jakmile budete mít položky s datem instalace, objeví se zde.")
        } actions: {
            if openAddSheet != nil {
                Button("Přidat položku") { openAddSheet?() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Hlavní obsah (přehledný iOS design)

    private static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    private var mainList: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(Self.monthTitleFormatter.string(from: selectedDate ?? Date()).capitalized)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    weekStrip
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
            .listRowSeparator(.hidden)

            if let date = selectedDate {
                Section {
                    let dayItems = items(for: date)
                    if dayItems.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                            Text("Žádné instalace na tento den")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(dayItems) { item in
                            Button {
                                selectedItem = item
                            } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    InstallationListRow(item: item)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text(relativeSectionHeader(for: date))
                        .textCase(nil)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(dateHeaderColor(for: date))
                } footer: {
                    if !items(for: date).isEmpty {
                        Text("Klepněte na položku pro detail")
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.visible)
    }

    // MARK: - Pás dnů (vždy zahrnuje dnes i vybraný den)

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.dateFormat = "EEEEE"
        return f
    }()

    private func daysForStrip() -> [(weekdaySymbol: String, day: Int, date: Date)] {
        let today = calendar.startOfDay(for: Date())
        let selected = selectedDate ?? today
        let from = calendar.date(byAdding: .day, value: -10, to: min(today, selected)) ?? today
        let to = calendar.date(byAdding: .day, value: 16, to: max(today, selected)) ?? selected
        var result: [(String, Int, Date)] = []
        var d = calendar.startOfDay(for: from)
        while d <= to {
            result.append((
                Self.weekdayFormatter.string(from: d),
                calendar.component(.day, from: d),
                d
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return result
    }

    private var weekStrip: some View {
        let days = daysForStrip()
        let selectedIdx = selectedDate.flatMap { sel in days.firstIndex { calendar.isDate($0.date, inSameDayAs: sel) } } ?? 0
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(days.enumerated()), id: \.offset) { idx, cell in
                        DayCell(
                            weekday: cell.weekdaySymbol,
                            day: cell.day,
                            isSelected: selectedDate.map { calendar.isDate(cell.date, inSameDayAs: $0) } ?? false,
                            isToday: calendar.isDateInToday(cell.date)
                        ) {
                            withAnimation(.easeInOut(duration: 0.22)) { selectedDate = cell.date }
                            proxy.scrollTo(idx, anchor: .center)
                        }
                        .id(idx)
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 58)
            .onAppear { proxy.scrollTo(selectedIdx, anchor: .center) }
        }
    }

    private func loadItems() async {
        guard authState.authToken != nil else {
            await MainActor.run { errorMessage = "Pro zobrazení kalendáře se přihlaste." }
            return
        }
        await MainActor.run { isLoading = true; errorMessage = nil }
        do {
            let fetched = try await service.fetchOrderItems(token: authState.authToken, installationDate: nil)
            await MainActor.run {
                items = fetched
                isLoading = false
                let today = calendar.startOfDay(for: Date())
                if selectedDate == nil {
                    selectedDate = today
                }
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

// MARK: - Buňka dne (iOS styl – přehledná, přívětivá)

private struct DayCell: View {
    let weekday: String
    let day: Int
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(weekday)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                ZStack {
                    if isSelected {
                        Circle().fill(Color.accentColor)
                    } else if isToday {
                        Circle().stroke(Color.accentColor, lineWidth: 2)
                    }
                    Text("\(day)")
                        .font(.body)
                        .fontWeight(isSelected || isToday ? .semibold : .regular)
                        .foregroundColor(isSelected ? .white : (isToday ? Color.accentColor : .primary))
                }
                .frame(width: 36, height: 36)
                Group {
                    if isSelected {
                        Circle().fill(Color.accentColor).frame(width: 4, height: 4)
                    } else if isToday {
                        Text("Dnes").font(.caption2).fontWeight(.medium).foregroundStyle(Color.accentColor)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 14)
            }
            .frame(width: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sheet s detailem instalace

private struct InstallationDetailSheet: View {
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
                    LabeledContent("Základní cena", value: Formatting.price(item.base_price))
                    if item.discount != 0 {
                        LabeledContent("Sleva", value: Formatting.price(item.discount))
                    }
                    LabeledContent("Provize", value: Formatting.price(item.commission))
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

// MARK: - Řádek instalace (přehledný, iOS styl)

private struct InstallationListRow: View {
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
                        Text(Formatting.price(item.base_price))
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
