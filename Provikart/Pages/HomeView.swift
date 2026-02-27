//
//  HomeView.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var authState: AuthState
    @State private var commission: CommissionResponse?
    @State private var commissionError: String?
    @State private var isLoadingCommission = false

    private let commissionService = CommissionService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    commissionBanner
                        .padding(.horizontal, 20)
                }
                .padding(.top, 16)
            }
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: authState.authToken) {
            await loadCommission()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PageHeaderBar(title: "Domů")
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - iOS-like Commission Banner

    private var commissionBanner: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            // TODO: případná navigace na detail provizí
        } label: {
            HStack(alignment: .top, spacing: 14) {
                // Leading badge icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                    Image(systemName: "creditcard")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Provize za aktuální měsíc")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)

                    Group {
                        if isLoadingCommission {
                            loadingSkeleton
                        } else if let err = commissionError {
                            errorRow(message: err)
                        } else if let c = commission {
                            valueRow(commission: c)
                        } else {
                            // Default placeholder
                            Text("Přihlaste se pro zobrazení provize.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()
                        .opacity(0.2)

                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(periodText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }
            .padding(16)
            .background(bannerBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityBannerLabel)
    }

    private var bannerBackground: some View {
        Group {
            if #available(iOS 15.0, *) {
                Color.clear
                    .background(.ultraThinMaterial)
            } else {
                Color(uiColor: .secondarySystemBackground)
            }
        }
    }

    private var periodText: String {
        if let c = commission, let label = c.month_label, !label.isEmpty {
            return "Období: \(label)"
        } else {
            return "Období: aktuální měsíc"
        }
    }

    private var accessibilityBannerLabel: String {
        if isLoadingCommission {
            return "Provize za aktuální měsíc, načítám"
        } else if let err = commissionError {
            return "Provize za aktuální měsíc, chyba: \(err)"
        } else if let c = commission {
            return "Provize za aktuální měsíc \(formatCommission(c.commission)) \(c.currency)"
        } else {
            return "Provize za aktuální měsíc"
        }
    }

    @ViewBuilder
    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color.primary.opacity(0.08),
                        Color.primary.opacity(0.16),
                        Color.primary.opacity(0.08)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(width: 140, height: 18)
                .redacted(reason: .placeholder)
                .shimmer()

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 100, height: 12)
                .redacted(reason: .placeholder)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func errorRow(message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer(minLength: 0)
            Button {
                Task { await loadCommission() }
            } label: {
                Text("Zkusit znovu")
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .controlSize(.mini)
        }
    }

    @ViewBuilder
    private func valueRow(commission c: CommissionResponse) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(formatCommission(c.commission))
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(c.currency)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data Loading

    private func loadCommission() async {
        let token = await MainActor.run { authState.authToken }
        guard let token else {
            await MainActor.run {
                commission = nil
                commissionError = "Pro zobrazení provize se přihlaste."
            }
            return
        }
        await MainActor.run {
            isLoadingCommission = true
            commissionError = nil
            commission = nil
        }

        do {
            let response = try await commissionService.fetchCommission(token: token)
            await MainActor.run {
                commission = response
                isLoadingCommission = false
            }
        } catch {
            await MainActor.run {
                commissionError = error.localizedDescription
                isLoadingCommission = false
            }
        }
    }

    private func formatCommission(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// Jednoduchý shimmer efekt pro skeleton (iOS 15+ fallback bez animace)
private extension View {
    @ViewBuilder
    func shimmer(active: Bool = true, duration: Double = 1.2) -> some View {
        if #available(iOS 15.0, *), active {
            self
                .overlay {
                    GeometryReader { proxy in
                        let size = proxy.size
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        .white.opacity(0.6),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .rotationEffect(.degrees(20))
                            .offset(x: -size.width)
                            .frame(width: size.width * 1.5)
                            .mask(self)
                            .animation(.linear(duration: duration).repeatForever(autoreverses: false), value: UUID())
                    }
                }
        } else {
            self
        }
    }
}

#Preview {
    HomeView()
}
