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
    @State private var displayedMonth: Date = Date()
    @State private var selectedDate: Date?

    private let service = OrderItemsByInstallationDateService()
    private let calendar = Calendar.current

    /// Množina dnů (start of day), které mají alespoň jednu instalaci.
    private var daysWithItems: Set<Date> {
        let set = Set(items.compactMap { parseInstallationDate($0.installation_date) })
        return Set(set.map { calendar.startOfDay(for: $0) })
    }

    /// Položky pro vybraný den (nebo prázdné, pokud nic není vybráno).
    private func items(for date: Date) -> [OrderItemByInstallationDate] {
        let start = calendar.startOfDay(for: date)
        return items.filter {
            guard let d = parseInstallationDate($0.installation_date) else { return false }
            return calendar.isDate(d, inSameDayAs: start)
        }
        .sorted { (a, b) in
            (parseInstallationDate(a.installation_date) ?? .distantPast) < (parseInstallationDate(b.installation_date) ?? .distantPast)
        }
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
            errorContent(msg)
        } else if items.isEmpty {
            emptyContent
        } else {
            calendarContent
        }
    }

    private func errorContent(_ msg: String) -> some View {
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
    }

    private var emptyContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Žádné položky s datem instalace")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var calendarContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Kalendářní mřížka
                monthCalendarCard

                // Seznam instalací pro vybraný den
                selectedDaySection
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Měsíční kalendář (iOS styl – mřížka s tečkami)

    private var monthCalendarCard: some View {
        VStack(spacing: 16) {
            // Nadpis měsíce + předchozí / další
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
                Spacer()
                Text(monthYearString(displayedMonth))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 8)

            // Názvy dnů v týdnu (Po–Ne)
            let weekdaySymbols = shortWeekdaySymbols
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Mřížka dnů
            let days = daysInDisplayedMonth()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 10) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, cell in
                    // capture date once for clarity
                    let cellDate = cell.date
                    DayCell(
                        day: cell.day,
                        hasInstallation: cellDate.map { daysWithItems.contains($0) } ?? false,
                        // Fix: avoid using $1 in single-arg closure; compare selectedDate to the captured cellDate
                        isSelected: {
                            guard let cellDate, let selectedDate else { return false }
                            return calendar.isDate(selectedDate, inSameDayAs: cellDate)
                        }(),
                        isToday: cellDate.map { calendar.isDateInToday($0) } ?? false
                    ) {
                        if let d = cellDate {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDate = d
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
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
        // firstWeekday: 1 = neděle, 2 = pondělí
        let first = calendar.firstWeekday - 1
        if first > 0 {
            symbols = Array(symbols[first...]) + Array(symbols[..<first])
        }
        return symbols
    }

    /// Buňky pro zobrazený měsíc: (day: číslo dne nebo nil, date: start of day nebo nil).
    private func daysInDisplayedMonth() -> [(day: Int?, date: Date?)] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) else {
            return []
        }
        let numberOfDays = range.count
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7
        var result: [(Int?, Date?)] = []
        for _ in 0..<offset {
            result.append((nil, nil))
        }
        for day in 1...numberOfDays {
            if let date = calendar.date(bySetting: .day, value: day, of: firstDay) {
                result.append((day, calendar.startOfDay(for: date)))
            } else {
                result.append((day, nil))
            }
        }
        let total = 42
        while result.count < total {
            result.append((nil, nil))
        }
        return Array(result.prefix(total))
    }

    // MARK: - Sekce „Instalace v tento den“

    private var selectedDaySection: some View {
        Group {
            if let date = selectedDate {
                let dayItems = items(for: date)
                if dayItems.isEmpty {
                    VStack(spacing: 8) {
                        Text("V tento den nemáte naplánované instalace")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 24)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(formatSectionDate(date))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        LazyVStack(spacing: 0) {
                            ForEach(dayItems) { item in
                                OrderItemRow(item: item)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                                if item.id != dayItems.last?.id {
                                    Divider()
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 16)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Text("Vyberte den v kalendáři")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 24)
                }
                .frame(maxWidth: .infinity)
            }
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
                if selectedDate == nil, let firstDate = Set(fetched.compactMap { parseInstallationDate($0.installation_date) }).min() {
                    let start = calendar.startOfDay(for: firstDate)
                    selectedDate = start
                    displayedMonth = start
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

// MARK: - Buňka jednoho dne v mřížce

private struct DayCell: View {
    let day: Int?
    let hasInstallation: Bool
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if let d = day {
                    Text("\(d)")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(isToday ? .bold : .regular)
                        .foregroundStyle(foregroundColor)
                    if hasInstallation {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 5, height: 5)
                    } else {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 5, height: 5)
                    }
                } else {
                    Text(" ")
                        .font(.body)
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(day == nil)
    }

    private var foregroundColor: Color {
        if isSelected { return .white }
        if isToday { return Color.accentColor }
        return .primary
    }

    private var backgroundColor: Color {
        if isSelected { return Color.accentColor }
        if isToday { return Color.accentColor.opacity(0.15) }
        return Color.clear
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
                Text("Objednávka \(item.displayOrderNumber)")
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

// MARK: - Formátování ceny

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
