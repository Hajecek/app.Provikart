//
//  CommissionLiveActivityView.swift
//  ProvikartWidget
//
//  Live Activity obchodníka (role „user“). Obsah všech prezentací je
//  ve sdíleném Shared/UserIslandViews.swift – stejné pohledy kreslí i náhled v aplikaci.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct CommissionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CommissionLiveActivityAttributes.self) { context in
            CommissionLockScreenView(state: context.state, isStale: context.isStale)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    UserIslandExpandedLeading(state: state)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    UserIslandExpandedTrailing(state: state)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    UserIslandExpandedBottom(state: state)
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                }
            } compactLeading: {
                UserIslandCompactLeading(state: state)
            } compactTrailing: {
                UserIslandCompactTrailing(state: state)
            } minimal: {
                UserIslandMinimal(state: state)
            }
            .widgetURL(URL(string: "provikart://"))
            .keylineTint(state.resolvedKind.islandTint)
        }
        .supplementalActivityFamilies([.small])
    }
}

private struct CommissionLockScreenView: View {
    @Environment(\.activityFamily) private var family
    var state: CommissionLiveActivityAttributes.ContentState
    var isStale: Bool

    var body: some View {
        Group {
            if family == .small {
                watch
            } else {
                UserLockCard(state: state, isStale: isStale)
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
            UserIslandCompactLeading(state: state)
            Text(state.resolvedKind.title)
                .font(.caption.weight(.bold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(watchValue)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 8)
    }

    private var watchValue: String {
        switch state.resolvedKind {
        case .commission: return state.isHidden ? "••••" : "\(state.amountText) \(state.currency)"
        case .performance: return "\(state.services)/\(state.effectiveServicesGoal)"
        case .myDay: return state.nextInstallationTime ?? "\(state.installationsToday)"
        }
    }
}

#if DEBUG
#Preview("Zámek", as: .content, using: CommissionLiveActivityAttributes()) {
    CommissionLiveActivityWidget()
} contentStates: {
    CommissionLiveActivityAttributes.ContentState.sample(kind: .commission)
    CommissionLiveActivityAttributes.ContentState.sample(kind: .performance)
    CommissionLiveActivityAttributes.ContentState.sample(kind: .myDay)
}

#Preview("Island rozbalený", as: .dynamicIsland(.expanded), using: CommissionLiveActivityAttributes()) {
    CommissionLiveActivityWidget()
} contentStates: {
    CommissionLiveActivityAttributes.ContentState.sample(kind: .commission)
    CommissionLiveActivityAttributes.ContentState.sample(kind: .performance)
    CommissionLiveActivityAttributes.ContentState.sample(kind: .myDay)
}

#Preview("Island compact", as: .dynamicIsland(.compact), using: CommissionLiveActivityAttributes()) {
    CommissionLiveActivityWidget()
} contentStates: {
    CommissionLiveActivityAttributes.ContentState.sample(kind: .commission)
    CommissionLiveActivityAttributes.ContentState.sample(kind: .performance)
    CommissionLiveActivityAttributes.ContentState.sample(kind: .myDay)
}
#endif
