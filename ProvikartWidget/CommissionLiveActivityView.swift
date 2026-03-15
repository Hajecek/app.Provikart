//
//  CommissionLiveActivityView.swift
//  ProvikartWidget
//
//  Zobrazení Live Activity – provize a postup k cíli (Lock Screen, Dynamic Island).
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Compact (Dynamic Island – zúžený)

struct CommissionLiveActivityCompactView: View {
    let context: ActivityViewContext<CommissionLiveActivityAttributes>
    let state: CommissionLiveActivityAttributes.ContentState

    private func formatCommission(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    private var progress: Double {
        guard state.goal > 0 else { return 0 }
        return min(state.commission / state.goal, 1.0)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
            if state.isHidden {
                Text("– – –")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            } else {
                Text(formatCommission(state.commission) + " " + state.currency)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            Spacer(minLength: 6)
            ProgressView(value: progress)
                .tint(.orange)
                .frame(maxWidth: 50)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Minimal (Dynamic Island – miniatura)

struct CommissionLiveActivityMinimalView: View {
    let context: ActivityViewContext<CommissionLiveActivityAttributes>
    let state: CommissionLiveActivityAttributes.ContentState

    private var progress: Double {
        guard state.goal > 0 else { return 0 }
        return min(state.commission / state.goal, 1.0)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            ProgressView(value: progress)
                .tint(.orange)
                .frame(width: 24)
        }
        .padding(8)
    }
}

// MARK: - Banner (Lock Screen – rozšířený pruh)

struct CommissionLiveActivityBannerView: View {
    let context: ActivityViewContext<CommissionLiveActivityAttributes>
    let state: CommissionLiveActivityAttributes.ContentState

    private func formatCommission(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    private func scaleLabel(_ value: Double) -> String {
        if value >= 1000 {
            let k = value / 1000.0
            return k == floor(k) ? "\(Int(k))k" : String(format: "%.1fk", k)
        }
        return String(format: "%.0f", value)
    }

    private var progress: Double {
        guard state.goal > 0 else { return 0 }
        return min(state.commission / state.goal, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                Text("Provize za měsíc")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                if let label = state.monthLabel, !label.isEmpty {
                    Text("· \(label)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }

            if state.isHidden {
                Text("– – – –")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatCommission(state.commission))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text(state.currency)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Progress bar (oranžová → zelená)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [.orange, .yellow, .green],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * progress), height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text("0")
                Spacer()
                Text(scaleLabel(state.goal / 2))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(scaleLabel(state.goal))
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        }
        .padding(16)
    }
}

// MARK: - Expanded Dynamic Island (vycentrovaný obsah v celé ploše)

struct CommissionLiveActivityExpandedView: View {
    let context: ActivityViewContext<CommissionLiveActivityAttributes>
    let state: CommissionLiveActivityAttributes.ContentState

    private func formatCommission(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    private func scaleLabel(_ value: Double) -> String {
        if value >= 1000 {
            let k = value / 1000.0
            return k == floor(k) ? "\(Int(k))k" : String(format: "%.1fk", k)
        }
        return String(format: "%.0f", value)
    }

    private var progress: Double {
        guard state.goal > 0 else { return 0 }
        return min(state.commission / state.goal, 1.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
                Text("Provize za měsíc")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                if let label = state.monthLabel, !label.isEmpty {
                    Text("· \(label)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }

            if state.isHidden {
                Text("– – – –")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatCommission(state.commission))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text(state.currency)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [.orange, .yellow, .green],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * progress), height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text("0")
                Spacer()
                Text(scaleLabel(state.goal / 2))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(scaleLabel(state.goal))
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Widget (Live Activity)

struct CommissionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CommissionLiveActivityAttributes.self) { context in
            CommissionLiveActivityBannerView(context: context, state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    CommissionLiveActivityExpandedView(context: context, state: context.state)
                }
            } compactLeading: {
                Image(systemName: "creditcard.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                let progress = context.state.goal > 0 ? min(context.state.commission / context.state.goal, 1.0) : 0.0
                Text(context.state.isHidden ? "–" : "\(Int(progress * 100))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            } minimal: {
                CommissionLiveActivityMinimalView(context: context, state: context.state)
            }
        }
    }
}
