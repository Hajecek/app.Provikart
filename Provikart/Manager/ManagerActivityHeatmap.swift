//
//  ManagerActivityHeatmap.swift
//  Provikart
//
//  „Aktivita po dnech“ – heatmapa služeb jako na webovém přehledu.
//  Týdny jsou sloupce, po–ne řádky, vpravo součet za den v týdnu.
//

import SwiftUI
import UIKit

struct ManagerHeatmapDayRoute: Identifiable, Hashable {
    let date: String
    var id: String { date }
}

struct ManagerActivityHeatmapGrid: View {
    let heatmap: ManagerOverviewHeatmap
    let tint: Color
    let onSelect: (ManagerOverviewHeatmap.Cell) -> Void

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let dayLabels = ["Po", "Út", "St", "Čt", "Pá", "So", "Ne"]
    private let gap: CGFloat = 3
    private let labelWidth: CGFloat = 22
    private let sumWidth: CGFloat = 30

    private var todayKey: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private var bestWeekdayIndex: Int? {
        guard let peak = heatmap.weekdayTotals.max(), peak > 0 else { return nil }
        return heatmap.weekdayTotals.firstIndex(of: peak)
    }

    var body: some View {
        GeometryReader { geo in
            let columns = max(1, heatmap.weeks.count)
            let available = geo.size.width - labelWidth - sumWidth - gap * 2
            let cell = max(6, (available - gap * CGFloat(columns - 1)) / CGFloat(columns))
            let maxSum = max(1, heatmap.weekdayTotals.max() ?? 1)
            let today = todayKey

            VStack(alignment: .leading, spacing: gap) {
                // Měsíce nad sloupci.
                ZStack(alignment: .topLeading) {
                    ForEach(Array(heatmap.months.enumerated()), id: \.offset) { _, month in
                        Text(month.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .offset(x: labelWidth + gap + CGFloat(month.col) * (cell + gap))
                    }
                    Text("Celkem")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: sumWidth + 6, alignment: .trailing)
                        .offset(x: geo.size.width - sumWidth - 6)
                }
                .frame(height: 14, alignment: .topLeading)

                ForEach(0..<7, id: \.self) { day in
                    HStack(spacing: gap) {
                        Text(Self.dayLabels[day])
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: labelWidth, alignment: .leading)

                        ForEach(Array(heatmap.weeks.enumerated()), id: \.offset) { week, column in
                            if day < column.count {
                                cellView(column[day], week: week, day: day, size: cell, today: today)
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }

                        let sum = day < heatmap.weekdayTotals.count ? heatmap.weekdayTotals[day] : 0
                        let isBest = day == bestWeekdayIndex
                        Text("\(sum)")
                            .font(.system(size: 11, weight: isBest ? .heavy : .semibold).monospacedDigit())
                            .foregroundStyle(isBest ? tint : Color.secondary)
                            .frame(width: sumWidth, alignment: .trailing)
                            .background(alignment: .trailing) {
                                Capsule()
                                    .fill(tint.opacity(isBest ? 0.18 : 0.08))
                                    .frame(width: sumWidth * CGFloat(sum) / CGFloat(maxSum) * (shown ? 1 : 0), height: cell * 0.7)
                            }
                    }
                    .frame(height: cell)
                }
            }
        }
        .frame(height: gridHeight)
        .onAppear {
            guard !shown else { return }
            if reduceMotion {
                shown = true
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { shown = true }
            }
        }
    }

    /// Výška mřížky odvozená od šířky obrazovky (buňky jsou čtverce).
    private var gridHeight: CGFloat {
        let width = UIScreen.main.bounds.width - 32 - 36
        let columns = CGFloat(max(1, heatmap.weeks.count))
        let available = width - labelWidth - sumWidth - gap * 2
        let cell = max(6, (available - gap * (columns - 1)) / columns)
        return 14 + gap + 7 * cell + 6 * gap
    }

    @ViewBuilder
    private func cellView(_ cell: ManagerOverviewHeatmap.Cell, week: Int, day: Int, size: CGFloat, today: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: max(2, size * 0.22), style: .continuous)
        if cell.future {
            shape
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                .frame(width: size, height: size)
        } else {
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                onSelect(cell)
            } label: {
                shape
                    .fill(fill(for: cell.level))
                    .overlay {
                        if cell.date == today {
                            shape.strokeBorder(Color.primary.opacity(0.75), lineWidth: 1.5)
                        }
                    }
                    .frame(width: size, height: size)
                    .scaleEffect(shown ? 1 : 0.2)
                    .opacity(shown ? 1 : 0)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.7)
                            .delay(Double(week) * 0.018 + Double(day) * 0.03),
                        value: shown
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(cell.date): \(cell.count) služeb")
        }
    }

    private func fill(for level: Int) -> Color {
        switch level {
        case 1: return tint.opacity(0.28)
        case 2: return tint.opacity(0.5)
        case 3: return tint.opacity(0.75)
        case 4: return tint
        default: return Color.primary.opacity(0.07)
        }
    }
}

/// Legenda „Méně ▢▢▢▢▢ Více“.
struct ManagerHeatmapLegend: View {
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            Text("Méně")
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(level == 0 ? Color.primary.opacity(0.07) : tint.opacity([0, 0.28, 0.5, 0.75, 1][level]))
                    .frame(width: 10, height: 10)
            }
            Text("Více")
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
    }
}

/// Detail jednoho dne z heatmapy.
struct ManagerHeatmapDayView: View {
    let date: String
    let count: Int
    let detail: ManagerOverviewHeatmap.Day?
    let tint: Color

    @Environment(\.dismiss) private var dismiss
    @State private var reveal: CGFloat = 0

    private var title: String {
        if let title = detail?.title, !title.isEmpty { return title }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let parsed = parser.date(from: date) else { return date }
        let out = DateFormatter()
        out.locale = Locale(identifier: "cs_CZ")
        out.dateFormat = "EEEE d. M. yyyy"
        return out.string(from: parsed).capitalized
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(detail?.total ?? count)")
                            .font(.system(size: 52, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(serviceWord(detail?.total ?? count))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    if let detail {
                        HStack(spacing: 10) {
                            tile("Pořadí dne", detail.rank > 0 ? "\(detail.rank). z \(detail.activeDays)" : "—")
                            tile("Průměr dne v týdnu", String(format: "%.1f", detail.weekdayAvg).replacingOccurrences(of: ".", with: ","))
                            tile("Podíl", "\(detail.share) %")
                        }
                        if !detail.cats.isEmpty {
                            section("Podle služeb", rows: detail.cats, colored: true)
                        }
                        if !detail.people.isEmpty {
                            section("Podle obchodníků", rows: detail.people, colored: false)
                        }
                    } else {
                        Text("Tento den tým nedokončil žádnou službu.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Zavřít")
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.1)) { reveal = 1 }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func serviceWord(_ n: Int) -> String {
        if n == 1 { return "služba" }
        if n >= 2 && n <= 4 { return "služby" }
        return "služeb"
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(value)
                .font(.headline.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func section(_ title: String, rows: [ManagerOverviewHeatmap.Count], colored: Bool) -> some View {
        let peak = max(1, rows.map(\.count).max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline.weight(.semibold))
            ForEach(rows) { row in
                let color = colored ? (row.color.map { Color(heatHex: $0) } ?? tint) : tint
                HStack(spacing: 10) {
                    if colored {
                        Circle().fill(color).frame(width: 9, height: 9)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.07))
                                Capsule()
                                    .fill(color)
                                    .frame(width: geo.size.width * CGFloat(row.count) / CGFloat(peak) * reveal)
                            }
                        }
                        .frame(height: 4)
                    }
                    Text("\(row.count)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .frame(minWidth: 26, alignment: .trailing)
                }
            }
        }
    }
}

private extension Color {
    init(heatHex hex: String) {
        var raw = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if raw.count == 3 {
            raw = raw.map { "\($0)\($0)" }.joined()
        }
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
