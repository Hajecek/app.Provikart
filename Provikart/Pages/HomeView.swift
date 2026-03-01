//
//  HomeView.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.openAddSheet) private var openAddSheet
    @State private var commission: CommissionResponse?
    @State private var commissionError: String?
    @State private var isLoadingCommission = false

    private let commissionService = CommissionService()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    commissionRow
                } header: {
                    Text("Provize")
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.visible)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Domů")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if let openAddSheet {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            openAddSheet()
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileBarButton()
                }
            }
        }
        .task {
            await loadCommission()
            // Periodické obnovení provize na pozadí (každých 30 s), dokud je obrazovka viditelná
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 30 sekund
                if Task.isCancelled { break }
                await loadCommission(silent: true)
            }
        }
        .refreshable {
            await loadCommission()
        }
    }

    // MARK: - Commission Row (iOS List style)

    private var commissionRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "creditcard.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28, alignment: .center)

                    Text("Aktuální měsíc")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }

                Group {
                    if isLoadingCommission {
                        loadingSkeleton
                    } else if let err = commissionError {
                        errorRow(message: err)
                    } else if let c = commission {
                        valueRow(commission: c)
                    } else {
                        Text("Přihlaste se pro zobrazení provize.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text(periodText)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityBannerLabel)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Button {
                Task { await loadCommission() }
            } label: {
                Text("Zkusit znovu")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
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

    /// Načte provizi z API. Při `silent: true` se nespouští loading stav – vhodné pro periodické obnovení na pozadí.
    private func loadCommission(silent: Bool = false) async {
        let token = await MainActor.run { authState.authToken }
        guard let token else {
            await MainActor.run {
                commission = nil
                commissionError = "Pro zobrazení provize se přihlaste."
            }
            return
        }
        if !silent {
            await MainActor.run {
                isLoadingCommission = true
                commissionError = nil
                commission = nil
            }
        }

        do {
            let response = try await commissionService.fetchCommission(token: token)
            await MainActor.run {
                commission = response
                isLoadingCommission = false
                WidgetDataStore.saveCommission(response.commission, currency: response.currency, monthLabel: response.month_label)
            }
        } catch {
            await MainActor.run {
                if !silent {
                    commissionError = error.localizedDescription
                }
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
        .environmentObject(AuthState())
}
