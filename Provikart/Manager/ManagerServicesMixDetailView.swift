//
//  ManagerServicesMixDetailView.swift
//  Provikart
//
//  Detail rozpadu služeb – po kliknutí na kategorii v přehledu.
//  Stejná data jako modal na webu (services_mix_detail).
//

import SwiftUI
import Charts

struct ManagerServicesMixRoute: Identifiable, Hashable {
    /// nil = všechny služby
    let key: String?
    var id: String { key ?? "__all__" }
}

struct ManagerServicesMixDetailView: View {
    let slices: [ManagerOverviewServiceSlice]
    let detail: ManagerOverviewMixDetail?
    let periodLabel: String
    let periodPhrase: String
    let onOpenPerformance: () -> Void

    @State private var selectedKey: String?
    @State private var reveal: CGFloat = 0
    @Namespace private var tabAnimation
    @Environment(\.dismiss) private var dismiss

    private let accent = Color(red: 0.99, green: 0.745, blue: 0.19)

    init(
        slices: [ManagerOverviewServiceSlice],
        detail: ManagerOverviewMixDetail?,
        initialKey: String?,
        periodLabel: String,
        periodPhrase: String,
        onOpenPerformance: @escaping () -> Void
    ) {
        self.slices = slices
        self.detail = detail
        self.periodLabel = periodLabel
        self.periodPhrase = periodPhrase
        self.onOpenPerformance = onOpenPerformance
        _selectedKey = State(initialValue: initialKey)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    tabs
                    stats
                    timeline
                    people
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .navigationTitle(selectedSlice?.label ?? "Rozpad na služby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Výkon týmu") {
                        dismiss()
                        onOpenPerformance()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Zavřít")
                }
            }
            .onAppear { replay() }
            .onChange(of: selectedKey) { _, _ in replay() }
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Data

    private var selectedSlice: ManagerOverviewServiceSlice? {
        guard let selectedKey else { return nil }
        return slices.first { $0.key == selectedKey }
    }

    private var tint: Color {
        selectedSlice.map { Color(mixHex: $0.color) } ?? accent
    }

    private func value(_ map: [String: Int]) -> Int {
        if let selectedKey { return map[selectedKey] ?? 0 }
        return map.values.reduce(0, +)
    }

    private var currentCount: Int {
        if let slice = selectedSlice { return slice.count }
        return slices.reduce(0) { $0 + $1.count }
    }

    private var previousCount: Int? {
        guard let cats = detail?.cats, !cats.isEmpty else { return nil }
        if let selectedKey { return cats.first { $0.key == selectedKey }?.prev }
        return cats.reduce(0) { $0 + $1.prev }
    }

    private var hint: String? {
        guard let selectedKey else { return nil }
        let text = detail?.cats.first { $0.key == selectedKey }?.hint ?? ""
        return text.isEmpty ? nil : text
    }

    private struct Bar: Identifiable {
        let id: Int
        let label: String
        let value: Int
    }

    private var bars: [Bar] {
        (detail?.timeline ?? []).enumerated().map { index, bucket in
            Bar(id: index, label: bucket.label, value: value(bucket.by))
        }
    }

    private struct Row: Identifiable {
        let id: Int
        let name: String
        let value: Int
        let previous: Int
    }

    private var rows: [Row] {
        (detail?.people ?? [])
            .map { Row(id: $0.id, name: $0.name, value: value($0.by), previous: value($0.prev)) }
            .filter { $0.value > 0 || $0.previous > 0 }
            .sorted { ($0.value, $0.previous) > ($1.value, $1.previous) }
    }

    private func replay() {
        reveal = 0
        withAnimation(.spring(response: 0.8, dampingFraction: 0.86).delay(0.05)) {
            reveal = 1
        }
    }

    // MARK: - Sekce

    private var tabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                tab(nil, "Vše", accent)
                ForEach(slices) { slice in
                    tab(slice.key, slice.label, Color(mixHex: slice.color))
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func tab(_ key: String?, _ title: String, _ color: Color) -> some View {
        let active = selectedKey == key
        return Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.snappy(duration: 0.28)) { selectedKey = key }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(active ? Color.primary : Color.secondary)
            .background {
                if active {
                    Capsule()
                        .fill(color.opacity(0.18))
                        .overlay(Capsule().strokeBorder(color.opacity(0.5)))
                        .matchedGeometryEffect(id: "tab", in: tabAnimation)
                } else {
                    Capsule().fill(Color.primary.opacity(0.05))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var stats: some View {
        let total = slices.reduce(0) { $0 + $1.count }
        let share = total > 0 ? Int((Double(currentCount) / Double(total) * 100).rounded()) : 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(currentCount)")
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .tracking(-1.5)
                    .contentTransition(.numericText(value: Double(currentCount)))
                Text("služeb \(periodPhrase)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if let hint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                statTile("Předchozí období", previousCount.map(String.init) ?? "—")
                statTile("Změna", deltaText)
                statTile("Podíl", selectedKey == nil ? "100 %" : "\(share) %")
            }
            Text(periodLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var deltaText: String {
        guard let previous = previousCount else { return selectedSlice?.delta ?? "—" }
        let diff = currentCount - previous
        return diff > 0 ? "+\(diff)" : "\(diff)"
    }

    private func statTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.headline.weight(.bold).monospacedDigit())
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var timeline: some View {
        let data = bars
        if !data.isEmpty {
            let peak = max(1, data.map(\.value).max() ?? 1)
            let labelStep = max(1, Int((Double(data.count) / 7).rounded(.up)))
            VStack(alignment: .leading, spacing: 10) {
                Text("Průběh")
                    .font(.headline.weight(.semibold))
                Chart(data) { bar in
                    BarMark(
                        x: .value("Den", bar.id),
                        y: .value("Služby", Double(bar.value) * reveal)
                    )
                    .foregroundStyle(tint.gradient)
                    .cornerRadius(4)
                }
                .chartYScale(domain: 0...Double(peak))
                .chartXAxis {
                    AxisMarks(values: Array(stride(from: 0, to: data.count, by: labelStep))) { value in
                        AxisValueLabel {
                            if let index = value.as(Int.self), data.indices.contains(index) {
                                Text(data[index].label)
                                    .font(.caption2.weight(.semibold))
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
                .frame(height: 160)
            }
        }
    }

    @ViewBuilder
    private var people: some View {
        let data = rows
        VStack(alignment: .leading, spacing: 10) {
            Text("Podle obchodníků")
                .font(.headline.weight(.semibold))
            if data.isEmpty {
                Text("V tomto období žádné služby.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                let peak = max(1, data.map(\.value).max() ?? 1)
                VStack(spacing: 12) {
                    ForEach(Array(data.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 10) {
                            Text("\(index + 1).")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 22, alignment: .leading)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(row.name)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.primary.opacity(0.07))
                                        Capsule()
                                            .fill(tint)
                                            .frame(width: geo.size.width * CGFloat(row.value) / CGFloat(peak) * reveal)
                                    }
                                }
                                .frame(height: 5)
                            }
                            Text("\(row.value)")
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .frame(minWidth: 28, alignment: .trailing)
                            let diff = row.value - row.previous
                            Text(diff > 0 ? "+\(diff)" : "\(diff)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(diff > 0 ? Color.green : (diff < 0 ? Color.red : Color.secondary))
                                .frame(minWidth: 30, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

private extension Color {
    init(mixHex hex: String) {
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
