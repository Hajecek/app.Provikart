//
//  ManagerServicesStatsView.swift
//  Provikart
//
//  Statistiky služeb – otevře se kliknutím na kartu „Služby“ v přehledu.
//  Interaktivní graf (přejetí prstem po dnech), denní přírůstky,
//  srovnání s minulým obdobím, plán, rozpad na kategorie a obchodníky.
//

import SwiftUI
import Charts
import UIKit

struct ManagerServicesStatsView: View {
    @ObservedObject var viewModel: ManagerHomeViewModel
    let onOpenPerformance: () -> Void

    @State private var selectedIndex: Int?
    @State private var reveal: CGFloat = 0
    @State private var drawnKey = ""
    @State private var mixRoute: ManagerServicesMixRoute?
    @Namespace private var periodAnimation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    // Paleta shodná s přehledem.
    private var isDark: Bool { scheme == .dark }
    private var coral: Color { isDark ? Color(red: 1.00, green: 0.60, blue: 0.49) : Color(red: 0.95, green: 0.49, blue: 0.37) }
    private var good: Color { isDark ? Color(red: 0.72, green: 0.90, blue: 0.35) : Color(red: 0.24, green: 0.48, blue: 0.08) }
    private var bad: Color { isDark ? Color(red: 1.00, green: 0.60, blue: 0.49) : Color(red: 0.72, green: 0.25, blue: 0.12) }
    private let accent = Color(red: 0.99, green: 0.745, blue: 0.19)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    periodPicker
                    if let progress = viewModel.payload?.progress {
                        hero(progress)
                        if !progress.compact && !progress.labels.isEmpty {
                            cumulativeSection(progress)
                            dailySection(progress)
                        }
                        comparisonSection(progress)
                        dayStatsSection(progress)
                    } else if viewModel.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                    planSection
                    categoriesSection
                    peopleSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 36)
            }
            .navigationTitle("Statistiky služeb")
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
            .onAppear { redraw(force: true) }
            .onChange(of: viewModel.period) { _, _ in
                selectedIndex = nil
                withAnimation(.easeOut(duration: 0.18)) { reveal = 0 }
            }
            .onChange(of: viewModel.revision) { _, _ in redraw(force: false) }
            .sheet(item: $mixRoute) { route in
                ManagerServicesMixDetailView(
                    slices: viewModel.payload?.servicesBreakdown ?? [],
                    detail: viewModel.payload?.mixDetail,
                    initialKey: route.key,
                    periodLabel: viewModel.periodLabel,
                    periodPhrase: periodPhrase,
                    onOpenPerformance: {
                        dismiss()
                        onOpenPerformance()
                    }
                )
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Pomocné

    private var periodPhrase: String {
        switch viewModel.period {
        case .today: return "dnes"
        case .yesterday: return "včera"
        case .week: return "tento týden"
        case .month: return "tento měsíc"
        }
    }

    private var signature: String {
        guard let p = viewModel.payload?.progress else { return viewModel.period.rawValue }
        return viewModel.period.rawValue + "|" + p.labels.joined(separator: ",") + "|"
            + p.current.map { $0.map(String.init) ?? "n" }.joined(separator: ",")
    }

    private func redraw(force: Bool) {
        guard force || signature != drawnKey || reveal < 1 else { return }
        drawnKey = signature
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { reveal = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            withAnimation(.easeOut(duration: 0.9)) { reveal = 1 }
        }
    }

    private var idealDaily: Double? {
        guard let meta = viewModel.payload?.servicesMeta, meta.hasGoal else { return nil }
        let days = Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
        return Double(meta.teamGoal) / Double(max(1, days))
    }

    /// Denní přírůstky z kumulativní řady.
    private func daily(_ series: [Int?]) -> [Int?] {
        var out: [Int?] = []
        var last = 0
        for value in series {
            guard let value else { out.append(nil); continue }
            out.append(max(0, value - last))
            last = value
        }
        return out
    }

    private func bump() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func card<Content: View>(_ title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title).font(.headline.weight(.semibold))
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(isDark ? 0.06 : 0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func tile(_ title: String, _ value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func legend(_ title: String, _ color: Color, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [4, 3] : []))
                .frame(width: 16, height: 3)
                .background(Capsule().fill(dashed ? .clear : color))
            Text(title).lineLimit(1)
        }
    }

    // MARK: - Sekce

    private var periodPicker: some View {
        HStack(spacing: 4) {
            ForEach(ManagerOverviewPeriod.allCases) { item in
                Button {
                    bump()
                    withAnimation(.snappy(duration: 0.28)) { viewModel.period = item }
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(viewModel.period == item ? Color(uiColor: .systemBackground) : Color.primary.opacity(0.84))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if viewModel.period == item {
                                Capsule()
                                    .fill(Color.primary)
                                    .matchedGeometryEffect(id: "period", in: periodAnimation)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .padding(.top, 4)
    }

    private func hero(_ progress: ManagerOverviewProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(progress.currentTotal)")
                    .font(.system(size: 60, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .tracking(-2)
                    .contentTransition(.numericText(value: Double(progress.currentTotal)))
                    .animation(.snappy, value: progress.currentTotal)
                VStack(alignment: .leading, spacing: 4) {
                    if !progress.verdict.isEmpty {
                        let tone = progress.tone
                        Text(progress.verdict)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tone == "up" ? good : (tone == "down" ? bad : .secondary))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background((tone == "up" ? good : (tone == "down" ? bad : Color.secondary)).opacity(0.14), in: Capsule())
                    }
                    Text("služeb \(periodPhrase)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Text(viewModel.periodLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
            if !progress.story.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(coral)
                    Text(progress.story)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: Kumulativní graf s výběrem dne

    private func cumulativeSection(_ progress: ManagerOverviewProgress) -> some View {
        let points = progress.points
        let dailyCurrent = daily(progress.current)
        let pace = idealDaily
        let selected = selectedIndex.flatMap { points.indices.contains($0) ? points[$0] : nil }
        return card("Průběh") {
            HStack(spacing: 14) {
                legend(progress.currentLabel, coral, dashed: false)
                legend(progress.previousLabel, .secondary, dashed: true)
                if pace != nil { legend("Ideál", accent, dashed: true) }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            // Detail vybraného dne (nebo nápověda).
            Group {
                if let point = selected {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(point.tip.isEmpty ? point.label : point.tip)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(point.current.map { "\($0) služeb" } ?? "Den ještě nenastal")
                                .font(.headline.weight(.bold).monospacedDigit())
                        }
                        Spacer(minLength: 4)
                        if let day = dailyCurrent[safe: point.index] ?? nil {
                            selectionChip("za den", "+\(day)", coral)
                        }
                        if let prev = point.previous {
                            selectionChip("minule", "\(prev)", .secondary)
                        }
                        if let pace {
                            selectionChip("ideál", "\(Int((pace * Double(point.index + 1)).rounded()))", accent)
                        }
                    }
                } else {
                    Label("Přejeď prstem po grafu pro detail dne", systemImage: "hand.point.up.left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(height: 38, alignment: .leading)
                }
            }
            .frame(minHeight: 38)

            cumulativeChart(progress, pace: pace)
                .id(drawnKey)
                .transaction { $0.animation = nil }
                .frame(height: 230)
                .mask(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle().frame(width: max(0, geo.size.width * reveal))
                    }
                }
        }
    }

    private func selectionChip(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(color == .secondary ? Color.primary : color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func cumulativeChart(_ progress: ManagerOverviewProgress, pace: Double?) -> some View {
        let points = progress.points
        let ideal = pace.map { p in points.map { (index: $0.index, value: p * Double($0.index + 1)) } } ?? []
        let peak = points.map { Double(max($0.current ?? 0, $0.previous ?? 0)) }.max() ?? 0
        let top = max(1, max(peak, ideal.last?.value ?? 0) * 1.08)
        let step = max(1, Int((Double(points.count) / 6).rounded(.up)))
        var ticks = Array(stride(from: 0, to: points.count, by: step))
        if let last = points.indices.last, !ticks.contains(last) { ticks.append(last) }
        return Chart {
            ForEach(ideal, id: \.index) { item in
                LineMark(x: .value("Den", item.index), y: .value("Služby", item.value), series: .value("Řada", "ideal"))
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5]))
            }
            ForEach(points) { point in
                if let value = point.previous {
                    LineMark(x: .value("Den", point.index), y: .value("Služby", Double(value)), series: .value("Řada", "previous"))
                        .foregroundStyle(Color.secondary.opacity(0.85))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .interpolationMethod(.monotone)
                }
            }
            ForEach(points) { point in
                if let value = point.current {
                    AreaMark(x: .value("Den", point.index), y: .value("Služby", Double(value)), series: .value("Řada", "current"))
                        .foregroundStyle(LinearGradient(colors: [coral.opacity(0.26), coral.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Den", point.index), y: .value("Služby", Double(value)), series: .value("Řada", "current"))
                        .foregroundStyle(coral)
                        .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
            }
            if let index = selectedIndex, points.indices.contains(index) {
                RuleMark(x: .value("Den", index))
                    .foregroundStyle(Color.primary.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                if let value = points[index].current {
                    PointMark(x: .value("Den", index), y: .value("Služby", Double(value)))
                        .foregroundStyle(coral)
                        .symbolSize(90)
                }
                if let value = points[index].previous {
                    PointMark(x: .value("Den", index), y: .value("Služby", Double(value)))
                        .foregroundStyle(Color.secondary)
                        .symbolSize(50)
                }
            } else if let today = progress.todayIndex, points.indices.contains(today), let value = points[today].current {
                PointMark(x: .value("Den", today), y: .value("Služby", Double(value)))
                    .foregroundStyle(coral)
                    .symbolSize(70)
            }
        }
        .chartXSelection(value: $selectedIndex)
        .chartYScale(domain: 0...top)
        .chartXScale(domain: 0...Double(max(1, points.count - 1)))
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisValueLabel {
                    if let index = value.as(Int.self), points.indices.contains(index) {
                        Text(points[index].label).font(.caption2.weight(.semibold))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text("\(Int(number))").font(.caption2.monospacedDigit())
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedIndex)
    }

    // MARK: Denní přírůstky

    private func dailySection(_ progress: ManagerOverviewProgress) -> some View {
        let points = progress.points
        let current = daily(progress.current)
        let previous = daily(progress.previous)
        let known = current.compactMap { $0 }
        let average = known.isEmpty ? 0 : Double(known.reduce(0, +)) / Double(known.count)
        let peak = max(1, (current + previous).compactMap { $0 }.max() ?? 1)
        let step = max(1, Int((Double(points.count) / 6).rounded(.up)))
        return card("Služby po dnech") {
            Chart {
                ForEach(points) { point in
                    if let value = previous[safe: point.index] ?? nil {
                        BarMark(x: .value("Den", point.index), y: .value("Služby", Double(value) * reveal), width: .ratio(0.7))
                            .foregroundStyle(Color.secondary.opacity(0.18))
                            .cornerRadius(3)
                    }
                    if let value = current[safe: point.index] ?? nil {
                        BarMark(x: .value("Den", point.index), y: .value("Služby", Double(value) * reveal), width: .ratio(0.45))
                            .foregroundStyle(point.index == selectedIndex ? coral : coral.opacity(0.75))
                            .cornerRadius(3)
                    }
                }
                if average > 0 {
                    RuleMark(y: .value("Průměr", average))
                        .foregroundStyle(coral.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("⌀ \(String(format: "%.1f", average).replacingOccurrences(of: ".", with: ","))")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                }
                if let pace = idealDaily {
                    RuleMark(y: .value("Ideál", pace))
                        .foregroundStyle(accent)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
            }
            .chartYScale(domain: 0...Double(max(peak, Int((idealDaily ?? 0).rounded(.up)))) * 1.15)
            .chartXScale(domain: -0.6...Double(max(1, points.count - 1)) + 0.6)
            .chartXAxis {
                AxisMarks(values: Array(stride(from: 0, to: points.count, by: step))) { value in
                    AxisValueLabel {
                        if let index = value.as(Int.self), points.indices.contains(index) {
                            Text(points[index].label).font(.caption2.weight(.semibold))
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
            .frame(height: 170)

            HStack(spacing: 14) {
                legend(progress.currentLabel, coral, dashed: false)
                legend(progress.previousLabel, Color.secondary.opacity(0.4), dashed: false)
                if idealDaily != nil { legend("Ideál za den", accent, dashed: true) }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Srovnání

    private func comparisonSection(_ progress: ManagerOverviewProgress) -> some View {
        let diff = progress.currentTotal - progress.previousSame
        let pct: String = {
            guard progress.previousSame > 0 else { return progress.currentTotal > 0 ? "nové" : "—" }
            let value = Int((Double(diff) / Double(progress.previousSame) * 100).rounded())
            return (value > 0 ? "+" : "") + "\(value) %"
        }()
        return card("Srovnání") {
            HStack(spacing: 10) {
                tile(progress.nowCaption.isEmpty ? "Teď" : progress.nowCaption, "\(progress.currentTotal)")
                tile(progress.sameCaption.isEmpty ? "Minule ve stejný bod" : progress.sameCaption, "\(progress.previousSame)")
                tile(progress.prevCaption.isEmpty ? "Minule celkem" : progress.prevCaption, "\(progress.previousTotal)")
            }
            HStack(spacing: 10) {
                tile("Rozdíl", diff > 0 ? "+\(diff)" : "\(diff)", tint: diff > 0 ? good : (diff < 0 ? bad : .primary))
                tile("Změna", pct, tint: diff > 0 ? good : (diff < 0 ? bad : .primary))
                tile("Do výsledku minula", "\(max(0, progress.previousTotal - progress.currentTotal))")
            }
        }
    }

    // MARK: Statistika dnů

    @ViewBuilder
    private func dayStatsSection(_ progress: ManagerOverviewProgress) -> some View {
        let points = progress.points
        let current = daily(progress.current)
        let known: [(index: Int, value: Int)] = current.enumerated().compactMap { item in
            item.element.map { (index: item.offset, value: $0) }
        }
        if known.count > 1 {
            let best = known.max { $0.value < $1.value }!
            let worst = known.min { $0.value < $1.value }!
            let active = known.filter { $0.value > 0 }.count
            let average = Double(known.reduce(0) { $0 + $1.value }) / Double(known.count)
            let name: (Int) -> String = { index in
                let point = points[index]
                return point.tip.isEmpty ? point.label : point.tip
            }
            card("Dny") {
                HStack(spacing: 10) {
                    tile("Nejlepší den", "\(best.value)", tint: good)
                    tile("Nejslabší den", "\(worst.value)")
                    tile("Průměr za den", String(format: "%.1f", average).replacingOccurrences(of: ".", with: ","))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label("Nejlepší: \(name(best.index))", systemImage: "trophy.fill")
                    Label("Nejslabší: \(name(worst.index))", systemImage: "arrow.down.right")
                    Label("Aktivní dny: \(active) z \(known.count)", systemImage: "calendar")
                    if let pace = idealDaily {
                        let hit = known.filter { Double($0.value) >= pace }.count
                        Label("Ideál splněn: \(hit) z \(known.count) dní", systemImage: "target")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Plán

    @ViewBuilder
    private var planSection: some View {
        if let meta = viewModel.payload?.servicesMeta, meta.hasGoal {
            let pct = max(0, meta.planPct ?? Int((Double(meta.monthTotal) / Double(max(1, meta.teamGoal)) * 100).rounded()))
            card(meta.monthName.isEmpty ? "Plán služeb" : "Plán služeb · \(meta.monthName)") {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(meta.monthTotal)")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("z \(meta.teamGoal)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(pct) %")
                        .font(.headline.weight(.bold).monospacedDigit())
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(coral)
                            .frame(width: geo.size.width * min(1, CGFloat(pct) / 100) * reveal)
                    }
                }
                .frame(height: 10)
                HStack(spacing: 10) {
                    tile("Zbývá", "\(max(0, meta.remaining ?? (meta.teamGoal - meta.monthTotal)))")
                    tile("Potřeba denně", meta.neededDailyLabel ?? "—")
                    tile("Odhad měsíce", meta.prediction.map(String.init) ?? "—")
                }
                if !meta.paceStatusLabel.isEmpty {
                    Text(meta.paceStatusLabel)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(meta.paceStatus == "behind" ? bad : good)
                }
            }
        }
    }

    // MARK: Kategorie

    @ViewBuilder
    private var categoriesSection: some View {
        if let slices = viewModel.payload?.servicesBreakdown, !slices.isEmpty {
            card("Podle služeb") {
                VStack(spacing: 12) {
                    ForEach(slices) { slice in
                        Button {
                            bump()
                            mixRoute = ManagerServicesMixRoute(key: slice.key)
                        } label: {
                            HStack(spacing: 10) {
                                Circle().fill(Color(statsHex: slice.color)).frame(width: 9, height: 9)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(slice.label)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.primary.opacity(0.07))
                                            Capsule()
                                                .fill(Color(statsHex: slice.color))
                                                .frame(width: geo.size.width * CGFloat(max(0, min(100, slice.pct))) / 100 * reveal)
                                        }
                                    }
                                    .frame(height: 4)
                                }
                                Text("\(slice.count)")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .frame(minWidth: 26, alignment: .trailing)
                                Text(slice.delta)
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(slice.deltaUp == true ? good : (slice.deltaUp == false ? bad : Color.secondary))
                                    .frame(minWidth: 34, alignment: .trailing)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(slice.count > 0 ? 1 : 0.5)
                    }
                }
            }
        }
    }

    // MARK: Obchodníci

    @ViewBuilder
    private var peopleSection: some View {
        let rows = (viewModel.payload?.mixDetail?.people ?? [])
            .map { (id: $0.id, name: $0.name, value: $0.by.values.reduce(0, +), prev: $0.prev.values.reduce(0, +)) }
            .filter { $0.value > 0 || $0.prev > 0 }
            .sorted { ($0.value, $0.prev) > ($1.value, $1.prev) }
        if !rows.isEmpty {
            let peak = max(1, rows.map(\.value).max() ?? 1)
            card("Podle obchodníků") {
                VStack(spacing: 12) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
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
                                            .fill(coral)
                                            .frame(width: geo.size.width * CGFloat(row.value) / CGFloat(peak) * reveal)
                                    }
                                }
                                .frame(height: 5)
                            }
                            Text("\(row.value)")
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .frame(minWidth: 28, alignment: .trailing)
                            let diff = row.value - row.prev
                            Text(diff > 0 ? "+\(diff)" : "\(diff)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(diff > 0 ? good : (diff < 0 ? bad : Color.secondary))
                                .frame(minWidth: 30, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Color {
    init(statsHex hex: String) {
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
