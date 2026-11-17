//
//  ManagerHeatmapBuilder.swift
//  Provikart
//
//  Složí heatmapu „Aktivita po dnech“ z dat Výkonu týmu (manager_performance.php),
//  když ji přehled (manager_overview.php) zatím neposílá. Výpočet odpovídá webu:
//  týdny po–ne, úroveň 1–4 podle maxima, součty po dnech v týdnu, detail dne.
//  Stejně jako web bere jen automatický rozpad z objednávek (auto_breakdown) –
//  bez ručních přepisů – a jen obchodníky (manažery a adminy vynechá).
//

import Foundation

enum ManagerHeatmapBuilder {
    /// Stejně jako web: data a sytost barev za 26 týdnů…
    static let weeks = 26
    /// …a zobrazené okno jako web na střední šířce (14 týdnů).
    static let visibleWeeks = 14

    private static let dayNames = ["Pondělí", "Úterý", "Středa", "Čtvrtek", "Pátek", "Sobota", "Neděle"]
    private static let monthShort = ["Led", "Úno", "Bře", "Dub", "Kvě", "Čvn", "Čvc", "Srp", "Zář", "Říj", "Lis", "Pro"]
    private static let categories: [(key: String, label: String, color: String, value: (ManagerPerformanceBreakdown) -> Int)] = [
        ("internet", "Internet", "#5aa6ec", { $0.internet }),
        ("postpaid", "Neo+", "#a9d636", { $0.postpaid }),
        ("oneplay", "OnePlay", "#f27d5f", { $0.oneplay }),
        ("family", "Family", "#a78bfa", { $0.family }),
        ("transfer", "Přenos", "#9ca29c", { $0.transfer })
    ]

    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = .current
        return cal
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f
    }()

    /// První den heatmapy (pondělí před `weeks - 1` týdny).
    static func startDate(today: Date = Date()) -> Date {
        let cal = calendar
        let todayStart = cal.startOfDay(for: today)
        let weekday = cal.component(.weekday, from: todayStart) // 1 = neděle
        let offsetToMonday = (weekday + 5) % 7
        let monday = cal.date(byAdding: .day, value: -offsetToMonday, to: todayStart) ?? todayStart
        return cal.date(byAdding: .day, value: -7 * (weeks - 1), to: monday) ?? monday
    }

    /// Měsíce (yyyy-MM), které heatmapa pokrývá – pro načtení Výkonu.
    static func monthsToFetch(today: Date = Date()) -> [String] {
        let cal = calendar
        var out: [String] = []
        var cursor = cal.date(from: cal.dateComponents([.year, .month], from: startDate(today: today))) ?? today
        let end = today
        while cursor <= end {
            out.append(monthFormatter.string(from: cursor))
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }

    static func build(
        from payloads: [ManagerTeamPerformancePayload],
        excludingUserIds excluded: Set<Int> = [],
        today: Date = Date()
    ) -> ManagerOverviewHeatmap {
        let cal = calendar
        let todayStart = cal.startOfDay(for: today)
        let start = startDate(today: today)

        // Součty po dnech, po kategoriích a po lidech.
        var byDay: [String: Int] = [:]
        var byDayCat: [String: [String: Int]] = [:]
        var byDayUser: [String: [String: Int]] = [:]
        for payload in payloads {
            for user in payload.users where !excluded.contains(user.userId) {
                let name = displayName(user)
                for (day, entry) in user.performance {
                    // Jako web: součet kategorií z objednávek, ruční zápis se nepočítá.
                    guard let breakdown = entry.autoBreakdown else { continue }
                    let count = breakdown.total
                    guard count > 0 else { continue }
                    byDay[day, default: 0] += count
                    byDayUser[day, default: [:]][name, default: 0] += count
                    for cat in categories {
                        let value = cat.value(breakdown)
                        if value > 0 { byDayCat[day, default: [:]][cat.key, default: 0] += value }
                    }
                }
            }
        }

        var weeksOut: [[ManagerOverviewHeatmap.Cell]] = []
        var months: [ManagerOverviewHeatmap.Month] = []
        var weekdayTotals = Array(repeating: 0, count: 7)
        var weekdayDays = Array(repeating: 0, count: 7)
        var total = 0
        var maxCount = 0
        var lastMonth: Int?

        // Nejdřív maximum a součet v rozsahu.
        for offset in 0..<(weeks * 7) {
            guard let date = cal.date(byAdding: .day, value: offset, to: start), date <= todayStart else { continue }
            let count = byDay[dayFormatter.string(from: date)] ?? 0
            maxCount = Swift.max(maxCount, count)
            total += count
        }

        for week in 0..<weeks {
            var column: [ManagerOverviewHeatmap.Cell] = []
            for day in 0..<7 {
                let date = cal.date(byAdding: .day, value: week * 7 + day, to: start) ?? start
                let key = dayFormatter.string(from: date)
                let future = date > todayStart
                let count = future ? 0 : (byDay[key] ?? 0)
                var level = 0
                if count > 0, maxCount > 0 {
                    level = Swift.max(1, Swift.min(4, Int((Double(count) / Double(maxCount) * 4).rounded(.up))))
                }
                if !future {
                    weekdayTotals[day] += count
                    weekdayDays[day] += 1
                }
                column.append(.init(date: key, count: count, level: level, future: future))
            }
            let month = cal.component(.month, from: cal.date(byAdding: .day, value: week * 7, to: start) ?? start)
            if month != lastMonth {
                months.append(.init(col: week, label: monthShort[month - 1]))
                lastMonth = month
            }
            weeksOut.append(column)
        }

        // Detail aktivních dnů.
        let activeKeys = weeksOut.flatMap { $0 }.filter { !$0.future && $0.count > 0 }
        let ranked = activeKeys.sorted { $0.count > $1.count }
        var rankOf: [String: Int] = [:]
        for (index, cell) in ranked.enumerated() { rankOf[cell.date] = index + 1 }

        var days: [String: ManagerOverviewHeatmap.Day] = [:]
        for column in weeksOut {
            for (dayIndex, cell) in column.enumerated() where !cell.future && cell.count > 0 {
                let cats = categories.compactMap { cat -> ManagerOverviewHeatmap.Count? in
                    let value = byDayCat[cell.date]?[cat.key] ?? 0
                    return value > 0 ? .init(key: cat.key, name: cat.label, color: cat.color, count: value) : nil
                }
                .sorted { $0.count > $1.count }
                let people = (byDayUser[cell.date] ?? [:])
                    .map { ManagerOverviewHeatmap.Count(key: nil, name: $0.key, color: nil, count: $0.value) }
                    .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
                let avg = weekdayDays[dayIndex] > 0 ? Double(weekdayTotals[dayIndex]) / Double(weekdayDays[dayIndex]) : 0
                let date = dayFormatter.date(from: cell.date) ?? start
                let title = "\(dayNames[dayIndex]) \(cal.component(.day, from: date)). \(cal.component(.month, from: date)). \(cal.component(.year, from: date))"
                days[cell.date] = .init(
                    title: title,
                    total: cell.count,
                    cats: cats,
                    people: people,
                    weekdayAvg: (avg * 10).rounded() / 10,
                    rank: rankOf[cell.date] ?? 0,
                    activeDays: activeKeys.count,
                    share: total > 0 ? Int((Double(cell.count) / Double(total) * 100).rounded()) : 0
                )
            }
        }

        var bestIndex = 0
        var bestAvg = 0.0
        for index in 0..<7 {
            let avg = weekdayDays[index] > 0 ? Double(weekdayTotals[index]) / Double(weekdayDays[index]) : 0
            if avg > bestAvg {
                bestAvg = avg
                bestIndex = index
            }
        }

        return ManagerOverviewHeatmap(
            weeks: weeksOut,
            months: months,
            total: total,
            max: maxCount,
            bestWeekday: bestAvg > 0 ? dayNames[bestIndex] : "",
            bestWeekdayAvg: (bestAvg * 10).rounded() / 10,
            weekdayTotals: weekdayTotals,
            days: days
        )
    }

    /// Okno posledních `count` týdnů – součty, měsíce a nejsilnější den
    /// se přepočítají jen za okno (jako na webu), úrovně barev zůstávají z celé řady.
    static func window(_ heat: ManagerOverviewHeatmap, lastWeeks count: Int = visibleWeeks) -> ManagerOverviewHeatmap {
        guard heat.weeks.count > count else { return heat }
        let from = heat.weeks.count - count
        let weeks = Array(heat.weeks[from...])
        var totals = Array(repeating: 0, count: 7)
        var dayCounts = Array(repeating: 0, count: 7)
        var total = 0
        for column in weeks {
            for (index, cell) in column.enumerated() where index < 7 && !cell.future {
                totals[index] += cell.count
                dayCounts[index] += 1
                total += cell.count
            }
        }
        var months: [ManagerOverviewHeatmap.Month] = []
        var lastMonth: String?
        for (index, column) in weeks.enumerated() {
            guard let first = column.first else { continue }
            let month = String(first.date.dropFirst(5).prefix(2))
            if month != lastMonth, let number = Int(month), (1...12).contains(number) {
                months.append(.init(col: index, label: monthShort[number - 1]))
                lastMonth = month
            }
        }
        var bestIndex = 0
        var bestAvg = 0.0
        for index in 0..<7 {
            let avg = dayCounts[index] > 0 ? Double(totals[index]) / Double(dayCounts[index]) : 0
            if avg > bestAvg {
                bestAvg = avg
                bestIndex = index
            }
        }
        return ManagerOverviewHeatmap(
            weeks: weeks,
            months: months,
            total: total,
            max: heat.max,
            bestWeekday: bestAvg > 0 ? dayNames[bestIndex] : "",
            bestWeekdayAvg: (bestAvg * 10).rounded() / 10,
            weekdayTotals: totals,
            days: heat.days
        )
    }

    private static func displayName(_ user: ManagerPerformanceUser) -> String {
        let name = user.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let full = "\(user.firstname ?? "") \(user.lastname ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty { return full }
        if let username = user.username, !username.isEmpty { return "@\(username)" }
        return "#\(user.userId)"
    }
}
