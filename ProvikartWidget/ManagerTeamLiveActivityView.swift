//
//  ManagerTeamLiveActivityView.swift
//  ProvikartWidget
//
//  Live Activity manažera. Obsah všech prezentací je ve sdíleném
//  Shared/ManagerIslandViews.swift – stejné pohledy kreslí i náhled v aplikaci.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct ManagerTeamLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ManagerTeamLiveActivityAttributes.self) { context in
            ManagerLockScreenView(state: context.state, isStale: context.isStale)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ManagerIslandExpandedLeading(state: state)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ManagerIslandExpandedTrailing(state: state)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ManagerIslandExpandedBottom(state: state)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                }
            } compactLeading: {
                ManagerIslandCompactLeading(state: state)
            } compactTrailing: {
                ManagerIslandCompactTrailing(state: state)
            } minimal: {
                ManagerIslandMinimal(state: state)
            }
            .widgetURL(URL(string: "provikart://"))
            .keylineTint(state.kind.islandTint)
        }
        .supplementalActivityFamilies([.small])
    }
}

private struct ManagerLockScreenView: View {
    @Environment(\.activityFamily) private var family
    var state: ManagerTeamLiveActivityAttributes.ContentState
    var isStale: Bool

    var body: some View {
        Group {
            if family == .small {
                watch
            } else {
                ManagerLockCard(state: state, isStale: isStale)
                    .islandLockCardPadding()
                    .activityBackgroundTint(IslandPalette.lockBackground)
                    .activitySystemActionForegroundColor(.white)
                    .accessibilityElement(children: .combine)
            }
        }
        .widgetURL(URL(string: "provikart://"))
    }

    private var watch: some View {
        HStack(spacing: 8) {
            ManagerIslandCompactLeading(state: state)
            Text(state.kind.compactTitle)
                .font(.caption.weight(.bold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(watchValue)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
    }

    private var watchValue: String {
        switch state.kind {
        case .todayServices: return "\(state.todayServices)"
        case .teamOverview: return state.attendanceText
        case .performance: return "\(state.monthServices)"
        }
    }
}

#if DEBUG
#Preview("Zámek", as: .content, using: ManagerTeamLiveActivityAttributes()) {
    ManagerTeamLiveActivityWidget()
} contentStates: {
    ManagerTeamLiveActivityAttributes.ContentState.sample(kind: .performance)
    ManagerTeamLiveActivityAttributes.ContentState.sample(kind: .todayServices)
    ManagerTeamLiveActivityAttributes.ContentState.sample(kind: .teamOverview)
}

#Preview("Island rozbalený", as: .dynamicIsland(.expanded), using: ManagerTeamLiveActivityAttributes()) {
    ManagerTeamLiveActivityWidget()
} contentStates: {
    ManagerTeamLiveActivityAttributes.ContentState.sample(kind: .performance)
    ManagerTeamLiveActivityAttributes.ContentState.sample(kind: .todayServices)
    ManagerTeamLiveActivityAttributes.ContentState.sample(kind: .teamOverview)
}

#Preview("Island compact", as: .dynamicIsland(.compact), using: ManagerTeamLiveActivityAttributes()) {
    ManagerTeamLiveActivityWidget()
} contentStates: {
    ManagerTeamLiveActivityAttributes.ContentState.sample(kind: .performance)
    ManagerTeamLiveActivityAttributes.ContentState.sample(kind: .todayServices)
    ManagerTeamLiveActivityAttributes.ContentState.sample(kind: .teamOverview)
}
#endif
