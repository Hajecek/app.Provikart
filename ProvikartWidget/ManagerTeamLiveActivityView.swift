//
//  ManagerTeamLiveActivityView.swift
//  ProvikartWidget
//
//  Live Activity pro manažera – problémy týmu a docházka.
//

import ActivityKit
import SwiftUI
import WidgetKit

private let managerAccent = Color.indigo

struct ManagerTeamLiveActivityBannerView: View {
    let state: ManagerTeamLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(managerAccent)
                Text("Přehled týmu")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 16) {
                metricBlock(
                    value: "\(state.openProblems)",
                    label: state.openProblems == 1 ? "problém" : "problémů",
                    icon: "exclamationmark.bubble.fill"
                )
                metricBlock(
                    value: "\(state.presentToday)/\(max(state.teamSize, state.presentToday))",
                    label: "v práci dnes",
                    icon: "person.badge.clock.fill"
                )
            }

            if let latest = state.latestProblemLabel, !latest.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 11))
                        .foregroundStyle(managerAccent.opacity(0.9))
                    Text(latest)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private func metricBlock(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(managerAccent)
                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ManagerTeamLiveActivityExpandedView: View {
    let state: ManagerTeamLiveActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ManagerTeamLiveActivityBannerView(state: state)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ManagerTeamLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ManagerTeamLiveActivityAttributes.self) { context in
            ManagerTeamLiveActivityBannerView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    ManagerTeamLiveActivityExpandedView(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(managerAccent)
                    .frame(width: 24, height: 24)
            } compactTrailing: {
                Text("\(context.state.openProblems)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(minWidth: 24, alignment: .trailing)
            } minimal: {
                ZStack {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(managerAccent)
                    if context.state.openProblems > 0 {
                        Text("\(min(context.state.openProblems, 9))")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: 8, y: -8)
                    }
                }
                .frame(width: 28, height: 28)
            }
        }
    }
}
