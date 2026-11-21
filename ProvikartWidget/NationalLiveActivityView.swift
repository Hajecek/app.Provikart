//
//  NationalLiveActivityView.swift
//  ProvikartWidget
//
//  Live Activity národního manažera. Obsah všech prezentací je ve sdíleném
//  Shared/NationalIslandViews.swift – stejné pohledy kreslí i náhled v aplikaci.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct NationalLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NationalLiveActivityAttributes.self) { context in
            NationalLockScreenView(state: context.state, isStale: context.isStale)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    NationalIslandExpandedLeading(state: state)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    NationalIslandExpandedTrailing(state: state)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    NationalIslandExpandedBottom(state: state)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                }
            } compactLeading: {
                NationalIslandCompactLeading(state: state)
            } compactTrailing: {
                NationalIslandCompactTrailing(state: state)
            } minimal: {
                NationalIslandMinimal(state: state)
            }
            .widgetURL(URL(string: "provikart://"))
            .keylineTint(state.resolvedKind.islandTint)
        }
        .supplementalActivityFamilies([.small])
    }
}

private struct NationalLockScreenView: View {
    @Environment(\.activityFamily) private var family
    var state: NationalLiveActivityAttributes.ContentState
    var isStale: Bool

    var body: some View {
        Group {
            if family == .small {
                watch
            } else {
                NationalLockCard(state: state, isStale: isStale)
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
            NationalIslandCompactLeading(state: state)
            Text(state.resolvedKind == .orders ? "Ke kontrole" : "Hlášení")
                .font(.caption.weight(.bold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(state.resolvedKind == .orders ? "\(state.ordersToCheck)" : state.reportText)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
    }
}

#if DEBUG
#Preview("Zámek", as: .content, using: NationalLiveActivityAttributes()) {
    NationalLiveActivityWidget()
} contentStates: {
    NationalLiveActivityAttributes.ContentState.sample(kind: .overview)
    NationalLiveActivityAttributes.ContentState.sample(kind: .reports)
    NationalLiveActivityAttributes.ContentState.sample(kind: .orders)
}

#Preview("Island rozbalený", as: .dynamicIsland(.expanded), using: NationalLiveActivityAttributes()) {
    NationalLiveActivityWidget()
} contentStates: {
    NationalLiveActivityAttributes.ContentState.sample(kind: .overview)
    NationalLiveActivityAttributes.ContentState.sample(kind: .reports)
    NationalLiveActivityAttributes.ContentState.sample(kind: .orders)
}

#Preview("Island compact", as: .dynamicIsland(.compact), using: NationalLiveActivityAttributes()) {
    NationalLiveActivityWidget()
} contentStates: {
    NationalLiveActivityAttributes.ContentState.sample(kind: .overview)
    NationalLiveActivityAttributes.ContentState.sample(kind: .reports)
    NationalLiveActivityAttributes.ContentState.sample(kind: .orders)
}
#endif
