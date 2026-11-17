//
//  ManagerPerformanceCompareView.swift
//  Provikart
//
//  Detail obchodníka ve Výkonu: posun oproti minulému měsíci (jako na webu).
//  Kumulativní křivky obou měsíců, „o X služeb výš/níž ke dni N“,
//  přejetí prstem po dnech a nejdelší pauza.
//

import SwiftUI
import Charts
import UIKit

struct ManagerPerformanceCompareRoute: Identifiable {
    let user: ManagerPerformanceUser
    var id: Int { user.userId }
}

struct ManagerPerformanceCompareView: View {
    let user: ManagerPerformanceUser
    let displayName: String
    let monthDate: Date
    let isCurrentMonth: Bool
    let todayKey: String
    let token: String?

    @State private var previousUser: ManagerPerformanceUser?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var reveal: CGFloat = 0
    @State private var countUp: Double = 0
    @State private var selectedDay: Int?
    @State private var showPrevious = true
    @State private var showCurrent = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let service = ManagerTeamPerformanceService()
    private let blue = Color(red: 0.36, green: 0.60, blue: 0.95)
    private var gray: Color { scheme == .dark ? Color(white: 0.62) : Color(white: 0.55) }
    private var up: Color { scheme == .dark ? Color(red: 0.42, green: 0.85, blue: 0.62) : Color(red: 0.13, green: 0.6, blue: 0.36) }
    private var down: Color { scheme == .dark ? Color(red: 1.0, green: 0.55, blue: 0.48) : Color(red: 0.78, green: 0.25, blue: 0.16) }

    // MARK: - Kalendář

    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }()

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let apiMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private static let monthName: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.dateFormat = "LLLL"
        return f
    }()

    private var previousMonthDate: Date {
        Self.calendar.date(byAdding: .month, value: -1, to: monthDate) ?? monthDate
    }

    private func daysIn(_ date: Date) -> Int {
        Self.calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    private func key(for day: Int, in month: Date) -> String {
        var comps = Self.calendar.dateComponents([.year, .month], from: month)
        comps.day = day
        guard let date = Self.calendar.date(from: comps) else { return "" }
        return Self.keyFormatter.string(from: date)
    }

    private func value(_ user: ManagerPerformanceUser?, day: Int, month: Date) -> Int {
        guard let entry = user?.performance[key(for: day, in: month)] else { return 0 }
        return entry.servicesCount ?? (entry.breakdown ?? entry.autoBreakdown)?.total ?? 0
    }

    /// Den, ke kterému srovnáváme (dnes u aktuálního měsíce, jinak poslední den).
    private var referenceDay: Int {
        if isCurrentMonth, let date = Self.keyFormatter.date(from: todayKey) {
            return Self.calendar.component(.day, from: date)
        }
        return daysIn(monthDate)
    }

    private func cumulative(_ user: ManagerPerformanceUser?, month: Date, upTo last: Int) -> [Int] {
        var sum = 0
        return (1...max(1, last)).map { day in
            sum += value(user, day: day, month: month)
            return sum
        }
    }

    private var currentSeries: [Int] { cumulative(user, month: monthDate, upTo: referenceDay) }
    private var previousSeries: [Int] { cumulative(previousUser, month: previousMonthDate, upTo: daysIn(previousMonthDate)) }

    private var currentNow: Int { currentSeries.last ?? 0 }
    private var previousSame: Int {
        let series = previousSeries
        guard !series.isEmpty else { return 0 }
        return series[min(series.count, referenceDay) - 1]
    }
    private var previousTotal: Int { previousSeries.last ?? 0 }
    private var diff: Int { currentNow - previousSame }

    private var currentName: String { Self.monthName.string(from: monthDate) }
    private var previousName: String { Self.monthName.string(from: previousMonthDate) }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else {
                        headline
                        tiles
                        legend
                        chart
                        footer
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Zavřít")
                }
            }
            .task { await loadPrevious() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayName)
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text("Minulý měsíc a tento · počet služeb")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var headline: some View {
        let tint: Color = diff > 0 ? up : (diff < 0 ? down : .secondary)
        let magnitude = abs(diff)
        let word = serviceWord(magnitude)
        let direction = diff > 0 ? "výš" : "níž"
        return HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 8) {
                Image(systemName: diff > 0 ? "arrow.up.right" : (diff < 0 ? "arrow.down.right" : "equal"))
                    .font(.title2.weight(.bold))
                CountingText(value: Double(magnitude) * countUp) { n in
                    diff == 0 ? "stejně jako minule" : "o \(n) \(word) \(direction)"
                }
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            .foregroundStyle(tint)
            Spacer(minLength: 8)
            Text("ke \(referenceDay). dni")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var tiles: some View {
        HStack(spacing: 10) {
            tile(currentNow, isCurrentMonth ? "\(currentName) teď" : "\(currentName) celkem", highlighted: true)
            tile(previousSame, "\(previousName) ke \(referenceDay). dni", highlighted: false)
            tile(previousTotal, "\(previousName) celkem", highlighted: false)
        }
    }

    private func tile(_ value: Int, _ title: String, highlighted: Bool) -> some View {
        return VStack(alignment: .leading, spacing: 4) {
            CountingText(value: Double(value) * countUp) { "\($0)" }
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(
            (highlighted ? blue.opacity(0.14) : Color.primary.opacity(0.05)),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(blue.opacity(0.5), lineWidth: 1)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 8) {
            legendToggle(previousName.capitalized, gray, isOn: $showPrevious)
            legendToggle(currentName.capitalized, blue, isOn: $showCurrent)
        }
    }

    private func legendToggle(_ title: String, _ color: Color, isOn: Binding<Bool>) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.snappy(duration: 0.25)) { isOn.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 8) {
                Capsule().fill(color).frame(width: 18, height: 4)
                Text(title).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isOn.wrappedValue ? color : Color.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(color.opacity(isOn.wrappedValue ? 0.14 : 0.04), in: Capsule())
            .opacity(isOn.wrappedValue ? 1 : 0.55)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Graf

    private struct Point: Identifiable {
        let series: String
        let day: Int
        let value: Int
        var id: String { "\(series)-\(day)" }
    }

    private var chart: some View {
        let current = currentSeries.enumerated().map { Point(series: "current", day: $0.offset + 1, value: $0.element) }
        let previous = previousSeries.enumerated().map { Point(series: "previous", day: $0.offset + 1, value: $0.element) }
        let lastDay = max(daysIn(monthDate), daysIn(previousMonthDate))
        let peak = max(1, max(currentNow, previousTotal))
        let ticks = Array(Set([1, 5, 10, 15, 20, 25, 30, lastDay, referenceDay].filter { $0 <= lastDay })).sorted()
        let selected = selectedDay.map { min(max(1, $0), lastDay) }

        return VStack(alignment: .leading, spacing: 10) {
            selectionInfo(selected)
                .frame(minHeight: 40, alignment: .leading)

            Chart {
                if showPrevious {
                    ForEach(previous) { point in
                        LineMark(x: .value("Den", point.day), y: .value("Služby", point.value), series: .value("Řada", "previous"))
                            .foregroundStyle(gray)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                    }
                    if let last = previous.last {
                        PointMark(x: .value("Den", last.day), y: .value("Služby", last.value))
                            .foregroundStyle(gray)
                            .symbolSize(40)
                    }
                }
                if showCurrent {
                    ForEach(current) { point in
                        AreaMark(x: .value("Den", point.day), y: .value("Služby", point.value), series: .value("Řada", "current"))
                            .foregroundStyle(LinearGradient(colors: [blue.opacity(0.35), blue.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Den", point.day), y: .value("Služby", point.value), series: .value("Řada", "current"))
                            .foregroundStyle(blue)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                    }
                }

                RuleMark(x: .value("Den", referenceDay))
                    .foregroundStyle(blue.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 4]))

                if showCurrent {
                    PointMark(x: .value("Den", referenceDay), y: .value("Služby", currentNow))
                        .foregroundStyle(blue)
                        .symbolSize(90)
                }
                if showPrevious {
                    PointMark(x: .value("Den", referenceDay), y: .value("Služby", previousSame))
                        .foregroundStyle(gray)
                        .symbolSize(60)
                }

                if let day = selected {
                    RuleMark(x: .value("Den", day))
                        .foregroundStyle(Color.primary.opacity(0.25))
                }
            }
            .chartXSelection(value: $selectedDay)
            .chartXScale(domain: 1...lastDay)
            .chartYScale(domain: 0...Double(peak) * 1.1)
            .chartXAxis {
                AxisMarks(values: ticks) { value in
                    AxisValueLabel {
                        if let day = value.as(Int.self) {
                            Text(day == referenceDay && isCurrentMonth ? "dnes" : "\(day)")
                                .font(.caption2.weight(day == referenceDay ? .bold : .medium))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text("\(Int(number))").font(.caption2.monospacedDigit())
                        }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: selectedDay)
            .frame(height: 260)
            .mask(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle().frame(width: max(0, geo.size.width * reveal))
                }
            }
        }
    }

    @ViewBuilder
    private func selectionInfo(_ day: Int?) -> some View {
        if let day {
            let cur = day <= currentSeries.count ? currentSeries[day - 1] : nil
            let prev = day <= previousSeries.count ? previousSeries[day - 1] : nil
            HStack(spacing: 12) {
                Text("\(day). den")
                    .font(.subheadline.weight(.bold))
                if let cur {
                    infoChip(currentName, "\(cur)", "+\(value(user, day: day, month: monthDate))", blue)
                }
                if let prev {
                    infoChip(previousName, "\(prev)", "+\(value(previousUser, day: day, month: previousMonthDate))", gray)
                }
                Spacer(minLength: 0)
                if let cur, let prev {
                    let d = cur - prev
                    Text(d > 0 ? "+\(d)" : "\(d)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(d > 0 ? up : (d < 0 ? down : .secondary))
                }
            }
        } else {
            Label("Přejeď prstem po grafu pro konkrétní den", systemImage: "hand.draw")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func infoChip(_ month: String, _ total: String, _ dayValue: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(total).font(.subheadline.weight(.bold).monospacedDigit())
            Text(dayValue).font(.caption2.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
        .accessibilityLabel("\(month): \(total)")
    }

    // MARK: - Pauzy

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if loadFailed {
                Label("Minulý měsíc se nepodařilo načíst.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if let text = pauseText(previousUser, month: previousMonthDate, upTo: daysIn(previousMonthDate), monthWord: "V \(locative(previousMonthDate))") {
                insight(text, icon: "pause.circle")
            }
            if let text = pauseText(user, month: monthDate, upTo: referenceDay, monthWord: isCurrentMonth ? "Tento měsíc" : "V \(locative(monthDate))") {
                insight(text, icon: "pause.circle.fill")
            }
        }
    }

    private func insight(_ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Nejdelší řada dnů bez služby (min. 2 dny).
    private func pauseText(_ user: ManagerPerformanceUser?, month: Date, upTo last: Int, monthWord: String) -> String? {
        guard user != nil, last > 0 else { return nil }
        var best = (start: 0, length: 0)
        var runStart = 0
        var runLength = 0
        for day in 1...last {
            if value(user, day: day, month: month) == 0 {
                if runLength == 0 { runStart = day }
                runLength += 1
                if runLength > best.length { best = (runStart, runLength) }
            } else {
                runLength = 0
            }
        }
        guard best.length >= 2 else { return nil }
        let end = best.start + best.length - 1
        return "\(monthWord) byla nejdelší pauza \(best.length) \(dayWord(best.length)) (\(best.start).–\(end).)."
    }

    private func locative(_ date: Date) -> String {
        let names = ["lednu", "únoru", "březnu", "dubnu", "květnu", "červnu", "červenci", "srpnu", "září", "říjnu", "listopadu", "prosinci"]
        return names[Self.calendar.component(.month, from: date) - 1]
    }

    private func dayWord(_ n: Int) -> String {
        if n == 1 { return "den" }
        if n >= 2 && n <= 4 { return "dny" }
        return "dní"
    }

    private func serviceWord(_ n: Int) -> String {
        if n == 1 { return "službu" }
        if n >= 2 && n <= 4 { return "služby" }
        return "služeb"
    }

    // MARK: - Načtení

    private func loadPrevious() async {
        defer { isLoading = false; playIntro() }
        guard let token, !token.isEmpty else { loadFailed = true; return }
        do {
            let payload = try await service.fetchPerformance(token: token, month: Self.apiMonth.string(from: previousMonthDate))
            previousUser = payload.users.first { $0.userId == user.userId }
        } catch {
            loadFailed = true
        }
    }

    private func playIntro() {
        guard !reduceMotion else {
            reveal = 1
            countUp = 1
            return
        }
        reveal = 0
        countUp = 0
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.easeOut(duration: 1.2)) { reveal = 1 }
            withAnimation(.spring(response: 0.9, dampingFraction: 0.9)) { countUp = 1 }
        }
    }
}

/// Text, který při animaci plynule „napočítá“ číslo.
private struct CountingText: View, Animatable {
    var value: Double
    let format: (Int) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(Int(value.rounded())))
    }
}
