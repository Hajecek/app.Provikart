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

struct CalendarView: View {
    @EnvironmentObject private var authState: AuthState

    @State private var items: [OrderItemByInstallationDate] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var displayedMonth: Date = Date()
    @State private var selectedDate: Date?

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
        .sorted { (parseInstallationDate($0.installation_date) ?? .distantPast) < (parseInstallationDate($1.installation_date) ?? .distantPast) }
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
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileBarButton()
                }
            }
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
            Text("Položky s datem instalace se zde zobrazí.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Hlavní List (iOS inset group style)

    private var mainList: some View {
        List {
            Section {
                monthGrid
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if let date = selectedDate {
                Section {
                    let dayItems = items(for: date)
                    if dayItems.isEmpty {
                        HStack {
                            Spacer()
                            Text("V tento den nemáte naplánované instalace")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(dayItems) { item in
                            InstallationListRow(item: item)
                        }
                    }
                } header: {
                    Text(formatSectionDate(date))
                }
            } else {
                Section {
                    HStack {
                        Spacer()
                        Text("Vyberte den v kalendáři")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.visible)
    }

    // MARK: - Mřížka měsíce (jako v Kalendáři)

    private var monthGrid: some View {
        VStack(spacing: 16) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundColor(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                Spacer()
                Text(monthYearString(displayedMonth))
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundColor(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 0) {
                ForEach(shortWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            let days = daysInDisplayedMonth()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, cell in
                    let cellDate = cell.date
                    DayCell(
                        day: cell.day,
                        hasInstallation: cellDate.map { daysWithItems.contains($0) } ?? false,
                        isSelected: cellDate.flatMap { d in selectedDate.map { calendar.isDate(d, inSameDayAs: $0) } } ?? false,
                        isToday: cellDate.map { calendar.isDateInToday($0) } ?? false
                    ) {
                        if let d = cellDate {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedDate = d }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func monthYearString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        f.locale = Locale(identifier: "cs_CZ")
        return f.string(from: date).capitalized
    }

    private var shortWeekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.dateFormat = "EEEEE"
        var symbols: [String] = []
        for i in 1...7 {
            guard let date = calendar.date(bySetting: .weekday, value: i, of: Date()) else { continue }
            symbols.append(formatter.string(from: date))
        }
        let first = calendar.firstWeekday - 1
        if first > 0 { symbols = Array(symbols[first...]) + Array(symbols[..<first]) }
        return symbols
    }

    private func daysInDisplayedMonth() -> [(day: Int?, date: Date?)] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) else {
            return []
        }
        let numberOfDays = range.count
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7
        var result: [(Int?, Date?)] = []
        for _ in 0..<offset { result.append((nil, nil)) }
        for day in 1...numberOfDays {
            if let date = calendar.date(bySetting: .day, value: day, of: firstDay) {
                result.append((day, calendar.startOfDay(for: date)))
            } else {
                result.append((day, nil))
            }
        }
        while result.count < 42 { result.append((nil, nil)) }
        return Array(result.prefix(42))
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
                    displayedMonth = today
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

// MARK: - Buňka dne (jako v aplikaci Kalendář)

private struct DayCell: View {
    let day: Int?
    let hasInstallation: Bool
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if let d = day {
                    ZStack {
                        if isSelected {
                            Circle()
                                .fill(Color.accentColor)
                        } else if isToday {
                            Circle()
                                .stroke(Color.accentColor, lineWidth: 2)
                        }
                        Text("\(d)")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(isSelected || isToday ? .semibold : .regular)
                            .foregroundColor(isSelected ? .white : (isToday ? Color.accentColor : .primary))
                    }
                    .frame(width: 32, height: 32)
                    if hasInstallation {
                        Circle()
                            .fill(isSelected ? Color.white.opacity(0.8) : Color.accentColor)
                            .frame(width: 4, height: 4)
                    } else {
                        Color.clear.frame(height: 4)
                    }
                } else {
                    Color.clear.frame(height: 36)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(.borderless)
        .disabled(day == nil)
    }
}

// MARK: - Řádek v Listu (nativní styl)

private struct InstallationListRow: View {
    let item: OrderItemByInstallationDate

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.item_name)
                .font(.body)
            Text("Objednávka \(item.displayOrderNumber)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
        .padding(.vertical, 2)
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
