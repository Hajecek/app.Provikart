//
//  ManagerTeamLiveActivityView.swift
//  ProvikartWidget
//
//  Live Activity s počtem dnešních služeb.
//  Rozložení podle systémových aktivit: zámek, malá rodina a Dynamic Island
//  ve vlastních regionech. Číslo v Islandu má skrytý vzor šířky, jinak se
//  ostrov roztáhne přes displej.
//

import ActivityKit
import SwiftUI
import WidgetKit

private func czechCount(_ n: Int, one: String, few: String, many: String) -> String {
    let mod10 = abs(n) % 10
    let mod100 = abs(n) % 100
    if mod10 == 1 && mod100 != 11 { return one }
    if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
    return many
}

private func servicesWord(_ n: Int) -> String {
    czechCount(n, one: "služba", few: "služby", many: "služeb")
}

struct ManagerTeamLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ManagerTeamLiveActivityAttributes.self) { context in
            ManagerServicesLockScreen(state: context.state, isStale: context.isStale)
        } dynamicIsland: { context in
            let count = "\(context.state.todayServices)"
            let badgeProbe = String(repeating: "0", count: min(max(count.count, 1), 3))
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandMark()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandServiceCount(text: count, probe: badgeProbe, alignment: .center)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(ProvikartActivityPalette.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(ProvikartActivityPalette.yellow, in: Capsule())
                        .fixedSize()
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("Služby")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(ProvikartActivityPalette.yellow)
            } compactTrailing: {
                IslandServiceCount(text: count)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(ProvikartActivityPalette.yellow)
            } minimal: {
                IslandServiceCount(text: count, probe: "00")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ProvikartActivityPalette.yellow)
            }
            .widgetURL(URL(string: "provikart://"))
            .keylineTint(ProvikartActivityPalette.yellow)
        }
        .supplementalActivityFamilies([.small])
    }
}

/// Číslo drží pevnou šířku skrytého vzoru. Bez ní Dynamic Island vyroste přes displej.
private struct IslandServiceCount: View {
    var text: String
    var probe = "000"
    var alignment: Alignment = .trailing

    var body: some View {
        Text(probe)
            .monospacedDigit()
            .hidden()
            .overlay(alignment: alignment) {
                Text(text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            }
            .lineLimit(1)
    }
}

private struct IslandMark: View {
    var body: some View {
        Image(systemName: "chart.bar.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(ProvikartActivityPalette.ink)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(ProvikartActivityPalette.yellow)
            )
    }
}

private struct ManagerServicesLockScreen: View {
    @Environment(\.activityFamily) private var family
    var state: ManagerTeamLiveActivityAttributes.ContentState
    var isStale: Bool

    var body: some View {
        Group {
            if family == .small {
                watch
            } else {
                card
            }
        }
        .widgetURL(URL(string: "provikart://"))
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.fill")
                    .font(.body.weight(.bold))
                Text("Provikart")
                    .font(.subheadline.weight(.bold))
                Spacer(minLength: 8)
                Text(statusLabel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(state.todayServices)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .widgetAccentable()
                Text(servicesWord(state.todayServices))
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
            }
            Text("dnes")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ProvikartActivityPalette.ink.opacity(0.62))
        }
        .padding(16)
        .foregroundStyle(ProvikartActivityPalette.ink)
        .activityBackgroundTint(ProvikartActivityPalette.yellow)
        .activitySystemActionForegroundColor(ProvikartActivityPalette.ink)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Služby dnes, \(state.todayServices)")
    }

    private var watch: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.fill")
                .font(.caption.weight(.bold))
            Text("Služby")
                .font(.caption.weight(.bold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(state.todayServices)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Služby dnes, \(state.todayServices)")
    }

    private var statusLabel: String {
        if isStale { return "Neaktuální" }
        if let day = state.dayLabel, !day.isEmpty { return day }
        return "Dnes"
    }
}

#if DEBUG
#Preview("Zámek", as: .content, using: ManagerTeamLiveActivityAttributes()) {
    ManagerTeamLiveActivityWidget()
} contentStates: {
    ManagerTeamLiveActivityAttributes.ContentState(
        todayServices: 12,
        openProblems: 3,
        teamSize: 8,
        presentToday: 6,
        dayLabel: "6. října"
    )
}

#Preview("Island", as: .dynamicIsland(.expanded), using: ManagerTeamLiveActivityAttributes()) {
    ManagerTeamLiveActivityWidget()
} contentStates: {
    ManagerTeamLiveActivityAttributes.ContentState(
        todayServices: 12,
        dayLabel: "6. října"
    )
}
#endif
