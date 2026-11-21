//
//  UserIslandViews.swift
//  Sdílený soubor – identická kopie je v Provikart/Widget/Shared i ProvikartWidget/Shared.
//
//  Obsah Live Activity obchodníka pro všechny prezentace a varianty:
//  • Provize:  ◔ prstenec cíle | „57k“      → částka, sloupcový ukazatel, kapsle
//  • Výkon:    ◔ prstenec služeb | „42“     → služby / cíl, ukazatel, provize
//  • Můj den:  📅 | „14:00“                 → další instalace, počet dnes, k dokončení
//

import SwiftUI

typealias UserIslandState = CommissionLiveActivityAttributes.ContentState

extension CommissionLiveActivityAttributes.ContentState {
    var progress: Double {
        guard goal > 0, !isHidden else { return 0 }
        return min(commission / goal, 1.0)
    }

    var percentText: String {
        isHidden ? "–" : "\(IslandFormat.percent(goal > 0 ? commission / goal : 0))"
    }

    var amountText: String {
        isHidden ? "• • • •" : IslandFormat.amount(commission)
    }

    var shortAmount: String {
        isHidden ? "••" : IslandFormat.short(commission)
    }

    var remaining: Double { max(goal - commission, 0) }

    var isGoalReached: Bool { !isHidden && goal > 0 && commission >= goal }

    var services: Int { servicesCount ?? 0 }
    var effectiveServicesGoal: Int { max(servicesGoal ?? 100, 1) }

    var servicesProgress: Double {
        min(Double(services) / Double(effectiveServicesGoal), 1)
    }

    var servicesRemaining: Int { max(effectiveServicesGoal - services, 0) }

    var installationsToday: Int { todayInstallations ?? 0 }

    var installationsChipText: String? {
        guard let count = todayInstallations, count > 0 else { return nil }
        let word = IslandFormat.czechCount(count, one: "instalace", few: "instalace", many: "instalací")
        if let time = nextInstallationTime, !time.isEmpty {
            return "\(count) \(word) · \(time)"
        }
        return "\(count) \(word) dnes"
    }

    var pendingChipText: String? {
        guard let count = pendingCompletions, count > 0 else { return nil }
        return "\(count) k dokončení"
    }
}

let userCommissionColors: [Color] = [
    IslandPalette.amber, IslandPalette.yellow, IslandPalette.yellow, IslandPalette.mint
]
let userPerformanceColors: [Color] = [IslandPalette.sky, IslandPalette.mint, IslandPalette.mint]

extension UserLiveActivityKind {
    var islandTint: Color {
        switch self {
        case .commission: return IslandPalette.yellow
        case .performance: return IslandPalette.mint
        case .myDay: return IslandPalette.sky
        }
    }
}

// MARK: - Compact a minimal

struct UserIslandCompactLeading: View {
    var state: UserIslandState

    var body: some View {
        switch state.resolvedKind {
        case .commission:
            IslandMiniRing(progress: state.progress, tint: IslandPalette.yellow) {
                Image(systemName: state.isGoalReached ? "checkmark" : "creditcard.fill")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(IslandPalette.yellow)
                    .contentTransition(.symbolEffect(.replace))
            }
        case .performance:
            IslandMiniRing(progress: state.servicesProgress, tint: IslandPalette.mint) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(IslandPalette.mint)
            }
        case .myDay:
            Image(systemName: "calendar")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(IslandPalette.sky)
        }
    }
}

struct UserIslandCompactTrailing: View {
    var state: UserIslandState

    var body: some View {
        Group {
            switch state.resolvedKind {
            case .commission:
                IslandFixedWidthText(text: state.shortAmount, probe: "000k", numericValue: state.commission)
                    .foregroundStyle(IslandPalette.yellow)
            case .performance:
                IslandFixedWidthText(text: "\(state.services)", probe: "000", numericValue: Double(state.services))
                    .foregroundStyle(IslandPalette.mint)
            case .myDay:
                if let time = state.nextInstallationTime, !time.isEmpty {
                    IslandFixedWidthText(text: time, probe: "00:00", numericValue: 0)
                        .foregroundStyle(IslandPalette.sky)
                } else {
                    IslandFixedWidthText(
                        text: "\(state.installationsToday)",
                        probe: "00",
                        numericValue: Double(state.installationsToday)
                    )
                    .foregroundStyle(IslandPalette.sky)
                }
            }
        }
        .font(.system(size: 14, weight: .bold, design: .rounded))
    }
}

struct UserIslandMinimal: View {
    var state: UserIslandState

    var body: some View {
        switch state.resolvedKind {
        case .commission:
            ring(progress: state.progress, tint: IslandPalette.yellow, text: state.percentText, value: state.progress)
        case .performance:
            ring(progress: state.servicesProgress, tint: IslandPalette.mint, text: "\(state.services)", value: Double(state.services))
        case .myDay:
            ring(
                progress: state.installationsToday > 0 ? 1 : 0,
                tint: IslandPalette.sky,
                text: "\(state.installationsToday)",
                value: Double(state.installationsToday)
            )
        }
    }

    private func ring(progress: Double, tint: Color, text: String, value: Double) -> some View {
        IslandMiniRing(progress: progress, tint: tint, size: 24, lineWidth: 3) {
            Text(text)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(value: value))
        }
    }
}

// MARK: - Rozbalený Island

struct UserIslandExpandedLeading: View {
    var state: UserIslandState

    var body: some View {
        let kind = state.resolvedKind
        IslandBrandHeader(
            symbol: kind.symbolName,
            title: kind.title,
            subtitle: kind == .myDay ? "Dnes" : state.monthLabel,
            tint: kind.islandTint
        )
    }
}

struct UserIslandExpandedTrailing: View {
    var state: UserIslandState
    var ringSize: CGFloat = 44

    var body: some View {
        switch state.resolvedKind {
        case .commission:
            UserPercentRing(state: state, size: ringSize)
        case .performance:
            UserServicesRing(state: state, size: ringSize)
        case .myDay:
            IslandHeadlineValue(
                text: "\(state.installationsToday)",
                value: Double(state.installationsToday),
                caption: IslandFormat.czechCount(state.installationsToday, one: "instalace", few: "instalace", many: "instalací"),
                color: IslandPalette.sky,
                inline: ringSize < 44
            )
        }
    }
}

struct UserIslandExpandedBottom: View {
    var state: UserIslandState

    var body: some View {
        switch state.resolvedKind {
        case .commission:
            UserCommissionBody(state: state, amountSize: 30, segments: 30)
        case .performance:
            UserPerformanceBody(state: state, numberSize: 30, segments: 30)
        case .myDay:
            UserMyDayBody(state: state)
        }
    }
}

// MARK: - Lock Screen (obsah karty)

struct UserLockCard: View {
    var state: UserIslandState
    var isStale: Bool

    var body: some View {
        let kind = state.resolvedKind
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: kind.symbolName)
                        .foregroundStyle(kind.islandTint)
                    Text(kind.title)
                    if let sub = kind == .myDay ? "dnes" : state.monthLabel, !sub.isEmpty {
                        Text("· \(sub)")
                            .foregroundStyle(IslandPalette.secondary)
                    }
                    if isStale {
                        Text("· neaktuální")
                            .foregroundStyle(IslandPalette.tertiary)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                Spacer(minLength: 8)
                UserIslandExpandedTrailing(state: state, ringSize: 40)
            }

            switch kind {
            case .commission:
                UserCommissionBody(state: state, amountSize: 28, segments: 34, barHeight: 16)
            case .performance:
                UserPerformanceBody(state: state, numberSize: 28, segments: 34, barHeight: 16)
            case .myDay:
                UserMyDayBody(state: state)
            }
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Části

struct UserPercentRing: View {
    var state: UserIslandState
    var size: CGFloat

    var body: some View {
        ZStack {
            IslandRing(progress: state.progress, tint: IslandPalette.yellow, lineWidth: size * 0.11)
            if state.isGoalReached {
                Image(systemName: "trophy.fill")
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundStyle(IslandPalette.yellow)
                    .transition(.scale.combined(with: .opacity))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(state.percentText)
                        .font(.system(size: size * 0.3, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: state.progress))
                    if !state.isHidden {
                        Text("%")
                            .font(.system(size: size * 0.18, weight: .bold, design: .rounded))
                            .foregroundStyle(IslandPalette.secondary)
                    }
                }
                .foregroundStyle(.white)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .islandAnimation(value: state.isGoalReached)
        .accessibilityLabel(state.isHidden ? "Postup skrytý" : "Splněno \(state.percentText) procent")
    }
}

struct UserServicesRing: View {
    var state: UserIslandState
    var size: CGFloat

    var body: some View {
        ZStack {
            IslandRing(progress: state.servicesProgress, tint: IslandPalette.mint, lineWidth: size * 0.11)
            if state.servicesProgress >= 1 {
                Image(systemName: "flame.fill")
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundStyle(IslandPalette.mint)
                    .transition(.scale.combined(with: .opacity))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(IslandFormat.percent(state.servicesProgress))")
                        .font(.system(size: size * 0.3, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: state.servicesProgress))
                    Text("%")
                        .font(.system(size: size * 0.18, weight: .bold, design: .rounded))
                        .foregroundStyle(IslandPalette.secondary)
                }
                .foregroundStyle(.white)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .islandAnimation(value: state.servicesProgress >= 1)
    }
}

struct UserCommissionBody: View {
    var state: UserIslandState
    var amountSize: CGFloat
    var segments: Int
    var barHeight: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                IslandNumber(text: state.amountText, value: state.commission, size: amountSize)
                Text(state.currency)
                    .font(.system(size: amountSize * 0.5, weight: .bold, design: .rounded))
                    .foregroundStyle(IslandPalette.secondary)
                Spacer(minLength: 6)
                UserGoalLabel(state: state)
            }
            IslandBarMeter(
                progress: state.progress,
                colors: userCommissionColors,
                segments: segments,
                height: barHeight,
                markers: [0.5]
            )
            UserChips(state: state)
        }
    }
}

struct UserPerformanceBody: View {
    var state: UserIslandState
    var numberSize: CGFloat
    var segments: Int
    var barHeight: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                IslandNumber(text: "\(state.services)", value: Double(state.services), size: numberSize)
                Text("/ \(state.effectiveServicesGoal) služeb")
                    .font(.system(size: numberSize * 0.45, weight: .bold, design: .rounded))
                    .foregroundStyle(IslandPalette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Group {
                    if state.servicesRemaining == 0 {
                        Label("Cíl splněn", systemImage: "sparkles")
                            .foregroundStyle(IslandPalette.mint)
                    } else {
                        Text("zbývá \(state.servicesRemaining)")
                            .contentTransition(.numericText(value: Double(state.servicesRemaining)))
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IslandPalette.secondary)
                .lineLimit(1)
            }
            IslandBarMeter(
                progress: state.servicesProgress,
                colors: userPerformanceColors,
                segments: segments,
                height: barHeight,
                markers: [0.5]
            )
            HStack(spacing: 6) {
                if !state.isHidden {
                    IslandChip(
                        symbol: "creditcard.fill",
                        text: "Provize \(IslandFormat.short(state.commission)) \(state.currency)",
                        tint: IslandPalette.yellow
                    )
                }
                if let pending = state.pendingChipText {
                    IslandChip(symbol: "exclamationmark.circle.fill", text: pending, tint: IslandPalette.coral)
                        .transition(.push(from: .bottom).combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }
            .islandAnimation(value: state.pendingCompletions)
        }
    }
}

struct UserMyDayBody: View {
    var state: UserIslandState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(IslandPalette.sky.opacity(0.18))
                    Image(systemName: state.nextInstallationTime == nil ? "checkmark.circle.fill" : "wrench.and.screwdriver.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(IslandPalette.sky)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 1) {
                    if let time = state.nextInstallationTime, !time.isEmpty {
                        Text("Další instalace")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(IslandPalette.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(time)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .contentTransition(.numericText())
                            if let name = state.nextInstallationName, !name.isEmpty {
                                Text(name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(IslandPalette.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .id(time)
                        .transition(.push(from: .bottom).combined(with: .opacity))
                    } else {
                        Text(state.installationsToday > 0 ? "Dnešní instalace hotové" : "Dnes žádná instalace")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Užijte si klidnější den")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(IslandPalette.secondary)
                    }
                }
                .islandAnimation(value: state.nextInstallationTime)
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                if let pending = state.pendingChipText {
                    IslandChip(symbol: "exclamationmark.circle.fill", text: pending, tint: IslandPalette.coral)
                } else {
                    IslandChip(symbol: "checkmark.seal.fill", text: "Nic nečeká na dokončení", tint: IslandPalette.mint)
                }
                if !state.isHidden {
                    IslandChip(symbol: "creditcard.fill", text: "\(IslandFormat.short(state.commission)) \(state.currency)", tint: IslandPalette.yellow)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct UserGoalLabel: View {
    var state: UserIslandState

    var body: some View {
        Group {
            if state.isHidden {
                Text("Skryto")
            } else if state.isGoalReached {
                Label("Cíl splněn", systemImage: "sparkles")
                    .foregroundStyle(IslandPalette.mint)
            } else {
                Text("zbývá \(IslandFormat.short(state.remaining))")
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(IslandPalette.secondary)
        .lineLimit(1)
        .contentTransition(.numericText(value: state.remaining))
    }
}

struct UserChips: View {
    var state: UserIslandState

    var body: some View {
        let install = state.installationsChipText
        let pending = state.pendingChipText
        if install != nil || pending != nil {
            HStack(spacing: 6) {
                if let install {
                    IslandChip(symbol: "calendar", text: install, tint: IslandPalette.sky)
                        .transition(.push(from: .bottom).combined(with: .opacity))
                }
                if let pending {
                    IslandChip(symbol: "exclamationmark.circle.fill", text: pending, tint: IslandPalette.coral)
                        .transition(.push(from: .bottom).combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }
            .islandAnimation(value: [install ?? "", pending ?? ""])
        }
    }
}

// MARK: - Ukázková data (náhled ve výběru)

extension CommissionLiveActivityAttributes.ContentState {
    static func sample(kind: UserLiveActivityKind) -> Self {
        Self(
            commission: 56_600, goal: 100_000, monthLabel: "Listopad", currency: "Kč", isHidden: false,
            todayInstallations: 2, nextInstallationTime: "14:00", nextInstallationName: "Internet 1000",
            pendingCompletions: 3, kind: kind, servicesCount: 42, servicesGoal: 60
        )
    }
}
