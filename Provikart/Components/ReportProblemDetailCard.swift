//
//  ReportProblemDetailCard.swift
//  Provikart
//
//  Popis problému v detailu reportu — barevná karta (bez levého pruhu).
//

import SwiftUI

struct ReportProblemDetailCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
                Text("Problém")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.orange.opacity(0.18),
                                    Color.orange.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.55),
                            Color.orange.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.25
                )
        }
        .shadow(color: .orange.opacity(0.12), radius: 12, y: 6)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Problém")
        .accessibilityValue(text)
    }
}
