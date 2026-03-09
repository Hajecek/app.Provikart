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
    var barMinHeight: CGFloat = 18
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
                    Text("50k")
                    Spacer()
                    Text("100k")
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
    }

    private func barHeightFor(index: Int) -> CGFloat {
        let mid = barCount / 2
        let distFromCenter = abs(index - mid)
        let factor = 1.0 - (Double(distFromCenter) / Double(mid)) * 0.5
        return barMinHeight + (barHeight - barMinHeight) * factor
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
