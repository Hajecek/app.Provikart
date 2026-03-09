//
//  StatisticsView.swift
//  Provikart
//
//  Statistiky prodejů – nativní iOS vzhled: souhrn, grafy, detail.
//  Vyžaduje iOS 16+ (Swift Charts).
//

import SwiftUI
import Charts

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

private enum ProductCategory: String, CaseIterable, Hashable {
    case postpaid = "Postpaid"
    case family = "Family"
    case internet = "Internet"
    case oneplay = "Oneplay"
    case ostatni = "Ostatní"

    var displayName: String { rawValue }
    var icon: String {
        switch self {
        case .postpaid: return "phone.fill"
        case .family: return "person.3.fill"
        case .internet: return "wifi"
        case .oneplay: return "tv.fill"
        case .ostatni: return "square.grid.2x2"
        }
    }

    static func from(itemType: String?) -> ProductCategory? {
        guard let raw = itemType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else { return nil }
        switch raw {
        case "postpaid": return .postpaid
        case "i_family", "i family", "ifamily": return .family
        case "internet": return .internet
        case "televize", "oneplay": return .oneplay
        case "pevna_linka": return .ostatni
        default: return nil
        }
    }
}

private struct SoldItemGroup: Identifiable, Hashable {
    let id: String
    let itemName: String
    let count: Int
    let totalBasePrice: Double
}

private func categoryFromItemName(_ name: String) -> ProductCategory {
    let lower = name.lowercased()
    if lower.contains("i family") || lower.contains("ifamily") { return .family }
    if lower.contains("postpaid") || lower.contains("předplacen") || lower.contains("tarif") ||
       lower.contains("mobil") || lower.contains("paušál") || lower.contains("sim ") ||
       lower.contains("sim.") || lower.contains("karta") { return .postpaid }
    if lower.contains("internet") || lower.contains("připojení") || lower.contains("wifi") ||
       lower.contains("optik") || lower.contains("pevná linka") || lower.contains(" net ") { return .internet }
    if lower.contains("televize") || lower.contains("oneplay") || lower.contains(" tv ") || lower.contains("tv ") ||
       lower.contains("příjem") || lower.contains("set-top") || lower.contains("set top") ||
       lower.contains("decoder") || lower.contains("receiv") { return .oneplay }
    return .ostatni
}

private func monthYear(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "cs_CZ")
    f.dateFormat = "LLLL yyyy"
    return f.string(from: date).capitalized
}

// MARK: - Datové pomocné struktury pro grafy

private struct CategoryMonthlyValue: Identifiable, Hashable {
    var id: String { category.rawValue }
    let monthStart: Date
    let category: ProductCategory
    let value: Double
}

private enum Metric: String, CaseIterable, Identifiable {
    case count = "Počet"
    case revenue = "Tržba"

    var id: String { rawValue }
    var displayName: String { rawValue }
}

private func colorForCategory(_ category: ProductCategory) -> Color {
    switch category {
    case .postpaid: return .blue
    case .family: return .purple
    case .internet: return .teal
    case .oneplay: return .orange
    case .ostatni: return .gray
    }
}

// MARK: - View

struct StatisticsView: View {
    @EnvironmentObject private var authState: AuthState

    @State private var items: [OrderItemByInstallationDate] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedMonth: Date = Date()
    @State private var selectedMetric: Metric = .count

    private let service = OrderItemsByInstallationDateService()
    private let calendar = Calendar.current

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth
    }

    private var itemsInMonth: [OrderItemByInstallationDate] {
        items.filter { item in
            guard let d = parseInstallationDate(item.installation_date) else { return false }
            return calendar.isDate(d, equalTo: monthStart, toGranularity: .month)
        }
    }

    private var groupedByCategory: [ProductCategory: [SoldItemGroup]] {
        var byCategoryAndName: [ProductCategory: [String: (Int, Double)]] = [:]
        for cat in ProductCategory.allCases { byCategoryAndName[cat] = [:] }
        for item in itemsInMonth {
            let cat = ProductCategory.from(itemType: item.item_type) ?? categoryFromItemName(item.item_name)
            let name = item.item_name.isEmpty ? "—" : item.item_name
            var t = byCategoryAndName[cat]![name] ?? (0, 0)
            t.0 += 1
            t.1 += item.revenueForStats  // zapojená provize (commission_earned), ne base_price
            byCategoryAndName[cat]![name] = t
        }
        return byCategoryAndName.mapValues { dict in
            dict.map { SoldItemGroup(id: $0.key, itemName: $0.key, count: $0.value.0, totalBasePrice: $0.value.1) }
                .sorted { lhs, rhs in
                    if selectedMetric == .count {
                        if lhs.count != rhs.count { return lhs.count > rhs.count }
                    } else {
                        if lhs.totalBasePrice != rhs.totalBasePrice { return lhs.totalBasePrice > rhs.totalBasePrice }
                    }
                    return lhs.itemName.localizedCompare(rhs.itemName) == .orderedAscending
                }
        }
    }

    private var detailOrder: [ProductCategory] {
        let main: [ProductCategory] = [.postpaid, .family, .internet, .oneplay]
        let hasOther = (groupedByCategory[.ostatni] ?? []).isEmpty == false
        return main + (hasOther ? [.ostatni] : [])
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(monthStart, equalTo: Date(), toGranularity: .month)
    }

    private func count(for cat: ProductCategory) -> Int {
        (groupedByCategory[cat] ?? []).reduce(0) { $0 + $1.count }
    }

    private func revenue(for cat: ProductCategory) -> Double {
        (groupedByCategory[cat] ?? []).reduce(0) { $0 + $1.totalBasePrice }
    }

    private var totalCountInMonth: Int {
        itemsInMonth.count
    }

    private var totalRevenueInMonth: Double {
        itemsInMonth.reduce(0) { $0 + $1.revenueForStats }
    }

    // MARK: - Graf: rozložení v měsíci (sloupce)

    private var categoryDistributionForSelectedMonth: [CategoryMonthlyValue] {
        var result: [CategoryMonthlyValue] = []
        for cat in ProductCategory.allCases {
            if cat == .ostatni { continue }
            let value: Double = selectedMetric == .count ? Double(count(for: cat)) : revenue(for: cat)
            result.append(CategoryMonthlyValue(monthStart: monthStart, category: cat, value: value))
        }
        let other = selectedMetric == .count ? Double(count(for: .ostatni)) : revenue(for: .ostatni)
        if other > 0 {
            result.append(CategoryMonthlyValue(monthStart: monthStart, category: .ostatni, value: other))
        }
        return result
    }

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ContentUnavailableView {
                    Label("Načítám…", systemImage: "chart.bar")
                } description: {
                    Text("Statistiky se načítají")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let msg = errorMessage {
                ContentUnavailableView {
                    Label("Chyba", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(msg)
                } actions: {
                    Button("Zkusit znovu") { Task { await loadItems() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Statistiky")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Metrika", selection: $selectedMetric) {
                    ForEach(Metric.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 180, maxWidth: 220)
            }
            ToolbarItem(placement: .topBarTrailing) {
                ProfileBarButton()
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await loadItems() }
        .refreshable { await loadItems() }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthBar
                summaryCard
                chartsBlock
                detailBlock
            }
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.visible)
    }

    // MARK: - Month bar

    private var monthBar: some View {
        HStack(spacing: 0) {
            Button {
                if let prev = calendar.date(byAdding: .month, value: -1, to: monthStart) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedMonth = prev
                    }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(monthYear(monthStart))
                .font(.headline)
                .frame(maxWidth: .infinity)

            Button {
                guard let next = calendar.date(byAdding: .month, value: 1, to: monthStart),
                      next <= calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date() else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedMonth = next
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.medium))
                    .foregroundStyle(isCurrentMonth ? Color(uiColor: .tertiaryLabel) : Color.accentColor)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isCurrentMonth)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Summary Card (přehledné řádky)

    private var summaryCard: some View {
        VStack(spacing: 0) {
            // Nadpis
            HStack {
                Text("Souhrn")
                    .font(.headline)
                Spacer()
            }
            .padding(16)

            Divider()
                .padding(.horizontal, 16)

            // Celkem
            HStack(alignment: .firstTextBaseline) {
                if selectedMetric == .count {
                    Text("\(totalCountInMonth)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                } else {
                    Text(price(totalRevenueInMonth))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                }
                Text(selectedMetric == .count ? "ks celkem" : "celková tržba")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(16)

            Divider()
                .padding(.horizontal, 16)

            // 4 kategorie jako řádky
            VStack(spacing: 0) {
                SummaryRow(category: .postpaid, value: metricValue(for: .postpaid), metric: selectedMetric)
                Divider().padding(.leading, 56)
                SummaryRow(category: .family, value: metricValue(for: .family), metric: selectedMetric)
                Divider().padding(.leading, 56)
                SummaryRow(category: .internet, value: metricValue(for: .internet), metric: selectedMetric)
                Divider().padding(.leading, 56)
                SummaryRow(category: .oneplay, value: metricValue(for: .oneplay), metric: selectedMetric)
            }
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func metricValue(for category: ProductCategory) -> Double {
        switch selectedMetric {
        case .count: return Double(count(for: category))
        case .revenue: return revenue(for: category)
        }
    }

    // MARK: - Charts

    @ViewBuilder
    private var chartsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Přehled")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            // Sloupcový graf: rozložení v měsíci
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Kategorie v měsíci")
                        .font(.headline)
                    Spacer()
                    let caption = selectedMetric == .count
                        ? "\(itemsInMonth.count) položek"
                        : price(totalRevenueInMonth)
                    if !itemsInMonth.isEmpty {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                Chart(categoryDistributionForSelectedMonth) { row in
                    BarMark(
                        x: .value("Kategorie", row.category.displayName),
                        y: .value(selectedMetric.displayName, row.value)
                    )
                    .foregroundStyle(colorForCategory(row.category))
                    .annotation(position: .top, alignment: .center) {
                        if row.value > 0 {
                            Text(selectedMetric == .count ? "\(Int(row.value))" : shortPrice(row.value))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartLegend(.automatic)
                .frame(height: 220)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
        }
    }

    private func shortMonth(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.dateFormat = "LLL"
        return f.string(from: date).capitalized
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detail")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            if itemsInMonth.isEmpty {
                Text("V tomto měsíci nemáte žádné prodané položky.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                ForEach(detailOrder, id: \.self) { cat in
                    let groups = groupedByCategory[cat] ?? []
                    if !groups.isEmpty {
                        DetailSection(category: cat, groups: groups, metric: selectedMetric)
                            .animation(nil, value: selectedMetric)
                    }
                }
            }
        }
    }

    private func loadItems() async {
        guard authState.authToken != nil else {
            await MainActor.run { errorMessage = "Pro zobrazení statistik se přihlaste." }
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
                isLoading = false
                let isCancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                if isCancelled {
                    errorMessage = nil
                } else {
                    items = []
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func price(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "CZK"
        f.currencySymbol = "Kč"
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(Int(value)) Kč"
    }

    private func shortPrice(_ value: Double) -> String {
        if value >= 1_000_000 {
            return "\(Int(value / 1_000))k Kč"
        } else if value >= 10_000 {
            return "\(Int(value / 1_000))k Kč"
        } else {
            return "\(Int(value)) Kč"
        }
    }
}

// MARK: - Shrnutí (řádek: ikona + název + hodnota)

private struct SummaryRow: View {
    let category: ProductCategory
    let value: Double
    let metric: Metric

    var body: some View {
        let accent = colorForCategory(category)
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: category.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
            }

            Text(category.displayName)
                .font(.body.weight(.medium))

            Spacer(minLength: 8)

            Text(metric == .count ? "\(Int(value))" : formatPrice(value))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func formatPrice(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "CZK"
        f.currencySymbol = "Kč"
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(Int(value)) Kč"
    }
}

// MARK: - Sekce detailu

private struct DetailSection: View {
    let category: ProductCategory
    let groups: [SoldItemGroup]
    let metric: Metric

    private var headerTotal: String {
        switch metric {
        case .count:
            let c = groups.reduce(0) { $0 + $1.count }
            return "\(c)×"
        case .revenue:
            let r = groups.reduce(0.0) { $0 + $1.totalBasePrice }
            return price(r)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                Text(category.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(headerTotal)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.itemName)
                                .font(.body)
                            if metric == .revenue, group.totalBasePrice > 0 {
                                Text(price(group.totalBasePrice))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Text(metric == .count ? "\(group.count)×" : price(group.totalBasePrice))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))

                    if index < groups.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 20)
    }

    private func price(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "CZK"
        f.currencySymbol = "Kč"
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(Int(value)) Kč"
    }
}

#Preview {
    NavigationStack {
        StatisticsView()
            .environmentObject(AuthState())
    }
}
