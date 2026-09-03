//
//  ManagerTeamLiveActivityView.swift
//  ProvikartWidget
//
//  Live Activity pro manažera – Lock Screen a Dynamic Island.
//

import ActivityKit
import SwiftUI
import WidgetKit

private let servicesAccent = Color(red: 0.14, green: 0.72, blue: 0.68)
private let teamAccent = Color(red: 0.45, green: 0.42, blue: 0.95)

private func managerAccent(for kind: ManagerLiveActivityKind) -> Color {
    switch kind {
    case .todayServices: return servicesAccent
    case .teamOverview: return teamAccent
    }
}

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

private func problemsWord(_ n: Int) -> String {
    czechCount(n, one: "problém", few: "problémy", many: "problémů")
}

// MARK: - Lock Screen

struct ManagerTeamLiveActivityBannerView: View {
    let state: ManagerTeamLiveActivityAttributes.ContentState

    private var accent: Color { managerAccent(for: state.kind) }
    private var teamSize: Int { max(state.teamSize, state.presentToday) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            switch state.kind {
            case .todayServices:
                servicesHero
            case .teamOverview:
                teamHero
            }

            footerChips
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .activityBackgroundTint(accent.opacity(0.22))
        .activitySystemActionForegroundColor(accent)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                Image(systemName: state.kind.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(state.kind.title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                if let day = state.dayLabel, !day.isEmpty {
                    Text(day)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var servicesHero: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text("\(state.todayServices)")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(servicesWord(state.todayServices))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var teamHero: some View {
        HStack(spacing: 12) {
            metricColumn(
                value: "\(state.presentToday)/\(max(teamSize, 1))",
                label: "v práci"
            )
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: 36)
            metricColumn(
                value: "\(state.openProblems)",
                label: problemsWord(state.openProblems)
            )
            Spacer(minLength: 0)
        }
    }

    private func metricColumn(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var footerChips: some View {
        HStack(spacing: 8) {
            switch state.kind {
            case .todayServices:
                chip(icon: "person.badge.clock.fill", text: "\(state.presentToday)/\(max(teamSize, 1)) v práci")
                chip(icon: "exclamationmark.bubble.fill", text: "\(state.openProblems) \(problemsWord(state.openProblems))")
            case .teamOverview:
                if let latest = state.latestProblemLabel, !latest.isEmpty {
                    chip(icon: "clock.badge.exclamationmark", text: latest)
                } else {
                    chip(icon: "checkmark.seal.fill", text: "Žádný otevřený problém")
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }
}

// MARK: - Dynamic Island expanded

private struct ManagerIslandExpandedLeading: View {
    let state: ManagerTeamLiveActivityAttributes.ContentState
    private var accent: Color { managerAccent(for: state.kind) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: state.kind.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(state.kind.compactTitle)
                    .font(.system(size: 15, weight: .semibold))
                if let day = state.dayLabel, !day.isEmpty {
                    Text(day)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, 4)
    }
}

private struct ManagerIslandExpandedTrailing: View {
    let state: ManagerTeamLiveActivityAttributes.ContentState

    var body: some View {
        switch state.kind {
        case .todayServices:
            Text("\(state.todayServices)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        case .teamOverview:
            Text("\(state.presentToday)/\(max(state.teamSize, state.presentToday, 1))")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }
}

private struct ManagerIslandExpandedBottom: View {
    let state: ManagerTeamLiveActivityAttributes.ContentState
    private var accent: Color { managerAccent(for: state.kind) }

    var body: some View {
        HStack(spacing: 10) {
            switch state.kind {
            case .todayServices:
                Text(servicesWord(state.todayServices).capitalized)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Label("\(state.presentToday) v práci", systemImage: "person.badge.clock.fill")
                Label("\(state.openProblems)", systemImage: "exclamationmark.bubble.fill")
            case .teamOverview:
                Label(
                    "\(state.openProblems) \(problemsWord(state.openProblems))",
                    systemImage: "exclamationmark.bubble.fill"
                )
                Spacer(minLength: 0)
                if let latest = state.latestProblemLabel, !latest.isEmpty {
                    Text(latest)
                        .lineLimit(1)
                }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .tint(accent)
    }
}

// MARK: - Widget

struct ManagerTeamLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ManagerTeamLiveActivityAttributes.self) { context in
            ManagerTeamLiveActivityBannerView(state: context.state)
        } dynamicIsland: { context in
            let accent = managerAccent(for: context.state.kind)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ManagerIslandExpandedLeading(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ManagerIslandExpandedTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ManagerIslandExpandedBottom(state: context.state)
                }
            } compactLeading: {
                Image(systemName: context.state.kind.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            } compactTrailing: {
                Group {
                    switch context.state.kind {
                    case .todayServices:
                        Text("\(context.state.todayServices)")
                    case .teamOverview:
                        Text("\(context.state.openProblems)")
                    }
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .foregroundStyle(.primary)
            } minimal: {
                ZStack {
                    Image(systemName: context.state.kind.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                    if context.state.kind == .teamOverview, context.state.openProblems > 0 {
                        Text("\(min(context.state.openProblems, 9))")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Color.red, in: Circle())
                            .offset(x: 8, y: -8)
                    }
                }
                .frame(width: 28, height: 28)
            }
            .keylineTint(accent)
        }
    }
}
