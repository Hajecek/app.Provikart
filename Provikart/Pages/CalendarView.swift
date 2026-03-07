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
            .navigationTitle(Self.monthTitleFormatter.string(from: selectedDate ?? Date()).capitalized)
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
                        if !items.isEmpty {
                            Button("Dnes") {
                                let today = calendar.startOfDay(for: Date())
                                withAnimation(.easeInOut(duration: 0.22)) { selectedDate = today }
                            }
                        }
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
                monthGridSection
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

    // MARK: - Měsíční mřížka

    private var monthGridSection: some View {
        let base = selectedDate ?? Date()
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: base)) ?? base
        return VStack(spacing: 12) {
            HStack {
                Button {
                    if let prev = calendar.date(byAdding: .month, value: -1, to: firstOfMonth) {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedDate = prev }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                }
                Spacer()
                Button {
                    if let next = calendar.date(byAdding: .month, value: 1, to: firstOfMonth) {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedDate = next }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                }
            }
            MonthGridView(
                monthDate: firstOfMonth,
                selectedDate: $selectedDate,
                calendar: calendar,
                daysWithItems: daysWithItems
            )
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    let threshold: CGFloat = 50
                    if value.translation.width < -threshold, let next = calendar.date(byAdding: .month, value: 1, to: firstOfMonth) {
                        withAnimation(.easeInOut(duration: 0.25)) { selectedDate = next }
                    } else if value.translation.width > threshold, let prev = calendar.date(byAdding: .month, value: -1, to: firstOfMonth) {
                        withAnimation(.easeInOut(duration: 0.25)) { selectedDate = prev }
                    }
                }
        )
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
                WidgetDataStore.saveInstallations(items: fetched)
            }
            // Nastavení selectedDate v dalším run loopu, aby nedocházelo k rekurzi v layoutu
            // (List + LazyVGrid při současné změně items a selectedDate na macOS).
            let today = calendar.startOfDay(for: Date())
            await MainActor.run {
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

// MARK: - Mřížka celého měsíce

private struct MonthGridView: View {
    let monthDate: Date
    @Binding var selectedDate: Date?
    let calendar: Calendar
    /// Dny, které mají alespoň jednu instalaci (pro tečku v buňce). Set místo closure kvůli stabilnímu layoutu.
    let daysWithItems: Set<Date>

    private static var czechCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "cs_CZ")
        return c
    }

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: monthDate)) ?? monthDate
    }

    private var numberOfDays: Int {
        calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 31
    }

    /// První den v týdnu: 1 = neděle (Apple), pro zobrazení Po první je offset (weekday - 2 + 7) % 7
    private var firstWeekdayOffset: Int {
        let w = calendar.component(.weekday, from: monthStart)
        return (w - 2 + 7) % 7
    }

    /// Po, Út, St, Čt, Pá, So, Ne (česky, pondělí první)
    private var weekdaySymbols: [String] {
        let syms = Self.czechCalendar.shortWeekdaySymbols
        return [1, 2, 3, 4, 5, 6, 0].map { syms[$0] }
    }

    /// Buňky pro mřížku: nil = prázdné, 1...31 = den v měsíci
    private var gridDays: [Int?] {
        var out: [Int?] = Array(repeating: nil, count: firstWeekdayOffset)
        for d in 1...numberOfDays { out.append(d) }
        while out.count < 42 { out.append(nil) }
        return out
    }

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, dayOpt in
                    if let day = dayOpt,
                       let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                        let isSelected = selectedDate.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
                        let isToday = calendar.isDateInToday(date)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedDate = date }
                        } label: {
                            ZStack {
                                if isSelected {
                                    Circle().fill(Color.accentColor)
                                } else if isToday {
                                    Circle().stroke(Color.accentColor, lineWidth: 2)
                                }
                                Text("\(day)")
                                    .font(.caption)
                                    .fontWeight(isSelected || isToday ? .semibold : .regular)
                                    .foregroundColor(isSelected ? .white : (isToday ? Color.accentColor : .primary))
                                if daysWithItems.contains(calendar.startOfDay(for: date)) && !isSelected {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 4, height: 4)
                                        .offset(x: 10, y: -10)
                                }
                            }
                            .frame(height: 32)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear
                            .frame(height: 32)
                    }
                }
            }
        }
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
