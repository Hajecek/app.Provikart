//
//  CalendarView.swift
//  Provikart
//
//  Kalendář instalací – přehledný design ve stylu Domů / docházky.
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
    @State private var showAttendance = false
    private let service = OrderItemsByInstallationDateService()
    private let calendar = Calendar.current

    private let logoOrange = Color(red: 0.97, green: 0.58, blue: 0.12)

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

    private func relativeSectionHeader(for date: Date) -> String {
        if calendar.isDateInToday(date) { return "Dnes" }
        if calendar.isDateInTomorrow(date) { return "Zítra" }
        let dayMonth = DateFormatter()
        dayMonth.locale = Locale(identifier: "cs_CZ")
        dayMonth.dateFormat = "d. M."
        let weekday = DateFormatter()
        weekday.locale = Locale(identifier: "cs_CZ")
        weekday.dateFormat = "EEEE"
        let weekdayText = weekday.string(from: date)
        let capitalized = weekdayText.prefix(1).uppercased() + weekdayText.dropFirst()
        return "\(capitalized) \(dayMonth.string(from: date))"
    }

    private var selectedDayItems: [OrderItemByInstallationDate] {
        guard let date = selectedDate else { return [] }
        return items(for: date)
    }

    private var monthTitle: String {
        Self.monthTitleFormatter.string(from: selectedDate ?? Date()).capitalized
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    loadingView
                } else if let msg = errorMessage, items.isEmpty {
                    errorView(msg)
                } else if items.isEmpty {
                    emptyView
                } else {
                    mainContent
                }
            }
            .background {
                ZStack(alignment: .top) {
                    Color(uiColor: .systemGroupedBackground)
                    CalendarTopArchGlow()
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Kalendář")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    if !items.isEmpty {
                        Button("Dnes") {
                            let today = calendar.startOfDay(for: Date())
                            withAnimation(.snappy(duration: 0.22)) { selectedDate = today }
                        }
                    }
                    Button {
                        showAttendance = true
                    } label: {
                        Image(systemName: "person.badge.clock")
                    }
                    .accessibilityLabel("Otevřít docházku")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        DealwarsView()
                    } label: {
                        Image(systemName: "trophy")
                    }
                    ProfileBarButton()
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .overlay(alignment: .top) {
                if isLoading && !items.isEmpty {
                    ProgressView()
                        .padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 8)
                }
            }
        }
        .sheet(isPresented: $showAttendance) {
            UserAttendanceView()
                .environmentObject(authState)
        }
        .sheet(item: $selectedItem) { item in
            InstallationDetailSheet(item: item, selectedItem: $selectedItem)
        }
        .task { await loadItems() }
        .refreshable { await loadItems() }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Načítám kalendář…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ msg: String) -> some View {
        ContentUnavailableView {
            Label("Nepodařilo se načíst kalendář", systemImage: "exclamationmark.triangle")
        } description: {
            Text(msg)
        } actions: {
            Button("Zkusit znovu") { Task { await loadItems() } }
                .buttonStyle(.borderedProminent)
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

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                monthCard
                daySummaryCard
                installationsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }

    private var monthCard: some View {
        let base = selectedDate ?? Date()
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: base)) ?? base

        return VStack(spacing: 14) {
            HStack(spacing: 12) {
                monthStepButton(systemName: "chevron.left") {
                    if let prev = calendar.date(byAdding: .month, value: -1, to: firstOfMonth) {
                        withAnimation(.snappy(duration: 0.22)) { selectedDate = prev }
                    }
                }

                VStack(spacing: 2) {
                    Text(monthTitle)
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.numericText())
                    Text("\(daysWithItemsInSelectedMonth) dní s instalací")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                monthStepButton(systemName: "chevron.right") {
                    if let next = calendar.date(byAdding: .month, value: 1, to: firstOfMonth) {
                        withAnimation(.snappy(duration: 0.22)) { selectedDate = next }
                    }
                }
            }

            MonthGridView(
                monthDate: firstOfMonth,
                selectedDate: $selectedDate,
                calendar: calendar,
                daysWithItems: daysWithItems,
                accent: logoOrange
            )
        }
        .padding(16)
        .background(cardBackground(tint: logoOrange))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    let threshold: CGFloat = 50
                    if value.translation.width < -threshold,
                       let next = calendar.date(byAdding: .month, value: 1, to: firstOfMonth) {
                        withAnimation(.snappy(duration: 0.25)) { selectedDate = next }
                    } else if value.translation.width > threshold,
                              let prev = calendar.date(byAdding: .month, value: -1, to: firstOfMonth) {
                        withAnimation(.snappy(duration: 0.25)) { selectedDate = prev }
                    }
                }
        )
    }

    private var daysWithItemsInSelectedMonth: Int {
        let base = selectedDate ?? Date()
        return daysWithItems.filter { calendar.isDate($0, equalTo: base, toGranularity: .month) }.count
    }

    private var daySummaryCard: some View {
        let date = selectedDate ?? Date()
        let count = selectedDayItems.count
        let isToday = calendar.isDateInToday(date)

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(logoOrange.opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: count > 0 ? "calendar.badge.checkmark" : "calendar")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(logoOrange)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(relativeSectionHeader(for: date))
                    .font(.headline.weight(.bold))
                Text(
                    count == 0
                        ? "Žádné instalace na tento den"
                        : "\(count) \(installationsWord(count))"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isToday {
                Text("Dnes")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
        .padding(16)
        .background(cardBackground(tint: .blue))
    }

    private var installationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Instalace")
                    .font(.title3.weight(.bold))
                Spacer()
                Text("\(selectedDayItems.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .padding(.horizontal, 4)

            if selectedDayItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("Vyberte jiný den nebo přidejte položku")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(cardBackground(tint: .secondary))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(selectedDayItems) { item in
                        Button {
                            selectedItem = item
                        } label: {
                            InstallationCard(item: item, accent: logoOrange)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func monthStepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func cardBackground(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.14),
                                tint.opacity(0.05),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
    }

    private func installationsWord(_ count: Int) -> String {
        switch count {
        case 1: return "instalace"
        case 2...4: return "instalace"
        default: return "instalací"
        }
    }

    private static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    private func loadItems() async {
        guard authState.authToken != nil else {
            await MainActor.run { errorMessage = "Pro zobrazení kalendáře se přihlaste." }
            return
        }
        await MainActor.run {
            isLoading = true
            if items.isEmpty { errorMessage = nil }
        }
        do {
            let fetched = try await service.fetchOrderItems(token: authState.authToken, installationDate: nil)
            await MainActor.run {
                items = fetched
                isLoading = false
                errorMessage = nil
                WidgetDataStore.saveInstallations(items: fetched)
            }
            let today = calendar.startOfDay(for: Date())
            await MainActor.run {
                if selectedDate == nil {
                    selectedDate = today
                }
            }
        } catch {
            if error is CancellationError { return }
            if let url = error as? URLError, url.code == .cancelled { return }
            await MainActor.run {
                isLoading = false
                if items.isEmpty {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Arch glow

private struct CalendarTopArchGlow: View {
    private let logoOrange = Color(red: 0.97, green: 0.58, blue: 0.12)
    private let logoGold = Color(red: 0.98, green: 0.69, blue: 0.23)
    private let logoPurple = Color(red: 0.30, green: 0.05, blue: 0.22)

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height: CGFloat = 320

            ZStack(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: logoOrange.opacity(0.22), location: 0),
                        .init(color: logoGold.opacity(0.12), location: 0.4),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                LinearGradient(
                    colors: [logoPurple.opacity(0.08), .clear],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            }
            .frame(width: width, height: height)
            .mask {
                CalendarTopArchShape()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white.opacity(0.55), location: 0.7),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .frame(height: 320)
    }
}

private struct CalendarTopArchShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.58))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.maxY * 0.58),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Mřížka měsíce

private struct MonthGridView: View {
    let monthDate: Date
    @Binding var selectedDate: Date?
    let calendar: Calendar
    let daysWithItems: Set<Date>
    var accent: Color = .accentColor

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

    private var firstWeekdayOffset: Int {
        let w = calendar.component(.weekday, from: monthStart)
        return (w - 2 + 7) % 7
    }

    private var weekdaySymbols: [String] {
        let syms = Self.czechCalendar.shortWeekdaySymbols
        return [1, 2, 3, 4, 5, 6, 0].map { syms[$0] }
    }

    private var gridDays: [Int?] {
        var out: [Int?] = Array(repeating: nil, count: firstWeekdayOffset)
        for d in 1...numberOfDays { out.append(d) }
        while out.count < 42 { out.append(nil) }
        return out
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            let days = gridDays
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { col in
                        let idx = row * 7 + col
                        let dayOpt = idx < days.count ? days[idx] : nil
                        dayCell(dayOpt: dayOpt)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(dayOpt: Int?) -> some View {
        if let day = dayOpt,
           let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
            let isSelected = selectedDate.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
            let isToday = calendar.isDateInToday(date)
            let hasItems = daysWithItems.contains(calendar.startOfDay(for: date))

            Button {
                withAnimation(.snappy(duration: 0.2)) { selectedDate = date }
            } label: {
                VStack(spacing: 3) {
                    ZStack {
                        if isSelected {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [accent, accent.opacity(0.82)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: accent.opacity(0.35), radius: 6, y: 2)
                        } else if isToday {
                            Circle()
                                .stroke(accent, lineWidth: 2)
                        }

                        Text("\(day)")
                            .font(.subheadline.weight(isSelected || isToday ? .bold : .medium))
                            .foregroundStyle(isSelected ? .white : (isToday ? accent : .primary))
                    }
                    .frame(width: 34, height: 34)

                    Circle()
                        .fill(hasItems ? (isSelected ? Color.white.opacity(0.9) : accent) : Color.clear)
                        .frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(day)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityValue(hasItems ? "Má instalace" : "Bez instalací")
        } else {
            Color.clear
                .frame(height: 44)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Karta instalace

private struct InstallationCard: View {
    let item: OrderItemByInstallationDate
    var accent: Color = .accentColor

    private var timeText: String? {
        let t = item.installation_time?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 44, height: 44)
            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.item_name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text("Obj. \(item.displayOrderNumber)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    if let timeText {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Label(timeText, systemImage: "clock")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                }

                HStack(spacing: 8) {
                    if item.base_price > 0 {
                        Text(Formatting.price(item.base_price))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                    if !item.status.isEmpty {
                        Text(item.status)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        )
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
