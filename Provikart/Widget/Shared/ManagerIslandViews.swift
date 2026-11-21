//
//  ManagerIslandViews.swift
//  Sdílený soubor – identická kopie je v Provikart/Widget/Shared i ProvikartWidget/Shared.
//
//  Obsah Live Activity manažera pro všechny prezentace a varianty:
//  • Služby dnes:  ▮ ikona | počet        → tři dlaždice (služby, docházka, problémy)
//  • Přehled týmu: ◔ docházka | „6/8“/⚠︎3 → tři dlaždice + poslední problém
//  • Výkon týmu:   ▁▃▅ minigraf | měsíc   → graf po dnech, top obchodník, dnes
//

import SwiftUI

typealias ManagerIslandState = ManagerTeamLiveActivityAttributes.ContentState

extension ManagerTeamLiveActivityAttributes.ContentState {
    var teamTotal: Int { max(teamSize, presentToday) }

    var attendanceProgress: Double {
        guard teamTotal > 0 else { return 0 }
        return Double(presentToday) / Double(teamTotal)
    }

    var attendanceText: String {
        teamTotal > 0 ? "\(presentToday)/\(teamTotal)" : "–"
    }

    var servicesWord: String {
        IslandFormat.czechCount(todayServices, one: "služba", few: "služby", many: "služeb")
    }

    var monthServicesWord: String {
        IslandFormat.czechCount(monthServices, one: "služba", few: "služby", many: "služeb")
    }

    var hasProblems: Bool { openProblems > 0 }

    /// Průměr služeb na den z grafu (bez dneška, který ještě běží).
    var dailyAverage: Double {
        let past = dailyServices.dropLast()
        guard !past.isEmpty else { return Double(todayServices) }
        return Double(past.reduce(0, +)) / Double(past.count)
    }
}

extension ManagerLiveActivityKind {
    var islandTint: Color {
        switch self {
        case .todayServices: return IslandPalette.yellow
        case .teamOverview: return IslandPalette.mint
        case .performance: return IslandPalette.amber
        }
    }
}

// MARK: - Compact a minimal

struct ManagerIslandCompactLeading: View {
    var state: ManagerIslandState

    var body: some View {
        switch state.kind {
        case .todayServices:
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(IslandPalette.yellow)
                .symbolEffect(.bounce, value: state.todayServices)
        case .teamOverview:
            IslandMiniRing(progress: state.attendanceProgress, tint: IslandPalette.mint) {
                Image(systemName: "person.fill")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(IslandPalette.mint)
            }
        case .performance:
            IslandSparkBars(values: state.dailyServices, tint: IslandPalette.yellow)
        }
    }
}

struct ManagerIslandCompactTrailing: View {
    var state: ManagerIslandState

    var body: some View {
        Group {
            switch state.kind {
            case .todayServices:
                IslandFixedWidthText(
                    text: "\(state.todayServices)",
                    probe: "000",
                    numericValue: Double(state.todayServices)
                )
                .foregroundStyle(IslandPalette.yellow)
            case .teamOverview:
                if state.hasProblems {
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .bold))
                        IslandFixedWidthText(
                            text: "\(state.openProblems)",
                            probe: "00",
                            numericValue: Double(state.openProblems)
                        )
                    }
                    .foregroundStyle(IslandPalette.coral)
                    .transition(.push(from: .bottom).combined(with: .opacity))
                } else {
                    IslandFixedWidthText(
                        text: state.attendanceText,
                        probe: "00/00",
                        numericValue: Double(state.presentToday)
                    )
                    .foregroundStyle(IslandPalette.mint)
                    .transition(.push(from: .bottom).combined(with: .opacity))
                }
            case .performance:
                IslandFixedWidthText(
                    text: "\(state.monthServices)",
                    probe: "0000",
                    numericValue: Double(state.monthServices)
                )
                .foregroundStyle(IslandPalette.yellow)
            }
        }
        .font(.system(size: 14, weight: .bold, design: .rounded))
    }
}

struct ManagerIslandMinimal: View {
    var state: ManagerIslandState

    var body: some View {
        switch state.kind {
        case .todayServices:
            ring(progress: 1, tint: IslandPalette.yellow, value: state.todayServices)
        case .teamOverview:
            ring(
                progress: state.attendanceProgress,
                tint: state.hasProblems ? IslandPalette.coral : IslandPalette.mint,
                value: state.hasProblems ? state.openProblems : state.presentToday
            )
        case .performance:
            let peak = max(state.dailyServices.max() ?? 0, 1)
            ring(
                progress: Double(state.todayServices) / Double(peak),
                tint: IslandPalette.yellow,
                value: state.todayServices
            )
        }
    }

    private func ring(progress: Double, tint: Color, value: Int) -> some View {
        IslandMiniRing(progress: progress, tint: tint, size: 24, lineWidth: 3) {
            Text("\(value)")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(value: Double(value)))
        }
    }
}

// MARK: - Rozbalený Island

struct ManagerIslandExpandedLeading: View {
    var state: ManagerIslandState

    var body: some View {
        switch state.kind {
        case .performance:
            IslandBrandHeader(
                symbol: "chart.line.uptrend.xyaxis",
                title: "Výkon týmu",
                subtitle: state.monthLabel ?? "Tento měsíc",
                tint: IslandPalette.yellow
            )
        default:
            IslandBrandHeader(
                symbol: "person.3.fill",
                title: "Tým",
                subtitle: state.dayLabel ?? "Dnes",
                tint: IslandPalette.yellow
            )
        }
    }
}

/// Hlavní číslo vpravo nahoře – navazuje na compact trailing (HIG: zachovat rozmístění).
struct ManagerIslandExpandedTrailing: View {
    var state: ManagerIslandState
    var inline = false

    var body: some View {
        switch state.kind {
        case .todayServices:
            IslandHeadlineValue(text: "\(state.todayServices)", value: Double(state.todayServices),
                                caption: state.servicesWord, color: IslandPalette.yellow, inline: inline)
        case .teamOverview:
            IslandHeadlineValue(text: state.attendanceText, value: Double(state.presentToday),
                                caption: "v práci", color: IslandPalette.mint, inline: inline)
        case .performance:
            IslandHeadlineValue(text: "\(state.monthServices)", value: Double(state.monthServices),
                                caption: inline ? state.monthServicesWord : "\(state.monthServicesWord) za měsíc",
                                color: IslandPalette.yellow, inline: inline)
        }
    }
}

struct ManagerIslandExpandedBottom: View {
    var state: ManagerIslandState
    var ringSize: CGFloat = 40

    var body: some View {
        switch state.kind {
        case .performance:
            ManagerPerformanceBody(state: state, chartHeight: 54)
        default:
            VStack(spacing: 10) {
                ManagerTiles(state: state, ringSize: ringSize)
                ManagerProblemLine(state: state)
            }
        }
    }
}

// MARK: - Lock Screen (obsah karty)

struct ManagerLockCard: View {
    var state: ManagerIslandState
    var isStale: Bool

    /// Lock Screen má omezenou výšku (~160 pt) – rozložení je nižší než v rozbaleném Islandu.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Image(systemName: state.kind == .performance ? "chart.line.uptrend.xyaxis" : "person.3.fill")
                        .foregroundStyle(IslandPalette.yellow)
                    Text(state.kind == .performance ? "Výkon týmu" : "Tým")
                    Text("· \(statusLabel)")
                        .foregroundStyle(isStale ? IslandPalette.tertiary : IslandPalette.secondary)
                }
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                Spacer(minLength: 8)
                ManagerIslandExpandedTrailing(state: state, inline: true)
            }

            switch state.kind {
            case .performance:
                ManagerPerformanceBody(state: state, chartHeight: 30)
            default:
                ManagerTiles(state: state, ringSize: 32, horizontal: true)
                ManagerProblemLine(state: state)
            }
        }
        .foregroundStyle(.white)
    }

    private var statusLabel: String {
        if isStale { return "neaktuální" }
        if state.kind == .performance, let month = state.monthLabel, !month.isEmpty { return month }
        if let day = state.dayLabel, !day.isEmpty { return day }
        return "dnes"
    }
}

// MARK: - Části

struct ManagerTiles: View {
    var state: ManagerIslandState
    var ringSize: CGFloat
    var horizontal = false

    var body: some View {
        HStack(spacing: 8) {
            IslandGaugeTile(
                symbol: "chart.bar.fill",
                value: "\(state.todayServices)",
                numericValue: Double(state.todayServices),
                caption: "Služby",
                tint: IslandPalette.yellow,
                style: .badge,
                ringSize: ringSize,
                horizontal: horizontal
            )
            IslandGaugeTile(
                symbol: "person.2.fill",
                value: state.attendanceText,
                numericValue: Double(state.presentToday),
                caption: "Docházka",
                tint: IslandPalette.mint,
                style: .ring(state.attendanceProgress),
                ringSize: ringSize,
                horizontal: horizontal
            )
            IslandGaugeTile(
                symbol: state.hasProblems ? "exclamationmark.triangle.fill" : "checkmark",
                value: state.hasProblems ? "\(state.openProblems)" : "OK",
                numericValue: Double(state.openProblems),
                caption: "Problémy",
                tint: state.hasProblems ? IslandPalette.coral : IslandPalette.mint,
                style: .alert(state.hasProblems),
                ringSize: ringSize,
                horizontal: horizontal
            )
        }
    }
}

struct ManagerProblemLine: View {
    var state: ManagerIslandState

    var body: some View {
        Group {
            if state.hasProblems, let label = state.latestProblemLabel, !label.isEmpty {
                HStack {
                    IslandChip(symbol: "exclamationmark.bubble.fill", text: label, tint: IslandPalette.coral)
                    Spacer(minLength: 0)
                }
                .id(label)
                .transition(.push(from: .bottom).combined(with: .opacity))
            }
        }
        .islandAnimation(value: state.latestProblemLabel)
    }
}

struct ManagerPerformanceBody: View {
    var state: ManagerIslandState
    var chartHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if state.dailyServices.isEmpty {
                Text("Graf se doplní po načtení výkonu týmu.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IslandPalette.secondary)
            } else {
                IslandColumnChart(
                    values: state.dailyServices,
                    labels: state.dailyLabels,
                    height: chartHeight
                )
            }

            HStack(spacing: 6) {
                if let name = state.topPerformerName, !name.isEmpty {
                    IslandChip(
                        symbol: "trophy.fill",
                        text: "\(name) · \(state.topPerformerServices)",
                        tint: IslandPalette.yellow
                    )
                    .id(name)
                    .transition(.push(from: .bottom).combined(with: .opacity))
                }
                IslandChip(
                    symbol: trendSymbol,
                    text: "Dnes \(state.todayServices)",
                    tint: trendTint
                )
                Spacer(minLength: 0)
            }
            .islandAnimation(value: state.topPerformerName)
        }
    }

    private var isAboveAverage: Bool { Double(state.todayServices) >= state.dailyAverage }
    private var trendSymbol: String { isAboveAverage ? "arrow.up.right" : "arrow.down.right" }
    private var trendTint: Color { isAboveAverage ? IslandPalette.mint : IslandPalette.coral }
}

// MARK: - Ukázková data (náhled ve výběru)

extension ManagerTeamLiveActivityAttributes.ContentState {
    static func sample(kind: ManagerLiveActivityKind) -> Self {
        Self(
            kind: kind, todayServices: 12, openProblems: 3, teamSize: 8, presentToday: 6,
            latestProblemLabel: "Jan Novák · obj. 4521", dayLabel: "21. listopadu",
            monthServices: 184, dailyServices: [9, 14, 11, 17, 8, 15, 12],
            dailyLabels: ["So", "Ne", "Po", "Út", "St", "Čt", "Pá"],
            topPerformerName: "Jana K.", topPerformerServices: 34, monthLabel: "Listopad"
        )
    }
}
