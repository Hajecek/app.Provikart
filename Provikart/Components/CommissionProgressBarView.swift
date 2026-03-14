//
//  CommissionProgressBarView.swift
//  Provikart
//
//  Graf postupu k cíli (100k) – tři barvy: oranžová, žlutá, zelená.
//

import SwiftUI

struct CommissionProgressBarView: View {
    var value: Double
    var goal: Double = 100_000
    var barCount: Int = 25
    var barHeight: CGFloat = 40
    var barSpacing: CGFloat = 3
    var showScaleLabels: Bool = true
    var scaleFontSize: CGFloat = 11

    @State private var animatedProgress: Double = 0

    private var targetProgress: Double {
        min(value / goal, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let barProgress = Double(index + 1) / Double(barCount)
                    let isFilled = barProgress <= animatedProgress
                    let height = barHeightFor(index: index)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(isFilled ? barColor(forIndex: index) : Color.primary.opacity(0.12))
                        .frame(height: height)
                }
            }
            .frame(height: barHeight)

            if showScaleLabels {
                HStack {
                    Text("0")
                    Spacer()
                    Text(scaleLabel(goal / 2))
                    Spacer()
                    Text(scaleLabel(goal))
                }
                .font(.system(size: scaleFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animatedProgress = targetProgress
            }
        }
        .onChange(of: value) { _, newValue in
            let newTarget = min(newValue / goal, 1.0)
            withAnimation(.easeInOut(duration: 0.6)) {
                animatedProgress = newTarget
            }
        }
        .onChange(of: goal) { _, _ in
            let newTarget = min(value / goal, 1.0)
            withAnimation(.easeInOut(duration: 0.6)) {
                animatedProgress = newTarget
            }
        }
    }

    private func scaleLabel(_ value: Double) -> String {
        if value >= 1000 {
            let k = value / 1000.0
            return k == floor(k) ? "\(Int(k))k" : String(format: "%.1fk", k)
        }
        return String(format: "%.0f", value)
    }

    private func barHeightFor(index: Int) -> CGFloat {
        barHeight
    }

    /// Tři barvy: od začátku oranžová, pak žlutá, ke konci zelená.
    private func barColor(forIndex index: Int) -> Color {
        let ratio = Double(index) / Double(max(barCount - 1, 1))
        if ratio < 1.0 / 3.0 {
            return .orange
        } else if ratio < 2.0 / 3.0 {
            return .yellow
        } else {
            return .green
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        CommissionProgressBarView(value: 35_000)
        CommissionProgressBarView(value: 72_000)
        CommissionProgressBarView(value: 100_000)
    }
    .padding()
}
